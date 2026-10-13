# CTE412 Integrated Systems Technology - Assessed Lab Report

**Rolling, Recreate and Blue/Green Releases of the Campus Notice Board on Kubernetes**

| | |
|---|---|
| Name | YOUR FULL NAME |
| Student number (`<sid>`) | 02230146 |
| Repository | https://github.com/YOUR-USER/YOUR-REPO |
| Date | ____ |

> Fill every `____` from your own evidence files. Replace each **[SCREENSHOT]** box with the
> screenshot named in it. Delete this note before submitting.

---

## 1. Objective

The Student Services Office takes the Campus Notice Board offline at every release and has never measured for how long. In this practical I deployed the API to a local three-node kind cluster, built a monitor that calls `/version` twice a second, and released new versions using Recreate, RollingUpdate and blue/green, plus a feature flag. For each release I report the number of failed requests the monitor actually counted, how long two versions were served at the same time, and how many Pods the release needed. I also show that a broken release can be stopped and rolled back without any failed requests.

Descriptor coverage: Unit IV 4.1 (rolling, blue/green, feature flags), 4.2 (monitoring and troubleshooting), 4.3 (containerised CI/CD with Docker and Kubernetes); LO6 and LO7.

## 2. Environment

| Item | Value |
|---|---|
| Operating system | ____ (e.g. Ubuntu 24.04 on WSL 2, Windows 11) |
| Docker | ____ |
| kind | ____ |
| kubectl (client) | ____ |
| Cluster Kubernetes version | ____ (from `kubectl get nodes`) |
| Cluster | `cte412-02230146`: 1 control-plane, 2 workers; host `127.0.0.1:30090` → NodePort 30090 |
| Namespace | `nb-02230146` (quota: requests 1 CPU / 1Gi, limits 2 CPU / 2Gi, 15 Pods, 4 Services) |
| Application language | Python 3.13 (standard library `http.server`, no packages) |
| Application base image | `python:3.13-alpine`, runs as UID 10001 (non-root) |
| Monitor image | `busybox:1.37` |
| Images | `notice-board:02230146-1.0.0`, `-1.1.0`, `-1.2.0-broken`, loaded with `kind load docker-image`, `imagePullPolicy: Never` |

> **[SCREENSHOT - Figure 1]** `kubectl get nodes -o wide` and `docker ps` showing the three nodes and `127.0.0.1:30090->30090/tcp`. Evidence: `evidence/t1-cluster.txt`

> **[SCREENSHOT - Figure 2]** `kubectl describe resourcequota nb-quota` and `kubectl describe limitrange nb-limits`. Evidence: `evidence/t1-quota.txt`

> **[SCREENSHOT - Figure 3]** Local test of the three images: `/healthz` returns 503 for the first 5 s, then 200, 200, 503 (broken); `/notices` for 1.1.0 with `"pinnedFirst": true`. Evidence: `evidence/t2-endpoints.txt`

> **[SCREENSHOT - Figure 4]** `crictl images` on a worker node showing the three `notice-board:02230146-*` images (no registry used). Evidence: `evidence/t2-loaded.txt`

> **[SCREENSHOT - Figure 5]** `kubectl get deploy,rs,pods,svc -o wide` after Task 3. Evidence: `evidence/t3-deploy.txt`

> **[SCREENSHOT - Figure 6]** `curl http://localhost:30090/version` loop answered by different Pods. Evidence: `evidence/t3-host-version.txt`

> **[SCREENSHOT - Figure 7]** One minute of monitor output at rest and its summary (____ requests, 0 failed). Evidence: `evidence/t4-rest-monitor.txt`, `evidence/t4-rest-summary.txt`

## 3. Results

Each row comes from `scripts/summarise.sh` run on a monitor log that starts at least 10 s before the apply and ends at least 10 s after the rollout completed. Peak Pods is the highest number of `app=notice-board` Pods listed (Terminating Pods included) in the matching `-pods.txt` file.

| Release | Evidence | Requests observed | Failed requests | Mixed-version window (s) | Peak notice-board Pods |
|---|---|---|---|---|---|
| Recreate, 1.0.0 → 1.1.0 | `t5-recreate-*` | ____ | ____ | ____ | ____ |
| RollingUpdate (0 / 1, minReady 5 s), 1.0.0 → 1.1.0 | `t5-rolling-*` | ____ | ____ | ____ | ____ |
| Broken release 1.2.0-broken + rollback | `t6-broken-*` | ____ | ____ | ____ | ____ |
| Blue/green switch 1: blue → green | `t7-switch1-to-green-*` | ____ | ____ | ____ | ____ |
| Blue/green switch 2: green → blue | `t7-switch2-to-blue-*` | ____ | ____ | ____ | ____ |
| Blue/green switch 3: blue → green | `t7-switch3-to-green-*` | ____ | ____ | ____ | ____ |
| Feature flag FEATURE_PINNED=true (green rollout) | `t8-flag-*` | ____ | ____ | ____ | ____ |

Timestamps have one-second resolution, so windows are accurate to about ±1 s. In the flag row both sides report version 1.1.0, so the "mixed" window is between Pods with the flag off and on; it is read from `t8-flag-pods.txt` and the rollout duration.

> **[SCREENSHOT - Figure 8]** `evidence/t5-recreate-summary.txt` (failures and a gap with no version).

> **[SCREENSHOT - Figure 9]** `evidence/t5-rolling-summary.txt` (0 failures, both versions overlapping).

> **[SCREENSHOT - Figure 10]** `kubectl rollout history deployment/notice-board` with change-causes. Evidence: `evidence/t5-history.txt`, `evidence/t6-history.txt`

> **[SCREENSHOT - Figure 11]** `kubectl rollout status` ending in "exceeded its progress deadline" and the condition `Progressing False ProgressDeadlineExceeded`. Evidence: `evidence/t6-rollout-status.txt`, `evidence/t6-condition.txt`

> **[SCREENSHOT - Figure 12]** Pods during the stalled rollout: three 1.1.0 Pods `1/1`, one `1.2.0-broken` Pod `0/1 Running`. Evidence: `evidence/t6-pods.txt`

> **[SCREENSHOT - Figure 13]** `kubectl diff -f manifests/rolling/01-deployment.yaml` printing nothing, exit code 0. Evidence: `evidence/t6-diff.txt`

> **[SCREENSHOT - Figure 14]** `kubectl get deploy,svc,pods -L slot,version` with blue and green running. Evidence: `evidence/t7-objects.txt`

> **[SCREENSHOT - Figure 15]** Preview Service answering 1.1.0 while production answers 1.0.0. Evidence: `evidence/t7-preview.txt`

> **[SCREENSHOT - Figure 16]** Summary of the monitor log across all three switches. Evidence: `evidence/t7-switches-all-summary.txt`

> **[SCREENSHOT - Figure 17]** ConfigMap shows `FEATURE_PINNED: true` but every running green Pod still prints `false`, same Pod names and ages. Evidence: `evidence/t8-after-configmap.txt`

> **[SCREENSHOT - Figure 18]** After the `flags-revision` rollout: Pods print `true`, `/notices` returns `"pinnedFirst": true` with notice 3 first; 0 failed requests. Evidence: `evidence/t8-after-rollout.txt`, `evidence/t8-flag-summary.txt`

> **[SCREENSHOT - Figure 19]** State rebuilt from the README commands only. Evidence: `evidence/t9-emptied.txt`, `evidence/t9-rebuilt.txt`

> **[SCREENSHOT - Figure 20]** `kind get clusters` → "No kind clusters found." Evidence: `evidence/t9-deleted.txt`

## 4. Analysis

> Check every sentence against your own numbers. If your evidence disagrees with what is written here, change the text to what you measured.

**A1. Rank the strategies by failed requests, and explain the mechanism.**

From fewest to most failed requests: blue/green switches (____, ____, ____), RollingUpdate (____), Recreate (____).

- *Recreate* (`t5-recreate-monitor.txt`): the Deployment scaled the old ReplicaSet to 0 before creating any new Pod. From ____ to ____ the Service had no ready endpoint, so every request in that gap was `FAIL` (connection refused). The gap is the Pod termination time plus image start plus the 5 s warm-up before `/healthz` returned 200, about ____ s, or ____ requests at 2 per second.
- *RollingUpdate* (`t5-rolling-monitor.txt`): with `maxUnavailable: 0` and `maxSurge: 1`, one 1.1.0 Pod was added and an old Pod was removed only after the new one had been Ready for `minReadySeconds: 5`. There were always three ready Pods behind the Service, so ____ requests failed. The application keeps answering for 5 s after SIGTERM, so requests already routed to a terminating Pod still succeed.
- *Blue/green* (`t7-switch*-monitor.txt`): both colours were already Running and Ready. A switch only changes the Service selector, so kube-proxy moved traffic from one set of ready Pods to another. Nothing had to start, so ____ requests failed.

**A2. Why did the broken release cause (or not cause) failed requests?**

The broken release produced ____ failed requests (`t6-broken-summary.txt`). In `manifests/rolling/01-deployment.yaml`:

- `readinessProbe` on `/healthz`: the 1.2.0-broken Pod never became Ready, so it was never added to the EndpointSlice and received no traffic (`t6-pods.txt` shows it `0/1`).
- `maxUnavailable: 0`: the Deployment may not remove an old Pod until a new Pod is available, so the three old Pods kept serving.
- `maxSurge: 1`: only one broken Pod was created, so the stalled rollout used a single extra Pod's quota.
- `progressDeadlineSeconds: 60`: after 60 s Kubernetes set `Progressing=False, reason ProgressDeadlineExceeded` (`t6-condition.txt`). It did not stop the rollout; it reported it so I could roll back.
- `livenessProbe` is a TCP check, not `/healthz`: the broken Pod was not restarted in a loop. It just stayed unready.

With the defaults: with no readiness probe the broken Pod would count as Ready as soon as it started, and old Pods would be removed. Here 1.2.0-broken still answers `/version`, so the monitor would have recorded **0 failures but would have served the broken version**, and the defect would go unnoticed. With `maxUnavailable` at its default 25% (= 1 of 3) and the probe kept, one old Pod would have been removed immediately. Capacity would drop to 2 Pods for the whole stall, but the remaining two would still answer, so probably 0 failures. With `progressDeadlineSeconds` at 600 the failure would have been reported after 10 minutes instead of 1. If the liveness probe had used `/healthz`, the broken Pod would have been restarted repeatedly (CrashLoopBackOff), but still with no traffic sent to it.

**A3. RollingUpdate versus blue/green**

| Axis | RollingUpdate | Blue/green |
|---|---|---|
| Mixed-version window | ____ s (`t5-rolling-summary.txt`): old and new Pods share one Service for the whole rollout | ____ s per switch (`t7-switch*-summary.txt`): only while kube-proxy updates its rules on the three nodes |
| Peak resources against the quota | ____ Pods (3 + 1 surge); requests ____m CPU of 1000m (`t5-rolling-pods.txt`) | ____ Pods (3 blue + 3 green, always); requests ____m CPU of 1000m (`t7-quota.txt`). Double capacity for the whole time both colours exist |
| Time to roll back | `kubectl rollout undo` in Task 6: ____ s. That was quick only because the rollout had stalled and the 1.1.0 ReplicaSet still had 3 Pods. After a completed rollout, undo must start and warm up new Pods (about ____ s, like `t5-rolling`) | Editing one selector and applying: ____ s (`t7-switch2-to-blue-summary.txt`). The old version is already running |

Blue/green gives a short mixed window and an instant rollback, but doubles the resources. RollingUpdate costs only one extra Pod, but mixes versions for longer and rolls back as slowly as it rolls forward.

**A4. When is Recreate the right choice?**

Recreate is right when two versions must never run at the same time. One example: version 1.1.0 changes the notice database schema (a column is renamed) in a way 1.0.0 cannot read. During a rolling update, 1.0.0 Pods would read the migrated data and return errors or corrupt it. Accepting the ____ s outage measured in `t5-recreate-summary.txt` during a quiet period (e.g. late at night) is safer than serving two incompatible versions. The same applies when the app holds an exclusive lock or a single-writer volume (ReadWriteOnce) that a second Pod cannot mount.

**A5. What did the feature flag change without a new image, and what did it not avoid?**

The flag changed the behaviour of `/notices` (pinned notices first, `"pinnedFirst": true`) using the same image `notice-board:02230146-1.1.0`. No build, no new tag, no `kind load` (`t8-after-rollout.txt`). The same flag could be turned off just as quickly.

It did not avoid a restart. The flag reaches the container as an environment variable, which is read only when the container starts. After the ConfigMap changed, the running Pods still printed `false` (`t8-after-configmap.txt`). To apply it I had to change the Pod template (`cte412/flags-revision: "2"`), which triggered a normal rolling update of the green Pods (`t8-flag-summary.txt`: ____ failed requests, ____ s rollout). It also did not avoid a brief period in which some green Pods had the flag on and some off.

## 5. Reflection

> Must be your own experience. Name the actual error, paste the output that revealed it, and explain how you reasoned to the fix.

**Error I met:** ____

**Output that revealed it:**

```
(paste the real command and its output here)
```

> **[SCREENSHOT - Figure 21]** (optional) the error as it appeared.

**Reasoning that resolved it:** ____

**One thing that remains unclear:** ____

## 6. References

| Documentation consulted | Date accessed |
|---|---|
| Kubernetes - Deployments (strategy, maxSurge, maxUnavailable, minReadySeconds, progressDeadlineSeconds). https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ | ____ |
| Kubernetes - Configure Liveness, Readiness and Startup Probes. https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ | ____ |
| Kubernetes - ConfigMaps (environment variables are not updated in running Pods). https://kubernetes.io/docs/concepts/configuration/configmap/ | ____ |
| Kubernetes - Resource Quotas / Limit Ranges. https://kubernetes.io/docs/concepts/policy/resource-quotas/ | ____ |
| kind - Configuration (extraPortMappings) and Quick Start (`kind load docker-image`). https://kind.sigs.k8s.io/docs/user/configuration/ | ____ |

> Keep only the pages you actually opened, and add any others.
