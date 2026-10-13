# Campus Notice Board on Kubernetes - CTE412 Assessed Lab

Student: Sangay Tshokyee Tshering(`<sid>` = 02230146)

## Purpose

Deploys the Campus Notice Board API to a local three-node kind cluster and releases new
versions with three strategies (Recreate, RollingUpdate, blue/green) plus a feature flag.
A monitor Pod requests `/version` every 0.5 s, so every release is reported as a
**measured** number of failed requests.

## Software versions

| Tool | Version |
|---|---|
| OS | _fill in_ |
| Docker | _fill in (`docker version --format '{{.Server.Version}}'`)_ |
| kind | _fill in (`kind version`)_ |
| kubectl | _fill in (`kubectl version --client`)_ |
| Cluster Kubernetes | _fill in (`kubectl get nodes`)_ |
| Application | Python 3.13 standard library, base image `python:3.13-alpine` |
| Monitor | `busybox:1.37` |

## Layout

```
cluster/kind-cluster.yaml     kind cluster cte412-02230146 (1 control-plane, 2 workers, host 127.0.0.1:30090)
app/                          app.py + Dockerfile (one source tree, three images)
manifests/base/               namespace, quota + limit range, monitor Pod
manifests/rolling/            single notice-board Deployment + Services (Tasks 3, 5, 6)
manifests/bluegreen/          flag ConfigMap, blue + green Deployments, Services (Tasks 7, 8)
scripts/summarise.sh          monitor-log summariser
evidence/                     tN-*.txt captured output
report/p06-report.md          the report
```

## Rebuild the final state (end of Task 8) from an empty machine

Requires Docker (running), kind, kubectl. Run from the repository root.

```bash
# 1. cluster
kind create cluster --config cluster/kind-cluster.yaml
kubectl config use-context kind-cte412-02230146

# 2. the three images, built locally and loaded into every node (no registry)
for v in 1.0.0 1.1.0 1.2.0-broken; do
  docker build --build-arg APP_VERSION=$v --build-arg STUDENT_ID=02230146 \
               -t notice-board:02230146-$v app/
  kind load docker-image notice-board:02230146-$v --name cte412-02230146
done

# 3. namespace, quota, limit range, monitor
kubectl apply -f manifests/base/00-namespace.yaml
kubectl apply -f manifests/base/01-quota-limits.yaml
kubectl config set-context --current --namespace=nb-02230146
kubectl apply -f manifests/base/02-monitor.yaml

# 4. final state of Task 8: flag ConfigMap, blue + green, production on green
kubectl apply -f manifests/bluegreen/
kubectl rollout status deployment/notice-board-blue
kubectl rollout status deployment/notice-board-green

# 5. check
kubectl get deploy,svc,pods -o wide
curl -s http://localhost:30090/version; echo
curl -s http://localhost:30090/notices; echo     # pinnedFirst: true
```

If the first apply in step 3 reports `status unknown for quota`, run it again (the quota
was created a moment earlier).

## Clean-up

```bash
kubectl delete -f manifests/bluegreen/
kubectl delete -f manifests/base/02-monitor.yaml
kubectl config set-context --current --namespace=default
kind delete cluster --name cte412-02230146
# optional: docker image rm notice-board:02230146-1.0.0 notice-board:02230146-1.1.0 notice-board:02230146-1.2.0-broken
```
