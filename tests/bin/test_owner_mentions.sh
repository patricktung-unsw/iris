#!/bin/bash
# bin/owner-mentions against a throwaway tree of workflows and their
# manifests, fed a PR's changed paths. Prints each failed case and nothing
# on success, so bin/check can run it.
#
#   tests/bin/test_owner_mentions.sh
#
# bin/check name: owner-mentions test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The tree: seg and denoise owned by jdoe, recon by asmith, hello-world
# with no owner, broken with an owner block bin/manifest-owner refuses.
tree="$scratch/tree"
mkdir -p "$tree/bin"
cp bin/owner-mentions bin/manifest-owner "$tree/bin/"
owned() {
    mkdir -p "$tree/workflows/$1"
    printf '%s\n' "name: $1" 'owner:' "  name: $2" "  github: $3" "  email: $3@example.org" > "$tree/workflows/$1/manifest.yml"
}
owned seg "Jane Doe" jdoe
owned denoise "Jane Doe" jdoe
owned recon "Ann Smith" asmith
owned broken "Bad Login" "@bad"
mkdir -p "$tree/workflows/hello-world"
echo 'name: Hello world' > "$tree/workflows/hello-world/manifest.yml"
marker='<!-- iris-owner-mention -->'

# mentions <case> <author> <paths> <earlier> <want>...: the comment for a PR
# by <author> changing <paths> (one per line), after the earlier comments
# <earlier> (empty for none), holds exactly the lines <want> after its
# marker and opening line; no <want> means it prints nothing.
mentions() {
    local name="$1" author="$2" paths="$3" earlier="$4" out want rc
    shift 4
    printf '%s' "$earlier" > "$scratch/earlier"
    out="$(printf '%s\n' "$paths" | "$tree/bin/owner-mentions" "$author" "$scratch/earlier" 2> "$scratch/err")"
    rc=$?
    [ "$rc" = 0 ] || { echo "$name: exit $rc, expected 0"; sed 's/^/  /' "$scratch/err"; }
    if [ $# = 0 ]; then
        [ -z "$out" ] || { echo "$name: printed a comment, expected none:"; echo "$out" | sed 's/^/  /'; }
        return
    fi
    want="$(printf '%s\n' "$@")"
    [ "$(head -n1 <<< "$out")" = "$marker" ] || echo "$name: the comment doesn't start with $marker"
    [ "$(grep '^- ' <<< "$out")" = "$want" ] ||
        { echo "$name: the comment's mentions are not:"; echo "$want" | sed 's/^/    /'; echo "  it printed:"; echo "$out" | sed 's/^/    /'; }
}

mentions one-file someone 'workflows/seg/src/run.py' '' \
    '- @jdoe: `workflows/seg/`'
mentions two-files-one-folder someone $'workflows/seg/src/run.py\nworkflows/seg/index.html' '' \
    '- @jdoe: `workflows/seg/`'
mentions one-owner-two-folders someone $'workflows/seg/index.html\nworkflows/denoise/index.html' '' \
    '- @jdoe: `workflows/denoise/`, `workflows/seg/`'
mentions two-owners someone $'workflows/seg/index.html\nworkflows/recon/form.yml.erb' '' \
    '- @asmith: `workflows/recon/`' '- @jdoe: `workflows/seg/`'
mentions outside-workflows someone $'index.html\nlib/iris-job.sh\nworkflows/README' ''
mentions owner-is-author jdoe 'workflows/seg/index.html' ''
mentions owner-is-author-other-case JDoe 'workflows/seg/index.html' ''
mentions author-skips-only-theirs jdoe $'workflows/seg/index.html\nworkflows/recon/index.html' '' \
    '- @asmith: `workflows/recon/`'
# A new workflow's folder has no manifest on the base branch: its author
# is its owner, so there is no one to mention.
mentions new-folder someone 'workflows/brand-new/index.html' ''
mentions no-owner someone 'workflows/hello-world/form.yml.erb' ''
mentions already-mentioned someone 'workflows/seg/index.html' "$marker"$'\n- @jdoe: `workflows/seg/`\n'
mentions mentioned-other-case someone 'workflows/seg/index.html' "$marker"$'\n- @JDOE: `workflows/seg/`\n'
mentions only-the-new-owner someone $'workflows/seg/index.html\nworkflows/recon/index.html' "$marker"$'\n- @jdoe: `workflows/seg/`\n' \
    '- @asmith: `workflows/recon/`'
# A login that is a prefix of an earlier one is still new.
owned short "Jo Doe" jdo
mentions prefix-login someone 'workflows/short/index.html' "$marker"$'\n- @jdoe: `workflows/seg/`\n' \
    '- @jdo: `workflows/short/`'
mentions crlf-paths someone $'workflows/seg/index.html\r' '' \
    '- @jdoe: `workflows/seg/`'

# A manifest whose owner block is refused mentions no one for it, says so
# on stderr and still exits 0, so the others are still mentioned.
mentions broken-manifest someone $'workflows/broken/index.html\nworkflows/seg/index.html' '' \
    '- @jdoe: `workflows/seg/`'
grep -qF workflows/broken/manifest.yml "$scratch/err" || echo "broken-manifest: no warning naming the manifest on stderr"

# Without an earlier-comments file, every owner is new.
out="$(echo workflows/seg/index.html | "$tree/bin/owner-mentions" someone)"
grep -qx -- '- @jdoe: `workflows/seg/`' <<< "$out" || echo "no-earlier-file: didn't mention @jdoe"
