# CTE412 Assessed Lab - command runbook (Tasks 1 to 9)

Student number used everywhere: **02230146**. If yours is different, run
`grep -rl 02230146 . | xargs sed -i 's/02230146/<your-sid>/g'` once, in this folder, before anything else.

**Before you start**
1. Linux or WSL 2 shell (Windows: everything inside WSL 2). Docker running, `kind` and `kubectl` installed.
2. Put your full name in `cte412-notice-board/manifests/base/00-namespace.yaml` and `README.md`.
3. Create an empty GitHub repo, then:
   ```bash
   cd cte412-notice-board
   git init && git add . && git commit -m "Repository structure"
   git branch -M main && git remote add origin <your-repo-url> && git push -u origin main
   ```
4. **Every terminal** you open: `cd cte412-notice-board && source ../lab-helpers.sh`
5. Commit after every task: `git add -A && git commit -m "Task N" && git push`

Helpers (from `lab-helpers.sh`): `ev <file> '<cmd>'` runs a command and appends its output to
`evidence/<file>` with a `sid=` header line. `capture_start/stop <label>` records the monitor log
and the Pod count around one release. `setrel`, `setstrategy`, `setcolour` edit manifests only;
**you** still apply them. 📸 marks where to take a screenshot for the report.

---

## Task 1 - Cluster, namespace, quota (15 min)

```bash
kind create cluster --config cluster/kind-cluster.yaml
ev t1-cluster.txt 'kind get clusters; kubectl config current-context; kubectl get nodes -o wide'
ev t1-cluster.txt 'docker ps --format "table {{.Names}}\t{{.Ports}}"'     # shows 127.0.0.1:30090->30090

kubectl apply -f manifests/base/00-namespace.yaml
kubectl apply -f manifests/base/01-quota-limits.yaml
kubectl config set-context --current --namespace=$NS

ev t1-namespace.txt "kubectl get namespace $NS --show-labels; kubectl describe namespace $NS"
ev t1-quota.txt 'kubectl describe resourcequota nb-quota; kubectl describe limitrange nb-limits'
ev t1-context.txt "kubectl config view --minify -o jsonpath='{..namespace}'; echo"
```
📸 Fig 1: `kubectl get nodes -o wide` + `docker ps`. 📸 Fig 2: `kubectl describe resourcequota nb-quota`.

## Task 2 - Three release images (30 min)

```bash
for v in 1.0.0 1.1.0 1.2.0-broken; do
  docker build --build-arg APP_VERSION=$v --build-arg STUDENT_ID=$SID -t notice-board:$SID-$v app/
done
ev t2-images.txt 'docker image ls notice-board'

# local test of every image (outside Kubernetes)
docker run -d --name nb100 -p 18080:8080 notice-board:$SID-1.0.0
docker run -d --name nb110 -p 18081:8080 -e FEATURE_PINNED=true notice-board:$SID-1.1.0
docker run -d --name nb120 -p 18082:8080 notice-board:$SID-1.2.0-broken
ev t2-endpoints.txt 'for p in 18080 18081 18082; do curl -s -o /dev/null -w "port $p healthz at start: %{http_code}\n" localhost:$p/healthz; done'
sleep 6
ev t2-endpoints.txt 'for p in 18080 18081 18082; do curl -s -w "  [%{http_code}]\n" localhost:$p/healthz; done'
ev t2-endpoints.txt 'curl -s localhost:18080/version; echo; curl -s localhost:18080/notices; echo'
ev t2-endpoints.txt 'curl -s localhost:18081/notices; echo; curl -s localhost:18082/version; echo'
ev t2-nonroot.txt 'docker exec nb100 id; docker image inspect notice-board:$SID-1.0.0 --format "User={{.Config.User}}"'
docker rm -f nb100 nb110 nb120

# place the images in the cluster without a registry
for v in 1.0.0 1.1.0 1.2.0-broken; do kind load docker-image notice-board:$SID-$v --name $CLUSTER; done
ev t2-loaded.txt 'docker exec $CLUSTER-worker crictl images | grep notice-board'
```
Expected: healthz `503` at start for all three, then `200 200 503`; 1.1.0 lists notice 3 first with `"pinnedFirst": true`; `id` shows `uid=10001`.
📸 Fig 3: the `t2-endpoints` output. 📸 Fig 4: `crictl images` on the worker.

## Task 3 - Deploy and expose 1.0.0 (25 min)

```bash
kubectl apply -f manifests/rolling/
kubectl rollout status deployment/notice-board
ev t3-deploy.txt 'kubectl get deploy,rs,pods,svc -o wide --show-labels'
ev t3-pullpolicy.txt "kubectl get deploy notice-board -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}{\"\n\"}'"
ev t3-pullpolicy.txt 'kubectl get events --field-selector reason=Pulling'      # expect: No resources found
ev t3-endpoints.txt 'kubectl get endpointslice -l kubernetes.io/service-name=notice-board'
ev t3-host-version.txt 'for i in $(seq 1 12); do curl -s http://localhost:30090/version; echo; done'
ev t3-host-version.txt 'for i in $(seq 1 30); do curl -s http://localhost:30090/version; echo; done | grep -o "\"pod\": \"[^\"]*\"" | sort | uniq -c'
```
Expected: the last command shows 2 or 3 different Pod names.
📸 Fig 5: `kubectl get deploy,rs,pods,svc`. 📸 Fig 6: curl loop showing different Pods.

## Task 4 - Monitor and summariser (15 min)

```bash
kubectl apply -f manifests/base/02-monitor.yaml
kubectl wait --for=condition=Ready pod/monitor --timeout=60s
kubectl logs monitor --tail=5
T0=$(mark 0); sleep 62; T1=$(mark 0)
slice "$T0" "$T1" t4-rest-monitor.txt
ev t4-rest-summary.txt 'scripts/summarise.sh evidence/t4-rest-monitor.txt'
```
Expected: ~120 requests, 0 failed, only 1.0.0. **Never delete or restart `monitor` until Task 9.**
📸 Fig 7: `kubectl logs monitor --tail=5` + the summary.

## Task 5 - Recreate versus RollingUpdate (25 min)

**5.1 Recreate, release 1.1.0**
```bash
setstrategy recreate
setrel 1.1.0 "task 5.1: release 1.1.0 with Recreate"
git diff manifests/rolling/01-deployment.yaml          # check the edit
capture_start t5-recreate
kubectl apply -f manifests/rolling/01-deployment.yaml
kubectl rollout status deployment/notice-board
capture_stop t5-recreate
```
**5.2 Back to 1.0.0 (declaratively)**
```bash
setrel 1.0.0 "task 5.2: back to 1.0.0"
capture_start t5-back-to-100
kubectl apply -f manifests/rolling/01-deployment.yaml
kubectl rollout status deployment/notice-board
capture_stop t5-back-to-100
```
**5.3 RollingUpdate (maxUnavailable 0, maxSurge 1, minReadySeconds 5), release 1.1.0**
```bash
setstrategy rolling
sed -i 's|^  minReadySeconds: .*|  minReadySeconds: 5   # task 5.3: a new Pod must stay Ready for 5 s before it counts as available|' manifests/rolling/01-deployment.yaml
setrel 1.1.0 "task 5.3: release 1.1.0 with RollingUpdate 0/1, minReady 5"
git diff manifests/rolling/01-deployment.yaml
capture_start t5-rolling
kubectl apply -f manifests/rolling/01-deployment.yaml
kubectl rollout status deployment/notice-board
capture_stop t5-rolling
ev t5-history.txt 'kubectl rollout history deployment/notice-board'
```
5.4: the mixed-version window is printed in `evidence/t5-recreate-summary.txt` and `evidence/t5-rolling-summary.txt` (Recreate should be 0 s with failures; Rolling > 0 s with 0 failures). Peak Pods: last line of `t5-*-pods.txt`.
📸 Fig 8: `t5-recreate-summary.txt`. 📸 Fig 9: `t5-rolling-summary.txt`. 📸 Fig 10: `kubectl rollout history`.

## Task 6 - Failed release and rollback (20 min)

```bash
sed -i 's|^  progressDeadlineSeconds: .*|  progressDeadlineSeconds: 60   # task 6.1: a rollout that makes no progress for 60 s is marked failed|' manifests/rolling/01-deployment.yaml
setrel 1.2.0-broken "task 6.1: release 1.2.0-broken"
git diff manifests/rolling/01-deployment.yaml
capture_start t6-broken
kubectl apply -f manifests/rolling/01-deployment.yaml
ev t6-rollout-status.txt 'kubectl rollout status deployment/notice-board --timeout=120s'   # ends with "exceeded its progress deadline"
ev t6-condition.txt "kubectl get deploy notice-board -o jsonpath='{range .status.conditions[*]}{.type}{\"\t\"}{.status}{\"\t\"}{.reason}{\"\t\"}{.message}{\"\n\"}{end}'"
ev t6-pods.txt 'kubectl get pods -l app=notice-board -o wide --show-labels'          # 3 old Ready + 1 broken 0/1
ev t6-pods.txt 'kubectl describe pods -l version=1.2.0-broken | grep -A2 -i "readiness probe failed" | head -6'

# 6.3 the ONLY imperative state change of the practical
kubectl rollout undo deployment/notice-board
kubectl rollout status deployment/notice-board
capture_stop t6-broken
ev t6-history.txt 'kubectl rollout history deployment/notice-board'
```
Expected condition: `Progressing  False  ProgressDeadlineExceeded`. `t6-broken-summary.txt` must show **Failed requests: 0**.

**6.4 Bring the manifest back into agreement and prove it**
```bash
kubectl get deploy notice-board -o jsonpath='{.metadata.annotations.kubernetes\.io/change-cause}{"\n"}'   # copy this text
setrel 1.1.0 "<paste the change-cause printed above>"
ev t6-diff.txt 'kubectl diff -f manifests/rolling/01-deployment.yaml; echo "kubectl diff exit code: $?"'
```
Exit code `0` and no diff output = manifest and cluster agree. If a diff remains, edit the file until it is empty.
📸 Fig 11: rollout status + condition. 📸 Fig 12: Pods during the stalled rollout. 📸 Fig 13: `kubectl diff` exit 0.

## Task 7 - Blue/green (25 min)

```bash
kubectl delete -f manifests/rolling/01-deployment.yaml     # sheet: remove the Task 3 Deployment first
# (the monitor logs FAIL until blue is Ready - expected, outside every measured row)
kubectl apply -f manifests/bluegreen/                      # ConfigMap, blue, green, 3 Services (production = blue)
kubectl rollout status deployment/notice-board-blue
kubectl rollout status deployment/notice-board-green
ev t7-objects.txt 'kubectl get deploy,svc,pods -o wide -L slot,version'
ev t7-objects.txt 'for s in notice-board notice-board-ext notice-board-preview; do kubectl get endpointslice -l kubernetes.io/service-name=$s; done'
ev t7-quota.txt 'kubectl describe resourcequota nb-quota'

# 7.3 verify green through the preview Service while production serves blue
ev t7-preview.txt 'for i in 1 2 3; do kubectl exec monitor -- wget -qO- http://notice-board-preview/version; echo; done'
ev t7-preview.txt 'for i in 1 2 3; do kubectl exec monitor -- wget -qO- http://notice-board/version; echo; done'
ev t7-preview.txt 'kubectl exec monitor -- wget -qO- http://notice-board-preview/notices; echo'
```
**7.4 / 7.5 Three switches (blue→green, green→blue, blue→green)**
```bash
T7=$(mark 15)
n=0
for c in green blue green; do
  n=$((n+1)); setcolour $c
  git diff manifests/bluegreen/04-services.yaml | grep '^[-+] .*slot'
  capture_start t7-switch$n-to-$c
  kubectl apply -f manifests/bluegreen/04-services.yaml
  sleep 10
  capture_stop t7-switch$n-to-$c
  git add -A && git commit -qm "Task 7: switch $n to $c"
done
slice "$T7" "$(mark 0)" t7-switches-all-monitor.txt
ev t7-switches-all-summary.txt 'scripts/summarise.sh evidence/t7-switches-all-monitor.txt'
ev t7-final.txt 'kubectl get svc -o wide; curl -s http://localhost:30090/version; echo'
```
📸 Fig 14: `kubectl get deploy,svc,pods -L slot,version`. 📸 Fig 15: preview vs production responses. 📸 Fig 16: summary of the three switches.

## Task 8 - Feature flag (15 min)

**8.1 Green reads FEATURE_PINNED from the ConfigMap** (template change → green rolls, 0/1)
```bash
sed -i 's/#FLAG# //' manifests/bluegreen/03-deployment-green.yaml
sed -i 's|^\( *kubernetes.io/change-cause: \).*|\1"task 8.1: green reads FEATURE_PINNED from notice-board-flags"|' manifests/bluegreen/03-deployment-green.yaml
git diff manifests/bluegreen/03-deployment-green.yaml
kubectl apply -f manifests/bluegreen/03-deployment-green.yaml
kubectl rollout status deployment/notice-board-green
ev t8-flag-false.txt 'kubectl exec deploy/notice-board-green -- printenv FEATURE_PINNED; curl -s http://localhost:30090/notices; echo'
```
**8.2 Flag to true - do the running Pods see it?**
```bash
sed -i 's|^  FEATURE_PINNED: .*|  FEATURE_PINNED: "true"   # task 8.2: pinned notices first|' manifests/bluegreen/01-configmap-flags.yaml
kubectl apply -f manifests/bluegreen/01-configmap-flags.yaml
sleep 30
ev t8-after-configmap.txt 'kubectl get configmap notice-board-flags -o jsonpath="{.data}"; echo'
ev t8-after-configmap.txt 'for p in $(kubectl get pods -l slot=green -o name); do echo "$p FEATURE_PINNED=$(kubectl exec ${p#pod/} -- printenv FEATURE_PINNED)"; done'
ev t8-after-configmap.txt 'kubectl get pods -l slot=green'                # same Pod names, AGE unchanged
ev t8-after-configmap.txt 'curl -s http://localhost:30090/notices; echo'  # still "pinnedFirst": false
```
Result: ConfigMap says `true`, Pods still print `false` → env vars are read only when a container starts.

**8.3 Make it take effect with zero failures (declarative only)**
```bash
sed -i 's|cte412/flags-revision: "1"|cte412/flags-revision: "2"|' manifests/bluegreen/03-deployment-green.yaml
sed -i 's|^\( *kubernetes.io/change-cause: \).*|\1"task 8.3: flags-revision 2 restarts green with FEATURE_PINNED=true"|' manifests/bluegreen/03-deployment-green.yaml
capture_start t8-flag
kubectl apply -f manifests/bluegreen/03-deployment-green.yaml
kubectl rollout status deployment/notice-board-green
capture_stop t8-flag
ev t8-after-rollout.txt 'for p in $(kubectl get pods -l slot=green -o name); do echo "$p FEATURE_PINNED=$(kubectl exec ${p#pod/} -- printenv FEATURE_PINNED)"; done'
ev t8-after-rollout.txt 'curl -s http://localhost:30090/notices; echo'   # "pinnedFirst": true, notice 3 first
```
📸 Fig 17: ConfigMap `true` but Pods `false`. 📸 Fig 18: after rollout, `pinnedFirst: true` and `t8-flag-summary.txt` with 0 failures.

## Task 9 - Reproducibility and clean-up (10 min)

```bash
# 9.1 complete monitor log of the session
kubectl logs monitor > evidence/t9-monitor-full.log
ev t9-full-summary.txt 'scripts/summarise.sh evidence/t9-monitor-full.log'

# 9.2 delete everything except namespace, quota, limit range ...
kubectl delete -f manifests/bluegreen/
kubectl delete -f manifests/base/02-monitor.yaml
ev t9-emptied.txt 'kubectl get all,configmap; kubectl get resourcequota,limitrange'   # only kube-root-ca.crt, quota, limitrange

# ... and rebuild using ONLY the README commands (steps 3-5; the cluster and images already exist)
kubectl apply -f manifests/base/00-namespace.yaml
kubectl apply -f manifests/base/01-quota-limits.yaml
kubectl config set-context --current --namespace=nb-02230146
kubectl apply -f manifests/base/02-monitor.yaml
kubectl apply -f manifests/bluegreen/
kubectl rollout status deployment/notice-board-blue
kubectl rollout status deployment/notice-board-green
ev t9-rebuilt.txt 'kubectl get deploy,svc,pods -o wide -L slot,version'
ev t9-rebuilt.txt 'curl -s http://localhost:30090/version; echo; curl -s http://localhost:30090/notices; echo'

# 9.3 reset, delete, commit
kubectl config set-context --current --namespace=default
kind delete cluster --name $CLUSTER
ev t9-deleted.txt 'kind get clusters; kubectl config get-contexts'
git add -A && git commit -m "Task 9: reproducibility and clean-up" && git push
```
📸 Fig 19: rebuilt state. 📸 Fig 20: `kind get clusters` → `No kind clusters found.`

---

## Filling the results table

For each row, open the matching `evidence/*-summary.txt` and `*-pods.txt`:

| Row | Summary file | Pods file |
|---|---|---|
| Recreate | `t5-recreate-summary.txt` | `t5-recreate-pods.txt` |
| RollingUpdate | `t5-rolling-summary.txt` | `t5-rolling-pods.txt` |
| Broken release + rollback | `t6-broken-summary.txt` | `t6-broken-pods.txt` |
| Switch 1/2/3 | `t7-switch1-to-green-summary.txt`, `t7-switch2-to-blue-…`, `t7-switch3-to-green-…` | matching `-pods.txt` |
| Flag change | `t8-flag-summary.txt` | `t8-flag-pods.txt` |

"Requests observed" = `Total requests`; "failed" = `Failed requests`; mixed window = `Mixed-version window`;
peak Pods = the `# peak:` line (it counts Terminating Pods too, which is what really occupies the quota).

## If something goes wrong

| Symptom | Check | Fix |
|---|---|---|
| Pod `ErrImageNeverPull` | `kubectl describe pod <name>` | you forgot `kind load docker-image ... --name $CLUSTER` for that tag |
| `exceeded quota` on apply | `kubectl describe resourcequota nb-quota` | Terminating Pods still count; wait 10 s and apply again |
| `status unknown for quota` | - | the quota was just created; apply again |
| `curl localhost:30090` refused | `docker ps` (port shown?) | cluster created without the config file; recreate it |
| Failures in `t6-broken-summary.txt` | `grep maxUnavailable manifests/rolling/01-deployment.yaml` | must be 0 before the broken apply; fix, roll back, repeat Task 6 |
| `kubectl diff` shows a change after 6.4 | read the diff lines | copy the live value into the manifest, diff again |
| `CreateContainerConfigError` on green | `kubectl describe pod` | the ConfigMap is missing; apply `01-configmap-flags.yaml` |
