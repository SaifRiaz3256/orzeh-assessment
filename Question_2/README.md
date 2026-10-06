# Task 2: Fix a Broken Kubernetes Deployment

The original manifest ([original/broken.yaml](original/broken.yaml)) is meant to run an API on AKS behind a Service. It **does not deploy at all**, and once the blocking bugs are fixed it still **serves no traffic**. It also has several security and reliability problems.

- **Corrected manifests:** [k8s/](k8s/) (Kustomize: `base` + `aks` and `kind` overlays)
- **Proof:** the failures were reproduced on a real cluster ([evidence/original-failures.txt](evidence/original-failures.txt)), and the fix passes a 16-check end-to-end test ([evidence/kind-test-output.txt](evidence/kind-test-output.txt)), including **0 failed requests during a rolling restart**.

## 1. Issues found

### A. Why it does not work (each one reproduced on kind)

| # | Issue | Why it matters | Fix |
|---|---|---|---|
| 1 | Deployment `selector` is `app: auction-api` but pod labels are `app: auctions-api` | The API server **rejects the Deployment** (`selector does not match template labels`), so no pods are ever created. | One label set (`app.kubernetes.io/name: auction-api`) used by selector, template, Service, PDB, HPA and policies. |
| 2 | Service selector `app: auction-api` matches no pod (pods are `auctions-api`) | Even with pods running, the Service has **no endpoints**, so every call fails. | Same consistent label as #1. |
| 3 | Readiness probe on port **80**, container listens on **8080** | Probe gets *connection refused*, the pod is **never Ready**, and it is never added to the Service. | Probes use the **named port** `http` (→ 8080). |
| 4 | Service `targetPort: 80`, container listens on **8080** | Traffic reaches the pod on a closed port: *connection refused* (curl exit 7). | `targetPort: http` (named), so it cannot drift from `containerPort`. |
| 5 | Namespace `auctions` is not defined | `kubectl apply` fails on a fresh cluster (`namespaces "auctions" not found`). | `namespace.yaml` is part of the set (and carries the Pod Security labels, see #9). |

### B. Security

| # | Issue | Why it matters | Fix |
|---|---|---|---|
| 6 | `DB_PASSWORD` in **plaintext** in the manifest | The secret sits in Git history and is readable by anyone with `get deployment` or via `kubectl describe`; it cannot be rotated without a code change. | `secretKeyRef` to Secret `auction-api-db`. On AKS that Secret is **synced from Azure Key Vault** by the Secrets Store CSI driver using **Workload Identity** (no credentials in the cluster config). The leaked password must also be **rotated**, since it is in the repo's history. |
| 7 | Image tag `:latest` | Mutable: two pods can run different code, a rollback re-pulls the "same" tag, and you cannot tell what is running. It also implies `imagePullPolicy: Always`. | Immutable release tag `1.0.0`, and CI pins the **digest** (`kustomize edit set image …@sha256:…`); ACR tag immutability on. |
| 8 | No `securityContext` | The container may run as **root** with a writable filesystem, privilege escalation and default Linux capabilities, so a compromised app has far more power than it needs. | Non-root UID 10001, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, drop **ALL** capabilities, `seccompProfile: RuntimeDefault`; writable `/tmp` via `emptyDir`. |
| 9 | No Pod Security Standard on the namespace | Nothing stops a privileged or root pod from being deployed into the namespace later. | Namespace labels `pod-security.kubernetes.io/enforce: restricted` (verified: a privileged pod is **rejected**). |
| 10 | Uses the `default` ServiceAccount with an **auto-mounted API token** | If the app is compromised, the attacker gets a Kubernetes API token for free. | Dedicated `auction-api` ServiceAccount, `automountServiceAccountToken: false`. |
| 11 | No NetworkPolicy | Any pod in the cluster can call the API, and the API can reach anything (lateral movement, data exfiltration). | Default-deny (ingress + egress); allow ingress only from the ingress controller namespace and labelled clients on the HTTP port; allow egress only to DNS and the database. |

### C. Reliability and operations

| # | Issue | Why it matters | Fix |
|---|---|---|---|
| 12 | `replicas: 1` | Single point of failure: a node drain, AKS upgrade or crash means an outage. | HPA with **minReplicas 3** (max 10). `replicas` is removed from the Deployment so `kubectl apply`/GitOps does not fight the autoscaler. |
| 13 | No resource requests or limits | **BestEffort** QoS: the pod is evicted first under pressure, can starve its neighbours, the scheduler places it blindly, and an HPA cannot work. | Requests (100m CPU, 128Mi) and limits (500m, 256Mi, ephemeral storage) → **Burstable** QoS. |
| 14 | No liveness or startup probe | A hung process (deadlock) is never restarted; with only a readiness probe it just silently drops out of the Service. | `startupProbe` (up to 2 min to start), `livenessProbe` (TCP: process accepts connections), `readinessProbe` (HTTP `/health`). |
| 15 | No PodDisruptionBudget | A node drain during an AKS upgrade can evict **all** replicas at once. | PDB `maxUnavailable: 1`. |
| 16 | No spreading across nodes or zones | All replicas can land on one node or zone, which then becomes the single point of failure. | `topologySpreadConstraints` on `zone` and `hostname`. |
| 17 | Default rollout and shutdown behaviour | `maxUnavailable: 25%` and an immediate SIGTERM drop in-flight requests during deploys. | `maxSurge: 1`, `maxUnavailable: 0`, `minReadySeconds`, `preStop` sleep 5s, 30s grace period (verified: **0 of 60** requests failed during a rolling restart). |
| 18 | Unnamed ports, a single ad-hoc label | Port numbers duplicated in four places is what caused #3 and #4; there is no consistent way to select or report on the app. | Named port `http` referenced everywhere; `app.kubernetes.io/*` recommended labels. |

## 2. Corrected manifest set

```
k8s/
├── base/                         # environment-neutral
│   ├── namespace.yaml            # + Pod Security "restricted" (enforce/audit/warn)
│   ├── serviceaccount.yaml       # dedicated SA, no token
│   ├── deployment.yaml           # fixed labels/ports, probes, resources, securityContext, spread, rollout
│   ├── service.yaml              # ClusterIP, targetPort: http
│   ├── pdb.yaml                  # maxUnavailable: 1
│   ├── hpa.yaml                  # 3–10 replicas on CPU
│   ├── networkpolicy.yaml        # default deny + minimal allows
│   └── kustomization.yaml
└── overlays/
    ├── aks/                      # Key Vault secret via Secrets Store CSI + Workload Identity, image tag
    └── kind/                     # local test: stand-in image, no cloud dependencies
```

**Deploy to AKS** (cluster prerequisites below):
```bash
kubectl apply -k Question_2/k8s/overlays/aks
```

**Test locally** (creates kind cluster `orzeh-q2` if missing):
```bash
./Question_2/test/kind-test.sh
kind delete cluster --name orzeh-q2
```

## 3. Verification

| Check | Original | Corrected |
|---|---|---|
| Deploys on a clean cluster | ❌ namespace missing, Deployment rejected | ✅ |
| Serves traffic through the Service | ❌ probe + targetPort on wrong port | ✅ HTTP 200 |
| kube-score | **12 CRITICAL** | **0** (2 documented ignores, see §4) |
| Trivy (misconfiguration) | **17 findings** (3 high, 4 medium, 10 low) | **0** |
| kubeconform (strict, K8s 1.33 + CRD schemas) | — | all resources valid (both overlays) |
| End-to-end on kind | — | **16/16 passed** |

The end-to-end test ([test/kind-test.sh](test/kind-test.sh)) checks, against a real API server:
3 Ready replicas via the HPA · 3 Service endpoints on port 8080 · a privileged pod **rejected** by Pod Security Admission · labelled client → **200**, unlabelled pod and other-namespace pod → **blocked** · `DB_PASSWORD` from a Secret with no plaintext value · no service account token · UID 10001 with read-only root FS · Burstable QoS · PDB allows 1 disruption · **0/60 failed requests** during `rollout restart`.

`democr.azurecr.io` is fictional, so the kind overlay replaces the image with `hashicorp/http-echo` (pinned by digest): a non-root static binary that listens on 8080 and serves `/health`, like the API. Everything else is the same manifest that goes to AKS.

## 4. Design decisions

- **Liveness ≠ readiness.** Readiness calls `/health` (which may check the database); liveness only checks the TCP port. If the database is slow, pods leave the Service but are **not** restarted in a loop. That would turn a database incident into an API outage.
- **No `replicas` with an HPA.** A static count is re-applied on every deploy and resets the autoscaler. The HPA's `minReplicas: 3` sets the floor.
- **`imagePullPolicy: IfNotPresent`.** With an immutable, digest-pinned image, `Always` adds nothing but makes every pod start depend on registry availability. kube-score's opinion is ignored via annotation, with that reason.
- **Topology spread instead of pod anti-affinity.** `topologySpreadConstraints` on zone and hostname (`ScheduleAnyway`) spread evenly but still schedule if a zone is short of capacity; hard anti-affinity could block scale-out. kube-score's anti-affinity check is ignored with that reason.
- **NetworkPolicy covers clients too.** `default-deny-all` also blocks egress of client pods in the namespace, so labelled clients get a matching egress rule. The end-to-end test caught this.
- **Secrets.** The Secret is synced from Key Vault by the CSI driver (the volume must be mounted for syncing to happen). Environment variables only refresh on pod restart, so rotation needs a rollout (or reading the mounted file). The better long-term option is **passwordless** database auth with Entra ID through the same Workload Identity.

## 5. Assumptions

1. The application listens on **8080** (its declared `containerPort`) and exposes **`/health`**; the probe port and Service `targetPort` were the mistakes, not the container port.
2. `/health` reports readiness (it may include dependency checks).
3. The database is **Azure Database for PostgreSQL** (TCP 5432) reached via a private endpoint inside `10.0.0.0/8`.
4. Ingress is the **AKS application routing add-on** (namespace `app-routing-system`); the Service stays `ClusterIP`.
5. Resource sizes (100m/128Mi requests) are starting points to be tuned from load tests and VPA recommendations.
6. Client IDs, tenant ID and Key Vault name in the AKS overlay are placeholders (`00000000-…`, `kv-orzeh-prod`); all names are fictional.

## 6. AKS prerequisites

```bash
az aks update -g <rg> -n <aks> --enable-oidc-issuer --enable-workload-identity
az aks enable-addons -g <rg> -n <aks> --addons azure-keyvault-secrets-provider
az aks update -g <rg> -n <aks> --attach-acr democr          # kubelet gets AcrPull (no imagePullSecrets)

# Workload identity for the pod, federated with the auction-api service account
az identity create -g <rg> -n id-auction-api
az identity federated-credential create -g <rg> --identity-name id-auction-api -n auction-api \
  --issuer "$(az aks show -g <rg> -n <aks> --query oidcIssuerProfile.issuerUrl -o tsv)" \
  --subject system:serviceaccount:auctions:auction-api --audiences api://AzureADTokenExchange
az role assignment create --assignee <identity-principal-id> --role "Key Vault Secrets User" --scope <key-vault-id>
```
Then put the identity's client ID and the tenant ID into `overlays/aks` (`workload-identity.yaml`, `secretproviderclass.yaml`).

## 7. Further production hardening

- **Image supply chain:** scan in CI (Trivy), sign images (Notation) and verify at admission (Ratify / Azure Policy for AKS); allow only `democr.azurecr.io`.
- **Policy as code:** Azure Policy for AKS (Gatekeeper) to enforce the same rules cluster-wide (no `:latest`, required probes/limits, no privileged pods).
- **Passwordless database access** with Entra ID via Workload Identity, removing the password entirely.
- **FQDN-aware egress** (Azure CNI powered by Cilium or Azure Firewall) instead of a broad `10.0.0.0/8` CIDR.
- **Observability:** a metrics endpoint + ServiceMonitor, SLO-based alerts; a `PriorityClass` for the API.
