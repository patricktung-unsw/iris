#!/bin/bash
# Publish one built and checked environment version's container, as the
# containers workflow's Publish step does (.github/workflows/containers.yml),
# from GitHub Actions' own variables:
#
#   envs/publish-container.sh <local name> <env>/<n>
#
# - On unsw-restech/iris's main: pushed to IRIS_ENV_REGISTRY tagged
#   <env>-<n>, and the digest map line printed is the digest alone,
#   "    [<env>/<n>]=sha256:<hex>".
# - On any branch of a workflow author's fork (#138): pushed to their own
#   account's package, ghcr.io/<owner>/iris-env, <owner> lowercased as GHCR
#   needs, tagged <env>-<n>, and the line names that container in full,
#   "    [<env>/<n>]=ghcr.io/<owner>/iris-env@sha256:<hex>". The review batch
#   copies it into IRIS_ENV_REGISTRY by that digest and writes the digest
#   alone in its place (#142).
# - On any other branch of unsw-restech/iris: nothing is pushed.
#
# The line goes to the run's summary (GITHUB_STEP_SUMMARY) and its log.
# The tag is only a label: a rebuild moves it, and the digest is the
# version. Exits 1 if the push gives no digest.

set -euo pipefail

LOCAL="${1:?usage: envs/publish-container.sh <local name> <env>/<n>}"
VERSION="${2:?usage: envs/publish-container.sh <local name> <env>/<n>}"
cd "$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=lib/katana.sh
. lib/katana.sh
iris_is_env_version "$VERSION" || { echo "$VERSION is not <env>/<n>"; exit 1; }

if [ "${GITHUB_REPOSITORY:?}" = unsw-restech/iris ]; then
    if [ "${GITHUB_REF:?}" != refs/heads/main ]; then
        echo "Not published: on unsw-restech/iris only main publishes, and this is $GITHUB_REF."
        exit 0
    fi
    registry="$IRIS_ENV_REGISTRY" prefix=""
else
    owner="${GITHUB_REPOSITORY_OWNER:?}"
    registry="ghcr.io/${owner,,}/iris-env" prefix="ghcr.io/${owner,,}/iris-env@"
fi

ref="$registry:${VERSION/\//-}"
docker tag "$LOCAL" "$ref"
docker push "$ref"
digest="$(docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$ref" |
    sed -n "s|^$registry@||p" | head -n1)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "No digest for $ref after the push."; exit 1; }
line="    [$VERSION]=$prefix$digest"
echo "Published $ref as $registry@$digest"
echo "Digest map line: $line"
{
    echo "Published \`$ref\` as \`$registry@$digest\`."
    echo
    echo "In lib/katana.sh's digest map, replace \`[$VERSION]=unpublished\` with:"
    echo
    echo '```'
    echo "$line"
    echo '```'
    if [ -n "$prefix" ]; then
        echo
        echo "Then make the package public, on its page under your account's **Packages**, so the pull request's CI and the review batch can pull it (CONTRIBUTING.md, New environment versions)."
    fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
