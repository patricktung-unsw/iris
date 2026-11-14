#!/bin/bash
# bin/run-proof --check against throwaway repos, each a main branch and a
# pull request's branch off it: a current run proof passes, and a change
# to the workflow's folder after the proof's commit fails, a library copy
# update and an environment version move among them; so does a changed
# workflow with no proof. Run as CI runs it, it checks only a pull request,
# so a push, to main or anywhere, is never checked. Prints each failed case
# and nothing on success, so bin/check can run it.
#
#   tests/bin/test_run_proof_check.sh
#
# bin/check name: run proof check test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

commit() {
    git -C "$scratch/$1" add -A
    git -C "$scratch/$1" -c user.name=t -c user.email=t@example.org commit -q -m "${2:-change}"
}

# make_repo <name>: a repo whose main holds the seg workflow, an imaging
# workflow with a library copy pinning ct/1, and hello, a workflow with
# none, then a branch, pr, checked out. origin/main is main, as CI's
# checkout of a pull request has it.
make_repo() {
    local r="$scratch/$1"
    mkdir -p "$r/bin" "$r/workflows/seg/lib" "$r/workflows/seg/src" "$r/workflows/hello"
    cp bin/run-proof "$r/bin/run-proof"
    printf '%s\n' 'script: |' '  IRIS_ENV_VERSION=ct/1' > "$r/workflows/seg/form.yml.erb"
    echo "0123456789abcdef0123456789abcdef01234567" > "$r/workflows/seg/lib/copied-from"
    echo "# lib" > "$r/workflows/seg/lib/iris-job.sh"
    echo "print(1)" > "$r/workflows/seg/src/run.py"
    echo "script: |" > "$r/workflows/hello/form.yml.erb"
    echo "# repo" > "$r/README.md"
    git init -q -b main "$r"
    commit "$1" "main"
    git -C "$r" update-ref refs/remotes/origin/main main
    git -C "$r" checkout -q -b pr
}

# prove <name> [<commit>]: writes seg's run proof for <commit> (HEAD) and
# commits it, as an author does after bin/run-proof on Katana.
prove() {
    local r="$scratch/$1" c
    c="$(git -C "$r" rev-parse "${2:-HEAD}")"
    cat > "$r/workflows/seg/run-proof.json" <<EOF
{
  "format": 1,
  "workflow": "seg",
  "commit": "$c",
  "job": {"id": "9000001", "exit_status": 0},
  "environment": {"version": "ct/1", "digest": "sha256:$(printf 'a%.0s' {1..64})"},
  "form_tests": {"test": "tests/test_form.rb", "result": "3 runs, 5 assertions, 0 failures, 0 errors, 0 skips"},
  "written": "2026-11-14T00:00:00Z"
}
EOF
    commit "$1" "seg's run proof"
}

# expect <pass|fail> <name> <args>...: runs the check in repo <name>.
expect() {
    local want="$1" name="$2" out rc
    shift 2
    out="$("$scratch/$name/bin/run-proof" --check "$@" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && { [ "$rc" != 0 ] || [ -n "$out" ]; }; then
        echo "$name: exit $rc, expected a silent pass"
    elif [ "$want" = fail ] && [ "$rc" != 1 ]; then
        echo "$name: exit $rc, expected 1"
    elif [ "$want" = fail ] && [ -z "$out" ]; then
        echo "$name: failed with no message"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

# A pull request whose change to seg is proved at its last commit passes.
make_repo current
echo "print(2)" > "$scratch/current/workflows/seg/src/run.py"
commit current "seg's fix"
prove current
expect pass current origin/main
# As CI runs it on a pull request: against origin/<base branch>.
out="$(GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main "$scratch/current/bin/run-proof" --check 2>&1)" ||
    echo "current: failed as a pull request's CI run: $out"

# Any change to the folder after the proof's commit fails, and names it.
for change in code library-copy environment; do
    make_repo "after-$change"
    prove "after-$change"
    r="$scratch/after-$change/workflows/seg"
    case "$change" in
        code) echo "print(3)" > "$r/src/run.py" ;;
        library-copy) echo "fedcba9876543210fedcba9876543210fedcba98" > "$r/lib/copied-from"; echo "# newer" >> "$r/lib/iris-job.sh" ;;
        environment) printf '%s\n' 'script: |' '  IRIS_ENV_VERSION=ct/2' > "$r/form.yml.erb" ;;
    esac
    commit "after-$change" "seg after its proof"
    expect fail "after-$change" origin/main
    out="$("$scratch/after-$change/bin/run-proof" --check origin/main 2>&1)"
    case "$change" in
        code) f=src/run.py ;; library-copy) f=lib/copied-from ;; environment) f=form.yml.erb ;;
    esac
    grep -qF "workflows/seg/$f" <<< "$out" || echo "after-$change: the failure doesn't name workflows/seg/$f: $out"
    # The same, as CI runs it on a pull request.
    GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main "$scratch/after-$change/bin/run-proof" --check > /dev/null 2>&1 &&
        echo "after-$change: passed as a pull request's CI run"
done

# A pull request changing seg with no proof fails.
make_repo unproved
echo "print(2)" > "$scratch/unproved/workflows/seg/src/run.py"
commit unproved
expect fail unproved origin/main

# A proof whose commit isn't in the branch's history, as after a rebase,
# fails.
make_repo rebased
git -C "$scratch/rebased" checkout -q -b gone
echo "print(9)" > "$scratch/rebased/workflows/seg/src/run.py"
commit rebased "a commit later rewritten"
gone="$(git -C "$scratch/rebased" rev-parse HEAD)"
git -C "$scratch/rebased" checkout -q pr
echo "print(9)" > "$scratch/rebased/workflows/seg/src/run.py"
commit rebased "the rewritten commit"
prove rebased "$gone"
expect fail rebased origin/main

# A workflow with no library copy writes no run record, so needs no proof,
# and a pull request leaving seg alone needs none of seg.
make_repo elsewhere
echo "script: | # changed" > "$scratch/elsewhere/workflows/hello/form.yml.erb"
echo "# changed" > "$scratch/elsewhere/README.md"
commit elsewhere
expect pass elsewhere origin/main

# Only a pull request is checked: a push, to main or a branch, is not, nor
# is a run outside CI, however stale the proof.
make_repo pushed
prove pushed
echo "print(4)" > "$scratch/pushed/workflows/seg/src/run.py"
commit pushed
git -C "$scratch/pushed" checkout -q main
git -C "$scratch/pushed" merge -q --ff-only pr
for event in push ""; do
    out="$(GITHUB_EVENT_NAME=$event GITHUB_REF=refs/heads/main "$scratch/pushed/bin/run-proof" --check 2>&1)"
    rc=$?
    [ "$rc" = 0 ] && [ -z "$out" ] || echo "pushed: event '${event}' was checked (exit $rc): $out"
done

# A base that isn't a commit is a usage error, exit 2.
make_repo no-base
"$scratch/no-base/bin/run-proof" --check origin/nothing > /dev/null 2>&1
[ $? = 2 ] || echo "no-base: an unknown base did not exit 2"
