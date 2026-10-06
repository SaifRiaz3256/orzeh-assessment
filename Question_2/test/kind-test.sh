#!/usr/bin/env bash
# End-to-end test of the corrected manifests on a local kind cluster.
#
#   ./test/kind-test.sh            # uses (or creates) kind cluster "orzeh-q2"
#   CLUSTER=other ./test/kind-test.sh
#
# Every check prints PASS/FAIL; the script exits non-zero if any check fails.
set -uo pipefail

CLUSTER="${CLUSTER:-orzeh-q2}"
CTX="kind-${CLUSTER}"
NS=auctions
SVC_URL="http://auction-api.${NS}.svc/health"
CURL_IMAGE="curlimages/curl:8.11.1"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
K=(kubectl --context "$CTX")
PASS=0
FAIL=0

check() { # $1 = description, $2 = expected, $3 = actual
  if [[ "$3" == "$2" ]]; then
    echo "  PASS  $1 (got: $3)"; PASS=$((PASS + 1))
  else
    echo "  FAIL  $1 (expected: $2, got: $3)"; FAIL=$((FAIL + 1))
  fi
}

# Runs a short-lived, Pod-Security-"restricted"-compliant curl pod and prints its output.
client() { # $1 = name, $2 = namespace, $3 = extra label line ("" for none), $4 = shell command
  "${K[@]}" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: $2
  labels:
    test: client
    $3
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: curl
      image: ${CURL_IMAGE}
      command: ["sh", "-c", "$4"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
EOF
  "${K[@]}" -n "$2" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$1" --timeout=120s >/dev/null 2>&1 ||
    "${K[@]}" -n "$2" wait --for=jsonpath='{.status.phase}'=Failed "pod/$1" --timeout=5s >/dev/null 2>&1
  "${K[@]}" -n "$2" logs "$1" 2>/dev/null | tail -1
  "${K[@]}" -n "$2" delete pod "$1" --wait=false >/dev/null 2>&1
}

echo "== 0. Cluster ${CTX}"
kind get clusters | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 120s
"${K[@]}" get nodes --no-headers | awk '{print "  node", $1, $2, $5}'

echo "== 1. Deploy (kustomize overlay: kind)"
"${K[@]}" apply -k "$HERE/k8s/overlays/kind"
# Random throwaway DB password for the test; real environments sync it from Key Vault.
"${K[@]}" -n "$NS" create secret generic auction-api-db \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 18)" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

echo "== 2. HPA brings the Deployment to minReplicas=3 and all pods become Ready"
for _ in $(seq 1 60); do
  ready=$("${K[@]}" -n "$NS" get deploy auction-api -o jsonpath='{.status.readyReplicas}')
  [[ "${ready:-0}" == "3" ]] && break
  sleep 3
done
"${K[@]}" -n "$NS" rollout status deploy/auction-api --timeout=120s >/dev/null
check "ready replicas" "3" "$("${K[@]}" -n "$NS" get deploy auction-api -o jsonpath='{.status.readyReplicas}')"
check "HPA minReplicas" "3" "$("${K[@]}" -n "$NS" get hpa auction-api -o jsonpath='{.spec.minReplicas}')"

echo "== 3. Service routes to the pods on the container port"
check "ready endpoints" "3" "$("${K[@]}" -n "$NS" get endpointslices -l kubernetes.io/service-name=auction-api \
  -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' | wc -c | tr -d ' ')"
check "endpoint port" "8080" "$("${K[@]}" -n "$NS" get endpointslices -l kubernetes.io/service-name=auction-api -o jsonpath='{.items[0].ports[0].port}')"

echo "== 4. Pod Security Admission (restricted) rejects a root/privileged pod"
psa=$("${K[@]}" -n "$NS" run psa-root-test --image=busybox:1.37 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c","image":"busybox:1.37","securityContext":{"privileged":true,"runAsUser":0}}]}}' 2>&1 || true)
check "privileged pod rejected" "rejected" "$(grep -q 'violates PodSecurity "restricted' <<<"$psa" && echo rejected || echo "admitted: $psa")"

echo "== 5. NetworkPolicy"
check "labelled client in namespace -> 200" "200" \
  "$(client np-allowed "$NS" 'auction-api-client: "true"' "curl -s -m 5 -o /dev/null -w '%{http_code}' ${SVC_URL}; echo")"
check "unlabelled pod in namespace -> blocked (namespace default-deny egress)" "blocked" \
  "$(client np-denied "$NS" '' "curl -s -m 5 -o /dev/null ${SVC_URL} && echo reached || echo blocked")"
check "pod in another namespace -> blocked (API ingress policy)" "blocked" \
  "$(client np-other default '' "curl -s -m 5 -o /dev/null ${SVC_URL} && echo reached || echo blocked")"

echo "== 6. Secret handling"
check "DB_PASSWORD comes from a Secret" "auction-api-db" \
  "$("${K[@]}" -n "$NS" get deploy auction-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}')"
check "no plaintext value in the Deployment" "" \
  "$("${K[@]}" -n "$NS" get deploy auction-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].value}')"
check "service account token not mounted" "false" \
  "$("${K[@]}" -n "$NS" get pod -l app.kubernetes.io/name=auction-api -o jsonpath='{.items[0].spec.automountServiceAccountToken}')"

echo "== 7. Runtime security context"
pod=$("${K[@]}" -n "$NS" get pod -l app.kubernetes.io/name=auction-api -o jsonpath='{.items[0].metadata.name}')
check "runs as UID 10001 (non-root)" "10001" "$("${K[@]}" -n "$NS" get pod "$pod" -o jsonpath='{.spec.securityContext.runAsUser}')"
check "read-only root filesystem" "true" "$("${K[@]}" -n "$NS" get pod "$pod" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}')"
check "QoS class" "Burstable" "$("${K[@]}" -n "$NS" get pod "$pod" -o jsonpath='{.status.qosClass}')"

echo "== 8. PodDisruptionBudget"
check "disruptions allowed" "1" "$("${K[@]}" -n "$NS" get pdb auction-api -o jsonpath='{.status.disruptionsAllowed}')"

echo "== 9. Zero-downtime rolling restart (60 requests over ~45s while pods are replaced)"
"${K[@]}" -n "$NS" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: rollout-probe
  namespace: ${NS}
  labels: { test: client, auction-api-client: "true" }
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: { runAsNonRoot: true, runAsUser: 100, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: curl
      image: ${CURL_IMAGE}
      command: ["sh", "-c", "sleep 3; ok=0; bad=0; for i in \$(seq 1 60); do c=\$(curl -s -m 2 -o /dev/null -w '%{http_code}' ${SVC_URL}); [ \"\$c\" = 200 ] && ok=\$((ok+1)) || bad=\$((bad+1)); sleep 0.75; done; echo \"ok=\$ok failed=\$bad\""]
      securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
EOF
"${K[@]}" -n "$NS" wait --for=condition=Ready pod/rollout-probe --timeout=60s >/dev/null
sleep 4
"${K[@]}" -n "$NS" rollout restart deploy/auction-api >/dev/null
"${K[@]}" -n "$NS" rollout status deploy/auction-api --timeout=180s >/dev/null
"${K[@]}" -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded pod/rollout-probe --timeout=120s >/dev/null
check "requests failed during rollout" "failed=0" "$("${K[@]}" -n "$NS" logs rollout-probe | grep -o 'failed=[0-9]*')"
echo "  ($("${K[@]}" -n "$NS" logs rollout-probe))"
"${K[@]}" -n "$NS" delete pod rollout-probe --wait=false >/dev/null

echo
echo "RESULT: ${PASS} passed, ${FAIL} failed"
echo "Clean up with: kind delete cluster --name ${CLUSTER}"
[[ "$FAIL" -eq 0 ]]
