#!/bin/bash
# envs/publish-container.sh against a fake docker on the PATH, which logs
# its calls and, once a reference is pushed, gives it a digest. GitHub
# Actions' variables say which repository and branch the run is on. On
# unsw-restech/iris's main it publishes to the org's package and prints
# the digest alone for the digest map; on any branch of a workflow
# author's fork, to that account's own iris-env package, printing the
# container in full (#138); on any other branch of unsw-restech/iris,
# nothing. Prints each failed case and nothing on success, so bin/check
# can run it.
#
#   tests/bin/test_publish_container.sh
#
# bin/check name: publish container test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

hex=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
fake="$scratch/fake"
mkdir -p "$fake"
# Logs each call a line; inspect prints the pushed reference's repository
# with the digest, as docker does after a push.
cat > "$fake/docker" <<EOF
#!/bin/bash
echo "\$*" >> "$fake/docker.log"
if [ "\$1" = inspect ]; then
    ref="\${!#}"
    grep -qxF "push \$ref" "$fake/docker.log" && echo "\${ref%:*}@sha256:$hex"
fi
exit 0
EOF
chmod +x "$fake/docker"

# run <repository> <ref>: the script's output for microct/2, built as
# iris-env-build:local, with its summary in $scratch/summary.
run() {
    rm -f "$fake/docker.log" "$scratch/summary"
    out="$(env PATH="$fake:$PATH" GITHUB_REPOSITORY="$1" GITHUB_REPOSITORY_OWNER="${1%%/*}" GITHUB_REF="$2" \
        GITHUB_STEP_SUMMARY="$scratch/summary" envs/publish-container.sh iris-env-build:local microct/2 2>&1)"
    rc=$?
}
has() { grep -qF -- "$3" <<< "$2" || { echo "$1: no '$3' in"; echo "$2" | sed 's/^/  /'; }; }
pushed() { grep -qxF "push $2" "$fake/docker.log" 2>/dev/null || { echo "$1: didn't push $2"; sed 's/^/  /' "$fake/docker.log" 2>/dev/null; }; }

# The org's main: the org's package, and the digest alone.
run unsw-restech/iris refs/heads/main
[ "$rc" = 0 ] || { echo "main: exit $rc"; echo "$out" | sed 's/^/  /'; }
pushed main ghcr.io/unsw-restech/iris-env:microct-2
has "main summary" "$(cat "$scratch/summary" 2>/dev/null)" "    [microct/2]=sha256:$hex"

# A fork, on any branch: the author's own package, named in full, the
# owner lowercased as GHCR needs.
run An-Author/iris refs/heads/my-workflow
[ "$rc" = 0 ] || { echo "fork: exit $rc"; echo "$out" | sed 's/^/  /'; }
pushed fork ghcr.io/an-author/iris-env:microct-2
has "fork summary" "$(cat "$scratch/summary" 2>/dev/null)" "    [microct/2]=ghcr.io/an-author/iris-env@sha256:$hex"
! grep -q unsw-restech "$fake/docker.log" || { echo "fork: touched the org's package"; sed 's/^/  /' "$fake/docker.log"; }

# A branch of the org's repo builds and checks, and publishes nothing.
run unsw-restech/iris refs/heads/some-branch
[ "$rc" = 0 ] || { echo "org branch: exit $rc"; echo "$out" | sed 's/^/  /'; }
! grep -q '^push ' "$fake/docker.log" 2>/dev/null || { echo "org branch: pushed"; sed 's/^/  /' "$fake/docker.log"; }
has "org branch" "$out" "Not published"

# A push that gives no digest fails.
sed -i 's/^    grep -qxF/    false \&\& grep -qxF/' "$fake/docker"
run An-Author/iris refs/heads/my-workflow
[ "$rc" = 1 ] || { echo "no digest: exit $rc, expected 1"; echo "$out" | sed 's/^/  /'; }
