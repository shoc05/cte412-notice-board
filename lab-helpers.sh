# lab-helpers.sh - shell helpers for the CTE412 assessed lab.
# Use   : cd cte412-notice-board && source ../lab-helpers.sh      (in EVERY terminal you open)
# Needs : bash and GNU date/sed (Linux or WSL 2). Run from the repository root.
# These are NOT part of the submission. They only save typing: they capture evidence
# and edit manifest files. Every change to the cluster itself is still a plain
# `kubectl apply -f <manifest>` that you type yourself.

export SID=02230146
export NS=nb-$SID
export CLUSTER=cte412-$SID
export CTX=kind-$CLUSTER

# ev <file> '<command>'  - run a command, show the output and APPEND it to evidence/<file>.
# The first line of every capture records <sid>, context, namespace and time, because
# evidence that does not show your <sid> is not marked.
ev() {
  local f="evidence/$1"; shift
  mkdir -p evidence
  {
    echo "# sid=$SID context=$(kubectl config current-context 2>/dev/null) namespace=$NS time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "\$ $*"
    eval "$*"
    echo
  } 2>&1 | tee -a "$f"
}

# mark [seconds]  - print the UTC time N seconds ago (default 0 = now) as an ISO-8601 string.
mark() { date -u -d "-${1:-0} seconds" +%Y-%m-%dT%H:%M:%SZ; }

# slice <start> <end> <outfile>  - save the monitor log between two UTC times to evidence/<outfile>
# (the first line shows <sid>; summarise.sh ignores it).
slice() {
  mkdir -p evidence
  {
    echo "# sid=$SID context=$(kubectl config current-context) namespace=$NS window=$1 .. $2"
    kubectl logs monitor --since-time="$1" | awk -v e="$2" '$1 ~ /^20/ && $1 <= e'
  } > "evidence/$3"
  echo "saved evidence/$3 ($(grep -c ' OK \| FAIL ' "evidence/$3") monitor lines)"
}

# podwatch_start <file> / podwatch_stop <file>
# Once a second, record the number of notice-board Pods listed by kubectl (Terminating Pods
# included) and the quota usage. podwatch_stop prints the peaks; the first number is the
# "peak number of notice-board Pods" for the results table.
podwatch_start() {
  mkdir -p evidence
  echo "# sid=$SID namespace=$NS columns: time pods-listed quota-pods quota-requests.cpu quota-requests.memory" > "evidence/$1"
  (
    while true; do
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $(kubectl get pods -l app=notice-board --no-headers 2>/dev/null | wc -l) $(kubectl get resourcequota nb-quota -o jsonpath='{.status.used.pods} {.status.used.requests\.cpu} {.status.used.requests\.memory}' 2>/dev/null)"
      sleep 1
    done >> "evidence/$1"
  ) &
  PW_PID=$!
}
podwatch_stop() {
  kill "$PW_PID" 2>/dev/null; wait "$PW_PID" 2>/dev/null
  grep -v '^#' "evidence/$1" | awk '
    { p = $2 + 0; q = $3 + 0; c = $4; m = $5; sub(/m$/, "", c); sub(/Mi$/, "", m); c += 0; m += 0
      if (p > mp) mp = p; if (q > mq) mq = q; if (c > mc) mc = c; if (m > mm) mm = m }
    END { printf "# peak: %d notice-board Pods listed | quota used at peak: %d Pods, requests.cpu %dm of 1000m, requests.memory %dMi of 1024Mi\n", mp, mq, mc, mm }' \
    | tee -a "evidence/$1"
}

# capture_start <label> / capture_stop <label>
# Wrap ONE release: start before the apply, stop after the rollout has finished. Together they
# give "from at least 10 s before the apply until at least 10 s after the rollout completes":
#   capture_start t5-recreate     # remembers "now - 15 s", starts the Pod counter
#   kubectl apply -f ...          # (and wait for the rollout)
#   capture_stop  t5-recreate     # waits 15 s, then writes
#                                 #   evidence/t5-recreate-monitor.txt  (monitor lines in the window)
#                                 #   evidence/t5-recreate-pods.txt     (Pod and quota counts per second)
#                                 #   evidence/t5-recreate-summary.txt  (scripts/summarise.sh output)
capture_start() {
  CAP_T0=$(mark 15)
  podwatch_start "$1-pods.txt"
  echo "capture '$1' started; window opens at $CAP_T0"
}
capture_stop() {
  echo "waiting 15 s after the rollout ..."; sleep 15
  local t1; t1=$(mark 0)
  podwatch_stop "$1-pods.txt"
  slice "$CAP_T0" "$t1" "$1-monitor.txt"
  ev "$1-summary.txt" "scripts/summarise.sh evidence/$1-monitor.txt"
}

# setrel <version> "<change-cause>"  - point manifests/rolling/01-deployment.yaml at a release:
# image tag, version label and change-cause annotation (three one-line edits).
# Do not use & | or \ in the change-cause text.
setrel() {
  sed -i -E \
    -e "s|^( *image: notice-board:$SID-).*|\1$1|" \
    -e "s|^( *version: ).*|\1\"$1\"|" \
    -e "s|^( *kubernetes.io/change-cause: ).*|\1\"$2\"|" \
    manifests/rolling/01-deployment.yaml
}

# setstrategy recreate | rolling  - rewrite the single `strategy:` line of the rolling Deployment.
setstrategy() {
  case "$1" in
    recreate) sed -i -E 's|^  strategy: .*|  strategy: {type: Recreate}   # task 5.1: stop every old Pod, then start the new ones (downtime accepted for this measurement)|' manifests/rolling/01-deployment.yaml ;;
    rolling)  sed -i -E 's|^  strategy: .*|  strategy: {type: RollingUpdate, rollingUpdate: {maxUnavailable: 0, maxSurge: 1}}   # task 5.3: never fewer than 3 available Pods, at most 1 extra Pod|' manifests/rolling/01-deployment.yaml ;;
    *) echo "usage: setstrategy recreate|rolling" >&2; return 2 ;;
  esac
}

# setcolour blue|green  - switch the PROD-SLOT lines of manifests/bluegreen/04-services.yaml
# (the two production Services; the preview Service has no PROD-SLOT marker and is never touched).
setcolour() {
  case "$1" in
    blue|green) sed -i -E "/# PROD-SLOT/ s,slot: (blue|green),slot: $1," manifests/bluegreen/04-services.yaml ;;
    *) echo "usage: setcolour blue|green" >&2; return 2 ;;
  esac
}

echo "helpers loaded: SID=$SID NS=$NS CLUSTER=$CLUSTER"
echo "  ev mark slice podwatch_start podwatch_stop capture_start capture_stop setrel setstrategy setcolour"
