#!/bin/bash
# bin/envrun --time-limit under each real container runtime it finds,
# Apptainer on the desktop and Docker in CI: a command that sleeps past a
# 3 s limit, once as it is and once ignoring SIGTERM, ends with status 124
# and the limit's message, and nothing of it is still running afterwards
# (#197). It runs in IRIS_TOOLS_ENV_VERSION, the version bin/check runs
# lib/tests in, so a first bin/check pulls it here instead. Under GitHub Actions Docker must be reachable; elsewhere a
# runtime that isn't is skipped. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_envrun_limit.sh
#
# bin/check name: envrun time limit test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
. lib/katana.sh
version="$IRIS_TOOLS_ENV_VERSION"

runtimes=()
command -v apptainer > /dev/null && runtimes+=(apptainer)
if docker info > /dev/null 2>&1; then
    runtimes+=(docker)
elif [ -n "${GITHUB_ACTIONS-}" ]; then
    echo "envrun time limit: Docker isn't reachable on this runner"
fi

# still_running <runtime> <marker>: what of a run marked <marker> is
# still running: under Docker, any container envrun named.
still_running() {
    if [ "$1" = docker ]; then
        docker ps --filter name=iris-envrun- --no-trunc --format '{{.Names}} {{.Command}}'
    else
        pgrep -af -- "$2"
    fi
}

# stop <runtime> <marker>: stops what still_running found, so a failed run
# leaves nothing behind.
stop() {
    if [ "$1" = docker ]; then
        docker ps -q --filter name=iris-envrun- | xargs -r docker kill > /dev/null
    else
        pkill -KILL -f -- "$2"
    fi
}

for runtime in "${runtimes[@]}"; do
    for kind in plain "ignoring SIGTERM"; do
        marker="envrun-limit-$$-${kind// /-}"
        code="import time; time.sleep(60)  # $marker"
        [ "$kind" = plain ] || code="import signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)  # $marker"
        what="$runtime, $kind"
        # The first run's pull happens before the limit starts.
        IRIS_CONTAINER_RUNTIME="$runtime" bin/envrun --no-network "$version" true > /dev/null 2>&1 ||
            { echo "$what: $version doesn't run"; continue; }
        start=$SECONDS
        out="$(IRIS_CONTAINER_RUNTIME="$runtime" bin/envrun --no-network --time-limit 3 "$version" python -c "$code" 2>&1)"
        status=$? took=$((SECONDS - start))
        [ "$status" = 124 ] || { echo "$what: exit $status, not 124"; echo "$out" | sed 's/^/  /'; }
        grep -qF "ran past its 3 s limit" <<< "$out" || { echo "$what: no limit message in"; echo "$out" | sed 's/^/  /'; }
        [ "$took" -le 20 ] || echo "$what: took $took s"
        sleep 2
        still="$(still_running "$runtime" "$marker")"
        [ -z "$still" ] || { echo "$what: still running"; echo "$still" | sed 's/^/  /'; stop "$runtime" "$marker"; }
    done
done
