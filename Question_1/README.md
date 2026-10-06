# Task 1: Secure Azure Storage Platform (Terraform + GitHub Actions)

A private storage platform for an internal application. **Nothing is reachable from the public internet**: the Storage Account and Key Vault only accept traffic through private endpoints inside a VNet, and the only identity that can read data is a managed identity with read-only access to one container. Infrastructure is deployed by a GitHub Actions pipeline that authenticates to Azure with OIDC (no stored credentials) and applies only from `main` after manual approval.

## Architecture

```
 GitHub Actions ──OIDC──► Entra ID ──► Azure Resource Manager
                                         │
 ┌───────────────────────────────────────┼───────────────────────────────────────┐
 │ rg-orzeh-<env>  (koreacentral)        ▼                                       │
 │                                                                               │
 │  vnet-orzeh-<env>  10.x0.0.0/16                                               │
 │  ├── snet-workload           10.x0.1.0/24   nsg: deny Internet in,           │
 │  │     (app would run here)                       allow 443 out → PE subnet   │
 │  └── snet-private-endpoints  10.x0.2.0/24   nsg: allow 443 from workload only │
 │        ├── pe-…-blob  ──► Storage Account  (public access Disabled, no keys)  │
 │        │                    └── container "appdata"                          │
 │        └── pe-…-vault ──► Key Vault        (RBAC model, public access off)    │
 │                                                                               │
 │  Private DNS zones (linked to the VNet, A records written by the PEs)         │
 │  ├── privatelink.blob.core.windows.net                                        │
 │  └── privatelink.vaultcore.azure.net                                          │
 │                                                                               │
 │  id-orzeh-<env>-blob-reader (user-assigned managed identity)                  │
 │    └── Storage Blob Data Reader  @ scope: container "appdata" only            │
 └───────────────────────────────────────────────────────────────────────────────┘

 rg-orzeh-tfstate: storzehtfstate3256 / tfstate  (remote state, blob-lease locking)
```

Inside the VNet, `<account>.blob.core.windows.net` resolves via CNAME to `<account>.privatelink.blob.core.windows.net`, which the linked private zone answers with the private endpoint IP. From the internet the name still resolves, but the account refuses the connection because public network access is disabled.

## Requirements → implementation

| Requirement | Where | How |
|---|---|---|
| RG, VNet, ≥2 subnets, NSGs | `modules/network` | Workload + private-endpoint subnets, an NSG on each. `private_endpoint_network_policies = "Enabled"` so the NSG is actually enforced on PE traffic. Both subnets have default outbound internet access disabled. |
| Storage: no public access, Private Endpoint only | `modules/storage` | `public_network_access = "Disabled"`, firewall default `Deny`, PE for `blob`. Also: shared keys/SAS disabled (Entra ID only), TLS 1.2, infrastructure double encryption, versioning + soft delete, copy scope limited to Private Link. |
| Private DNS zone linked to VNet | `modules/private_dns` | `privatelink.blob.core.windows.net` (+ `privatelink.vaultcore.azure.net` for Key Vault), VNet links, records created by PE DNS zone groups. |
| Key Vault: RBAC, no public access, PE | `modules/key_vault` | `rbac_authorization_enabled = true`, `public_network_access_enabled = false`, ACL default `Deny`, PE for `vault`, soft delete, purge protection in prod. |
| Managed identity: read blobs and nothing more | `modules/identity` | User-assigned identity with **Storage Blob Data Reader scoped to the single container**: no control-plane rights, no write, no other containers, no Key Vault access. |
| Remote state with locking | `bootstrap/`, `infra/backend.tf` | `azurerm` backend, Entra ID auth (`use_azuread_auth`), native blob-lease locking. The state account is versioned, soft-delete protected, has a `CanNotDelete` lock and `prevent_destroy`. |
| Reusable modules, dev/prod var files | `modules/*`, `infra/env/` | One root module composes five modules. `env/dev.tfvars` and `env/prod.tfvars` with separate state keys (`env/*.backend.hcl`). |
| PR: fmt, validate, security scan | `.github/workflows/q1-terraform.yml` → *Static checks* | `terraform fmt -check`, `validate` (infra + bootstrap), `tflint` (azurerm ruleset), **Trivy** IaC scan (checksum-verified binary), SARIF uploaded to the Security tab. |
| PR: plan visible to reviewers | *Plan (dev)*, *Plan (prod)* | Plan posted as a sticky PR comment (one per env, updated on each push), plus job summary and an artifact. |
| Apply only after approval, only from main | `_q1-terraform-apply.yml` | Runs in GitHub environments `dev` / `prod` with required reviewers and a deployment-branch policy of `main`. A step also refuses any ref other than `main`, and `main` is protected (PR + required checks, no force push). |
| OIDC, no client secrets | `bootstrap/identities.tf` | Entra app registrations with federated credentials for the exact GitHub subjects, in GitHub's **immutable subject format** (`repo:<owner>@<owner_id>/<repo>@<repo_id>:…`). The repo holds only non-secret IDs as Actions *variables*; there are **no Actions secrets**. |

## Repository layout

```
.github/workflows/
├── q1-terraform.yml            # PR checks + plan; on main: plan → apply dev → apply prod
└── _q1-terraform-apply.yml     # reusable apply job (environment-gated)
Question_1/
├── bootstrap/                  # one-time: state backend, OIDC identities, GitHub environments/rules/variables
├── infra/                      # root module (composition only, no resources besides RG + suffix)
│   └── env/{dev,prod}.tfvars, {dev,prod}.backend.hcl
├── modules/{network,private_dns,storage,key_vault,identity}/
├── evidence/                   # saved plan output for submission
├── .tflint.hcl
```

## How to run

### Prerequisites
- Terraform ≥ 1.9 (CI uses 1.16.5), Azure CLI, GitHub CLI.
- Azure: Owner on the subscription and permission to create Entra app registrations (needed only for the bootstrap).
- The repository exists and `main` has at least one commit (branch protection needs the branch).

### 1. Bootstrap (once, from a laptop)

```bash
az login
az account set --subscription "<subscription-id>"
export GITHUB_TOKEN=$(gh auth token)        # needs repo admin; used only by the github provider

cd Question_1/bootstrap
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

This creates the state backend, the two pipeline identities with their federated credentials and role assignments, the `dev` and `prod` GitHub environments (required reviewer, `main` only), branch protection on `main`, and the Actions variables `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_PLAN` (repo) and `AZURE_CLIENT_ID_APPLY` (per environment).

Optionally, move the bootstrap's own state into the backend it just created: add a `backend "azurerm"` block with key `bootstrap.tfstate` and run `terraform init -migrate-state`.

> Role assignments can take a few minutes to propagate. If the next step returns `403 AuthorizationPermissionMismatch` on the state container, wait and retry.

### 2. Plan / apply locally (optional)

```bash
cd Question_1/infra
terraform init -backend-config=env/dev.backend.hcl          # use -reconfigure when switching env
terraform plan -var-file=env/dev.tfvars -out=dev.tfplan
terraform show -no-color dev.tfplan > ../evidence/dev-plan.txt
terraform apply dev.tfplan

terraform init -reconfigure -backend-config=env/prod.backend.hcl
terraform plan -var-file=env/prod.tfvars -out=prod.tfplan
terraform show -no-color prod.tfplan > ../evidence/prod-plan.txt
```

> **New environments:** the pipeline's plan identity is read-only on state, so it cannot create a state file that does not exist yet (`init` writes an empty state for a new key → `403`). Initialise each environment's state once, which step 2 does (`terraform init -backend-config=env/<env>.backend.hcl`).

### 3. Through the pipeline (normal path)
1. Open a PR into `main`. *Static checks* runs, then *Plan (dev)* and *Plan (prod)* comment their plans on the PR.
2. Merge after review. On `main`, the plans are re-created and uploaded.
3. *Apply (dev)* waits for approval in the `dev` environment, then applies **the saved plan**. *Apply (prod)* follows, with its own approval.

### 4. Verify private-only access

```bash
# Public access really is off
az storage account show -n <account> --query "{public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}"
az keyvault show -n <vault> --query "properties.publicNetworkAccess"

# The private DNS zone holds the private IP
az network private-dns record-set a list -g rg-orzeh-dev -z privatelink.blob.core.windows.net -o table

# From inside the VNet (e.g. a VM in snet-workload): resolves to 10.10.2.x
nslookup <account>.blob.core.windows.net

# From the internet: name resolves, but the request is refused (403 / public access disabled)
curl -sI https://<account>.blob.core.windows.net/appdata?restype=container
```

### 5. Tear down

```bash
terraform -chdir=Question_1/infra destroy -var-file=env/dev.tfvars
```

Dev has purge protection off so it can be removed and recreated. Prod has purge protection on, so a destroyed prod Key Vault stays soft-deleted for 90 days. That is intentional.

## Design decisions

**One root module + per-environment tfvars, not one folder per environment.** Dev and prod run the same code, so they cannot drift in structure, only in values. Each environment has its own state file (`question1/dev.tfstate`, `question1/prod.tfstate`), so a dev change can never touch prod state. I chose separate state keys over Terraform workspaces because the backend file makes the target explicit in every `init` and in the pipeline.

**Small modules with one responsibility each.** Network, DNS, storage, Key Vault and identity change for different reasons and are tested separately. The root module only wires outputs to inputs. Adding another private service (e.g. a database) means another module plus another key in the DNS zone map.

**Secure defaults, explicit opt-out for dev.** Module and root defaults are the production-safe values (GZRS, 30/90-day retention, purge protection on). `dev.tfvars` *opts out* deliberately (LRS, 7 days, purge protection off). Forgetting a variable therefore produces the safe result, never the weak one.

**Entra ID everywhere, no keys.** Shared-key access is disabled on both storage accounts, the backend uses `use_azuread_auth`, and the provider uses `storage_use_azuread`. No access key exists that could leak through state, logs or CI variables.

**Management plane only.** With public access disabled, the storage data plane is unreachable from GitHub-hosted runners. The container is created through Azure Resource Manager (`storage_account_id`), and `features.storage.data_plane_available = false` stops the provider from making data-plane calls that would time out. Without these settings the pipeline would fail when it reads the storage account.

**Two pipeline identities, least privilege per stage.**

Subjects use GitHub's **immutable format**, which is the default for repositories created after 2026-07-15 (this repo reports `use_immutable_subject: true`):

```
repo:SaifRiaz3256@167188461/orzeh-assessment@1407727082:environment:prod
     └─ owner@owner_id ─────┘ └─ repo@repo_id ────────┘ └─ job context ┘
```

The numeric IDs are read from the GitHub API by Terraform (`data.github_user`, `data.github_repository`), not hard-coded. Because IDs are never reused, deleting or renaming the repo or account cannot let someone recreate the same name and obtain matching tokens (*subject recycling*). With the old name-only format, they could.

| Identity | Trusted OIDC subjects (prefix `repo:SaifRiaz3256@167188461/orzeh-assessment@1407727082`) | Azure permissions |
|---|---|---|
| `gh-orzeh-assessment-tf-plan` | `…:pull_request`, `…:ref:refs/heads/main` | Reader (subscription), Storage Blob Data **Reader** on the state container |
| `gh-orzeh-assessment-tf-apply` | `…:environment:dev`, `…:environment:prod` | Contributor + Role Based Access Control Administrator (**ABAC-restricted** to creating/deleting *Storage Blob Data Reader* assignments for service principals), Blob Data Contributor on state |

Code in a pull request, including a malicious one, can only obtain the read-only identity. The apply identity can only be used by a job that has passed the environment approval gate, and its client ID is stored as an *environment* variable. Thanks to the ABAC condition the pipeline can grant the one role the design needs, but cannot make itself Owner.

**Plan without lock, apply the saved plan.** The plan identity cannot write state, so plans run with `-lock=false`. This is safe because apply uses the *saved* plan artifact: Terraform takes the lock at apply time and rejects the plan as stale if state changed after it was created. Reviewers approve exactly what will be applied.

**Pipeline hardening.** All actions are pinned to full commit SHAs. `permissions` are minimal per job (`id-token: write` only where OIDC is needed). Every job has a timeout. A concurrency group per ref (and per environment for apply) prevents overlapping runs. Plan artifacts are kept for only 5 days because plan files can contain sensitive values. The PR trigger has no `paths` filter, because the required status checks must report on every PR.

**Region guard.** The subscription's Azure Policy only allows certain regions. A Terraform `precondition` fails the plan early with a clear message instead of a policy-deny error halfway through an apply.

## Security scan results

**Trivy 0.75.0** (`trivy config Question_1`, the successor to tfsec): **0 failures**. Accepted findings are ignored with `#trivy:ignore:<ID>` directly above the resource, with the reason written in the comment just above:

| Trivy ID | Resource | Reason |
|---|---|---|
| AZU-0012 (critical) | state storage | Public endpoint is needed by GitHub-hosted runners. Access is Entra ID + RBAC only, with shared keys disabled (see production changes). |
| AZU-0057 | both storage accounts | Logging needs diagnostic settings + Log Analytics (see production changes). |
| AZU-0060 | both storage accounts | Customer-managed keys (see production changes). |
| GIT-0004 | branch protection | Commit signing not yet configured for the single maintainer. |

The app storage account passes AZU-0012 because it has public network access disabled and a `Deny` firewall.

In CI, Trivy is downloaded from the official release and **verified against a pinned SHA-256**, instead of using `aquasecurity/trivy-action`: that action's tags were hijacked in a 2026 supply-chain attack, and a checksum-pinned binary cannot be swapped silently. Results are also uploaded as SARIF to the repository's **Security** tab.

`tflint` (azurerm ruleset 0.32.0) is clean. `prevent_destroy` is set on the state account. In the modules it is ignored with a comment, because it cannot vary per environment and dev must be destroyable.

## Assumptions

1. **Single subscription, single region (`koreacentral`).** Dev and prod are separate resource groups. In a real organisation they would be separate subscriptions under a management group, each with its own pipeline identity.
2. **No compute is deployed.** `snet-workload` is where the application (VM, App Service via VNet integration, AKS…) would run and attach the managed identity.
3. **GitHub-hosted runners.** They reach Azure Resource Manager (always public) but not private data planes. This is why the state account keeps a public, RBAC-only endpoint and why storage is managed through the management plane only.
4. **Single maintainer.** Environment reviewers and PR approvals use one person, so self-review is allowed and 0 PR approvals are required. Both are settings in `bootstrap/github.tf` to tighten for a team.
5. **Key Vault starts empty.** No secrets are created by Terraform: writing secrets requires data-plane access (not available from outside the VNet) and would put secret values in state. Applications or a release process inside the network would populate it.
6. **Names are fictional** (`orzeh`) and contain no real organisation, credentials or secrets.
7. **The repository uses immutable OIDC subjects** (verified via `GET /repos/{owner}/{repo}/actions/oidc/customization/sub`). The GitHub Terraform provider (6.13) cannot yet manage this toggle, so it is a precondition rather than managed configuration.
8. **The repository will be public at submission**, which is required for environment protection rules and branch protection on a free GitHub plan.

## Before using this in production

**Network & access**
- **Self-hosted runners inside the VNet** (VM scale set or Container Apps jobs). Then put the *state* account behind a private endpoint too and remove its public endpoint. (This is the same issue as Task 3 / Scenario 4.)
- **Hub-and-spoke**: central hub with Azure Firewall for controlled egress, **Azure DNS Private Resolver** so on-prem and other VNets resolve private endpoints, and private DNS zones owned centrally (in policy-driven landing zones, PE DNS records are created by Azure Policy `DeployIfNotExists`).
- **Azure Policy** at management-group level: deny public network access on Storage/Key Vault, require private endpoints, enforce allowed SKUs and regions.

**Data protection**
- **Customer-managed keys** for storage encryption (key in this Key Vault/Managed HSM, accessed by a managed identity), with key rotation.
- **Diagnostic settings** for Storage, Key Vault, NSG flow logs → Log Analytics. Alerts on authorization failures and on Key Vault access.
- **Microsoft Defender for Storage and Key Vault**, plus resource locks (`CanNotDelete`) on prod resource groups.
- Blob immutability/legal hold or object replication if the data requires it.

**Pipeline & IaC**
- Separate subscriptions and **one apply identity per environment**, scoped to that environment's subscription, ideally pre-created resource groups and RG-level roles instead of subscription-level Contributor.
- Version the modules (tags or a private registry) so environments can pin and promote module versions.
- `terraform test` / Terratest for modules, **Infracost** on PRs, OPA/Conftest policies on the plan JSON, and scheduled **drift detection** (`plan -detailed-exitcode` nightly, alert on drift).
- Require ≥ 1 PR approval from someone other than the author, CODEOWNERS for `modules/`, signed commits, and `prevent_self_review` on the prod environment.
- Break-glass procedure for state recovery: blob versioning is enabled, so a corrupted state can be restored from a previous version.

## Evidence

Save plan output in `evidence/` (see step 2):
- `evidence/dev-plan.txt`
- `evidence/prod-plan.txt`
- (optional) `evidence/dev-apply.txt` and screenshots of the PR plan comment and the approval gate.
