## Scenario 1 — Fails only in production.

**An application works in Dev, QA, and UAT. Immediately after a production release it returns HTTP 500 errors. The application code is identical across environments.**

The code is identical, so the cause is something that differs between environments: configuration, secrets, identity, network, data or scale.

**Stabilise**
1. Confirm the scope in monitoring. Is it every endpoint or one, every instance or some, and did it start exactly at the release? In Application Insights:
   `requests | where timestamp > ago(1h) and resultCode == "500" | summarize count() by name, cloud_RoleInstance, bin(timestamp, 5m)`
2. Roll back if the release is clearly the trigger and a rollback is safe. First check that no database migration ran that the old version can't work with. Then run `kubectl rollout undo deployment/<app> -n <ns>`, or redeploy the previous artifact or swap the App Service slot back. Users first, root cause second.

**Diagnose**
3. Read the real error. The stack trace usually names the failing dependency.
   `kubectl logs deploy/<app> -n <ns> --since=30m | grep -iE "error|exception" | head -50`
   Also check the Application Insights `exceptions` table and failed calls in `dependencies | where success == false`.
4. Compare production with UAT, because that is where the difference lives:
   - **Config:** environment variables, app settings, feature flags and connection strings (`kubectl get deploy <app> -o yaml`, `az webapp config appsettings list`). A missing or misspelled key is the most common cause.
   - **Secrets:** does the secret exist in the prod Key Vault under the expected name, and is it still valid?
   - **Identity:** does the prod managed identity have the roles it needs? `az role assignment list --assignee <principal-id> --all`. A 403 from Key Vault or storage often comes back to the user as a 500.
   - **Network:** can the pod resolve and reach the database privately? `kubectl exec <pod> -- nslookup <db-host>`, then a TCP test to the port. Prod often has private endpoints or firewall rules that UAT doesn't.
   - **Data and schema:** were the migrations applied in prod? Real data can also hit edge cases (nulls, large records) that test data never did.
   - **Capacity:** `kubectl describe pod` shows OOMKilled pods and restarts, and `kubectl top pod` shows usage. Prod load can exhaust connection pools or memory limits.
5. Confirm the cause by reproducing it in a prod-like slot or a canary pod with prod configuration, not by trying fixes on live traffic.

**Fix and prevent**
6. Fix forward through the pipeline, with no hand edits in prod, and watch the 5xx rate return to its baseline.
7. To stop it happening again:
   - Keep environment config in code, so differences show up in review.
   - Promote the same artifact through every stage.
   - Run smoke tests after each deployment, and roll back automatically if they fail.
   - Release through canaries.
   - Write a short blameless postmortem.

## Scenario 2 — Corrupted Terraform state.

**During a production terraform apply, the state file became corrupted. Some resources exist in Azure but are now missing from state. Other engineers are waiting to deploy.**

The goal is a state that matches what exists in Azure again, without creating duplicates or destroying anything. The other engineers wait until then: waiting is safer than several people writing to a broken state.

**Contain**
1. Stop all writes. Tell the team, pause the pipelines for that stack, and leave the state lock in place for now. Give the waiting engineers an estimate.
2. Keep the evidence. Save the full apply log, which lists every `Creation complete … [id=…]`. Also save a copy of the current state file:
   `az storage blob download --account-name <state-sa> -c tfstate -n prod.tfstate -f corrupted.tfstate --auth-mode login`

**Restore**
3. Look for `errored.tfstate` in the working directory of the failed run. Terraform writes this file when it can't save state to the backend, and it's usually the most complete copy. If it's valid: `terraform state push errored.tfstate`.
4. Otherwise, restore the last good version from blob versioning:
   `az storage blob list --account-name <state-sa> -c tfstate --prefix prod.tfstate --include v -o table`
   Download the version from just before the apply and check it: `terraform show -json` should parse it, and its lineage should match. Then upload it with `terraform state push`.

**Reconcile**
5. The restored state doesn't know about resources created during the failed apply. Find them in the apply log and in Azure (`az resource list -g <rg> -o table`), and adopt them with `import` blocks (or `terraform import`):
   ```hcl
   import {
     to = azurerm_storage_account.this
     id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<name>"
   }
   ```
6. Run `terraform plan`. It should show the imports and nothing unexpected:
   - A "create" means something is still missing from state.
   - A "destroy" or "replace" means stop.

   Have a second engineer review the plan.
7. Once the plan is clean, release the lock with `terraform force-unlock <lock-id>`, but only after confirming that no run is still active. Then re-enable the pipeline and let the original change finish through it.

**Prevent**
8. Find out why it broke: a runner killed mid-write, a network drop, two runs at once, or a manual state edit. Then:
   - Keep blob versioning and soft delete on the state account.
   - Apply to prod only from the pipeline, with a limit of one run at a time.
   - Split large states by component, so one failure affects less.
   - Write this procedure up as a runbook.

## Scenario 3 — AKS far behind.

**A production AKS cluster is four Kubernetes minor versions behind. The normal one-version-at-a-time upgrade targets are no longer offered by Azure.**

AKS upgrades one minor version at a time. The exception is a cluster on an unsupported version, which may be offered a direct jump to the oldest supported version. A four-version jump crosses several API removals, so most of the work is checking the workloads, not running the upgrade command.

**Assess**
1. Check the current versions and what Azure offers now:
   `az aks show -g <rg> -n <aks> --query "{cp:kubernetesVersion, pools:agentPoolProfiles[].{name:name, v:orchestratorVersion}}"`
   `az aks get-upgrades -g <rg> -n <aks> -o table` and `az aks get-versions -l <region> -o table`
2. Find what will break across those versions:
   - Removed APIs: run `kubent` or `pluto detect-all-in-cluster`, and use the deprecated-API check in AKS *Diagnose and solve problems*.
   - Helm charts, CRDs and add-ons (ingress controller, cert-manager, CSI drivers): check each against the target version.
3. Find what will block the upgrade:
   - PDBs with `maxUnavailable: 0`, or `minAvailable` equal to the replica count.
   - Single-replica apps.
   - Not enough quota for surge nodes.

**Choose the path**
4. **Blue/green cluster (preferred for production with a four-version gap).**
   - Build a new cluster on a supported version from Terraform.
   - Deploy the same manifests through the pipeline or GitOps, and run smoke and load tests.
   - Shift traffic gradually (Front Door, Traffic Manager or DNS weights).
   - Keep the old cluster as the rollback until the new one has proven itself, then remove it.
   - Stateful workloads need a data plan: Velero, disk snapshots, or moving the state to managed services first.
5. **In place, if a new cluster isn't possible.**
   - Back up first (Velero, or confirm Git can rebuild everything).
   - Fix every deprecated API in manifests and charts before touching the cluster.
   - Rehearse the same version path on a copy of the cluster.
   - Upgrade one version at a time inside a maintenance window: the control plane first (`az aks upgrade --control-plane-only -k <version>`), then the node pools to the same version (`az aks nodepool upgrade --max-surge 33%`), before moving to the next version.
   - After each step, run `kubectl get nodes`, check that workloads are healthy, and run the smoke tests.

**Prevent**
6. Set an auto-upgrade channel (`--auto-upgrade-channel stable` or `patch`) with a planned maintenance window. Upgrade dev a few weeks before prod, and alert when the cluster version gets close to end of support.

## Scenario 4 — Private endpoint timeout.

**A self-hosted pipeline runner cannot reach a storage account that sits behind a private endpoint. The error is a connection timeout.**

A **timeout** points to the network path. A 403 would mean the request reached the account and was rejected by its firewall or RBAC. Check the path in order: DNS, then the endpoint, then routing and filtering.

1. **DNS on the runner** (the most common cause):
   `nslookup <account>.blob.core.windows.net`
   It should return a CNAME to `<account>.privatelink.blob.core.windows.net` and a **private IP** (for example 10.x). If it returns a public IP, the runner isn't using the private DNS zone. The usual reasons:
   - The `privatelink.blob.core.windows.net` zone isn't linked to the runner's VNet. Check with `az network private-dns link vnet list -g <rg> -z privatelink.blob.core.windows.net -o table`.
   - The VNet uses custom DNS servers that don't forward to Azure DNS (168.63.129.16) or to a DNS Private Resolver.
   - For an on-premises runner, there's no conditional forwarder for `blob.core.windows.net` pointing at the resolver's inbound endpoint.
2. **The private endpoint itself:** check that the connection is `Approved` and that the A record points to the endpoint's IP.
   `az network private-endpoint show -g <rg> -n <pe> --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status"`
   `az network private-dns record-set a list -g <rg> -z privatelink.blob.core.windows.net -o table`
3. **Reachability, once DNS is right:** run `nc -vz <private-ip> 443` from the runner. If that times out, check:
   - **Peering (if the VNets differ):** it must exist and be `Connected` in both directions. Use `az network vnet peering list`.
   - **NSGs:** outbound 443 must be allowed on the runner subnet, and inbound on the endpoint subnet. Network Watcher shows which rule drops the traffic: `az network watcher test-ip-flow` or `az network watcher test-connectivity`.
   - **Routes:** a user-defined route may send the traffic through a firewall that blocks it or routes it asymmetrically. Check `az network nic show-effective-route-table` and the firewall logs.
   - **Proxy:** an `HTTPS_PROXY` on the runner may send the request to a proxy that can't reach private IPs. Add the account to `NO_PROXY`.
4. Fix the layer that failed, re-run the same `nslookup` and `nc` checks, then re-run the pipeline job.
5. **Prevent:**
   - Build runners with Terraform inside a VNet where the private DNS zones are linked, or behind a central DNS Private Resolver.
   - Add a pre-flight step to the pipeline that runs `nslookup` and `nc` and fails fast with a clear message.

This is the same situation as Task 1: GitHub-hosted runners can't use private endpoints. That's why moving to self-hosted runners inside the VNet is listed there as the next production step.
