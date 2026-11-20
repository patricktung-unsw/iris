#!/bin/bash
# Report which workflows pass in a version just built, as the containers
# workflow's Report step does after every build (.github/workflows/containers.yml,
# #150):
#
#   envs/report-workflows.sh <local name> <env>/<n>
#
# Runs the tests of every workflow whose form pins an earlier version of
# <env>, any lab's, since labs may share an environment, in the container
# Docker holds as <local name>, as bin/check runs them: each workflow's
# tests/test_*.py from its tests/ folder, on CPU, with no network and
# the tests' time limit, through bin/envrun --container, leaving out a
# file marked "# bin/check: on the host", which runs outside any
# container (lib/katana.sh's iris_py_tests and IRIS_TEST_TIME_LIMIT).
# Lists each workflow, the version it pins and passed or failed, with a
# failure's first lines, in the run's summary (GITHUB_STEP_SUMMARY) and
# its log.
#
# It reports and never decides: a failing workflow doesn't fail the
# script, so the version is checked and published whatever the lab's
# other workflows do, and moving a workflow's pin stays its owner's
# choice (CONTRIBUTING.md, New environment versions). Exits 0 unless its
# own arguments or files are wrong.

set -uo pipefail

LOCAL="${1-}" VERSION="${2-}"
usage() { echo "usage: envs/report-workflows.sh <local name> <env>/<n>" >&2; exit 2; }
[ -n "$LOCAL" ] && [ $# = 2 ] || usage
repo="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=lib/katana.sh
. "$repo/lib/katana.sh"
iris_is_env_version "$VERSION" || usage
env="${VERSION%/*}" n="${VERSION#*/}"
summary_lines=30  # of a failure's output, in the summary

rows=()
declare -A failures=()
# result <text>: adds the workflow's row with <text> and logs it.
result() {
    rows+=("| \`$slug\` | \`$pin\` | $1 |")
    echo "$slug: ${1//\*/}"
}
for form in "$repo"/workflows/*/form.yml.erb; do
    [ -f "$form" ] || continue
    dir="${form%/form.yml.erb}"
    slug="${dir##*/}"
    pin="$(iris_form_pins "$form" | sed -n 1p)"
    [[ "$pin" == "$env"/* ]] && [ "${pin#*/}" -lt "$n" ] 2>/dev/null || continue
    mapfile -t tests < <(iris_py_tests "$dir/tests" container)
    if [ ${#tests[@]} = 0 ]; then
        result "no tests run in a container"
    elif out="$(cd "$dir/tests" && "$repo/bin/envrun" --no-network --time-limit "$IRIS_TEST_TIME_LIMIT" \
        --container "$LOCAL" "$VERSION" python -m unittest "${tests[@]}" 2>&1)"; then
        result passed
    else
        result "**failed**"
        failures[$slug]="$(head -n "$summary_lines" <<< "$out")"
        sed 's/^/  /' <<< "$out"
    fi
done

{
    echo "### Workflows in \`$VERSION\`"
    echo
    if [ ${#rows[@]} = 0 ]; then
        echo "No workflow pins an earlier version of \`$env\`, so there is nothing to report."
    else
        echo "Each workflow pinning an earlier version of \`$env\`, its tests run in \`$VERSION\` on CPU as \`bin/check\` runs them. A failure here never stops the version: its owner moves the workflow's pin, or not."
        echo
        echo "| Workflow | Pins | In \`$VERSION\` |"
        echo "|---|---|---|"
        printf '%s\n' "${rows[@]}"
        for slug in $(printf '%s\n' "${!failures[@]}" | sort); do
            echo
            echo "<details><summary><code>$slug</code>: the first $summary_lines lines of its output</summary>"
            echo
            echo '````'
            echo "${failures[$slug]}"
            echo '````'
            echo
            echo "</details>"
        done
    fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit 0
