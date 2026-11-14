#!/bin/bash
# bin/review-batch's listing against fixture pull request data: a fake `gh`
# on PATH answers `gh pr list` from a JSON file as gh prints it, and a
# throwaway origin holds each PR's head as refs/pull/<n>/head. The listing
# shows each ready PR with its diff and what it flags, ends with the one
# --apply line for the batch, and changes nothing: no merge, no push, no
# container copy, no branch or worktree. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_review_batch.sh
#
# bin/check name: review batch test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# Fakes: gh answers `pr list` from $fake/prs.json, or fails as gh does
# when $fake/gh-down exists; gh, docker and ssh each record their
# arguments, one call a line, in $fake/calls.
mkdir "$fake/bin"
cat > "$fake/bin/gh" <<'EOF'
#!/bin/bash
dir="$(dirname "$0")/.."
echo "gh $*" >> "$dir/calls"
[ -e "$dir/gh-down" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
[ "$1 $2" = "pr list" ] && { cat "$dir/prs.json"; exit 0; }
exit 1
EOF
for t in docker ssh; do
    printf '#!/bin/bash\necho "%s $*" >> "$(dirname "$0")/../calls"\nexit 1\n' "$t" > "$fake/bin/$t"
done
chmod +x "$fake/bin/"*

a64=$(printf 'a%.0s' {1..64}) b64=$(printf 'b%.0s' {1..64})
src="$fake/src" clone="$fake/iris"
commit() { git -C "$src" add -A && git -C "$src" commit -qm "$1"; }

# main: the ct-lab section with seg's card, the seg workflow, the lab
# table [ct-lab]=ct/1, ct/1's recipe, and the tools under test.
mkdir -p "$src/bin" "$src/lib" "$src/workflows/seg/src" "$src/envs/ct/1"
cp bin/review-batch bin/outside-folder "$src/bin/"
cp lib/katana.sh "$src/lib/"
sed -i -e '/^declare -gA IRIS_LAB_ENVS=(/,/^)/c\declare -gA IRIS_LAB_ENVS=(\n    [ct-lab]=ct/1\n)' \
    -e '/^declare -gA IRIS_ENV_DIGESTS=(/,/^)/c\declare -gA IRIS_ENV_DIGESTS=(\n    [ct/1]=sha256:'"$b64"'\n)' "$src/lib/katana.sh"
printf '%s\n' '<div class="lab" id="ct-lab">' '    <a href="workflows/seg/" class="workflow-card">' \
    '      <div class="card-name">seg</div>' '    </a>' '</div>' > "$src/index.html"
echo "print(1)" > "$src/workflows/seg/src/run.py"
echo "numpy==2.0" > "$src/envs/ct/1/requirements.lock"
echo "# IRIS" > "$src/README.md"
git init -q -b main "$src"
commit main

# PR 7: seg's next code in ct/2, an author's container, with a run proof
# whose digest isn't the one the map names.
git -C "$src" checkout -q -b pr7
echo "print(2)" > "$src/workflows/seg/src/run.py"
mkdir -p "$src/envs/ct/2"
printf '%s\n' "numpy==2.0" "scipy==1.14" > "$src/envs/ct/2/requirements.lock"
sed -i 's|^    \[ct/1\]=.*|&\n    [ct/2]=ghcr.io/alice-lab/iris-env@sha256:'"$a64"'|' "$src/lib/katana.sh"
printf '{"format": 1, "workflow": "seg", "environment": {"version": "ct/2", "digest": "sha256:%s"}}\n' "$b64" \
    > "$src/workflows/seg/run-proof.json"
commit "seg on ct/2"
pr7=$(git -C "$src" rev-parse HEAD)

# PR 9: a page edit and a README edit, which bin/outside-folder flags,
# and a new version left unpublished.
git -C "$src" checkout -q -b pr9 main
echo "<h1>seg</h1>" > "$src/workflows/seg/index.html"
echo "# IRIS, changed" > "$src/README.md"
mkdir -p "$src/envs/ct/2"
echo "numpy==2.1" > "$src/envs/ct/2/requirements.lock"
sed -i 's|^    \[ct/1\]=.*|&\n    [ct/2]=unpublished|' "$src/lib/katana.sh"
commit "seg's page"
pr9=$(git -C "$src" rev-parse HEAD)

# PR 12: a page edit alone, nothing to flag.
git -C "$src" checkout -q -b pr12 main
echo "<h1>seg, again</h1>" > "$src/workflows/seg/index.html"
commit "seg's heading"
pr12=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main

git clone -q --bare "$src" "$fake/origin.git"
for n in 7 9 12; do git -C "$src" push -q "$fake/origin.git" "pr$n:refs/pull/$n/head"; done
git clone -q "$fake/origin.git" "$clone"

# pr <number> <head> <title> <login> <mergeable> [<label>...]: one PR as
# gh pr list --json prints it.
pr() {
    local n="$1" head="$2" title="$3" login="$4" mergeable="$5" labels="" l
    shift 5
    for l in "$@"; do labels+="${labels:+,}{\"id\":\"L$l\",\"name\":\"$l\",\"description\":\"\",\"color\":\"0e8a16\"}"; done
    printf '{"author":{"id":"U1","is_bot":false,"login":"%s","name":""},"baseRefName":"main","body":"Body of #%s.\\r\\nUrgent: a quick fix.","headRefOid":"%s","labels":[%s],"mergeable":"%s","number":%s,"title":"%s","url":"https://github.com/unsw-restech/iris/pull/%s"}' \
        "$login" "$n" "$head" "$labels" "$mergeable" "$n" "$title" "$n"
}
# Newest first, as gh lists them.
printf '[%s,%s,%s]\n' "$(pr 12 "$pr12" "seg's heading" carol MERGEABLE ready)" \
    "$(pr 9 "$pr9" "seg's page" bob CONFLICTING ready outside-folder)" \
    "$(pr 7 "$pr7" "seg on ct/2" alice-lab MERGEABLE ready)" > "$fake/prs.json"

refs_before=$(git -C "$fake/origin.git" for-each-ref; git -C "$clone" for-each-ref refs/heads; git -C "$clone" worktree list)

failures=0
fail() { echo "$*"; failures=1; }
# run <arg>...: bin/review-batch in the clone with the fakes on PATH, into
# $out and $rc.
run() { rm -f "$fake/calls"; out="$(PATH="$fake/bin:$PATH" "$clone/bin/review-batch" "$@" 2>&1)"; rc=$?; }
has() { grep -qF -- "$1" <<< "$out" || fail "review-batch ${2:-listing}: output lacks '$1'"; }
lacks() { ! grep -qF -- "$1" <<< "$out" || fail "review-batch ${2:-listing}: output has '$1'"; }
show() { [ "$failures" = 0 ] || echo "$out" | sed 's/^/  /'; failures=0; }

run
[ "$rc" = 0 ] || fail "review-batch listing: exit $rc, expected 0"
grep -q '^gh pr list .*--label ready' "$fake/calls" || fail "review-batch listing: didn't ask gh for the ready PRs"
grep -q '^gh pr list .*--base main' "$fake/calls" || fail "review-batch listing: didn't limit the PRs to those into main"
# Each PR, oldest first, with its author, its body and its diff.
has "#7 seg on ct/2"; has "#9 seg's page"; has "#12 seg's heading"
[ "$(grep -n '#7 seg on ct/2' <<< "$out" | head -n1 | cut -d: -f1)" -lt "$(grep -n "#12 seg's heading" <<< "$out" | head -n1 | cut -d: -f1)" ] ||
    fail "review-batch listing: #12 comes before #7"
has "alice-lab"; has "Urgent: a quick fix."
has "+print(2)"; has "+# IRIS, changed"; has "workflows/seg/src/run.py"
# What each flags: the author's container to copy, its proof's other
# digest, what bin/outside-folder lists, a conflict, a version to publish.
has "ct/2: copy ghcr.io/alice-lab/iris-env@sha256:$a64 into ghcr.io/unsw-restech/iris-env"
has "run-proof.json ran ct/2 at sha256:$b64"
has "outside its folder: README.md"
has "conflicts with main"
has "ct/2 is unpublished"
has "Nothing flagged."
# The one yes: every PR, oldest first, pinned at the head reviewed.
has "bin/review-batch --apply 7:${pr7:0:12} 9:${pr9:0:12} 12:${pr12:0:12}"
# It changed nothing.
grep -vq '^gh pr list' "$fake/calls" && fail "review-batch listing: ran more than gh pr list: $(grep -v '^gh pr list' "$fake/calls")"
[ "$(git -C "$fake/origin.git" for-each-ref; git -C "$clone" for-each-ref refs/heads; git -C "$clone" worktree list)" = "$refs_before" ] ||
    fail "review-batch listing: changed a branch, a worktree or origin"
show

# No ready PR: nothing to review and no --apply line.
echo '[]' > "$fake/prs.json"
run
[ "$rc" = 0 ] || fail "review-batch empty: exit $rc, expected 0"
has "No ready pull requests" empty; lacks "--apply" empty
show

# gh can't list them: says so, exits 2.
touch "$fake/gh-down"
run
[ "$rc" = 2 ] || fail "review-batch gh-down: exit $rc, expected 2"
has "error connecting" gh-down
show
rm "$fake/gh-down"

# Usage errors exit 2 before anything runs.
for args in "--apply" "--apply 7" "--apply 7:zz" "--apply 7:abc1234;x" "bogus" \
    "--copy ct/2" "--copy ct/2 sha256:$a64" "--copy ct/2 ghcr.io/unsw-restech/iris-env@sha256:$a64" \
    "--copy nope ghcr.io/alice-lab/iris-env@sha256:$a64"; do
    # shellcheck disable=SC2086  # each case is its words
    run $args
    [ "$rc" = 2 ] || fail "review-batch $args: exit $rc, expected 2"
    has "usage:" "$args"
    [ ! -e "$fake/calls" ] || fail "review-batch $args: ran $(cat "$fake/calls")"
    show
done
