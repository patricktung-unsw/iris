#!/bin/bash
# bin/exec-bits and .githooks/pre-commit in a scratch repo: a script run by
# path that git's index holds as 100644 is listed, and the commit that
# stages it is refused with the command that fixes it, then goes through
# once the bit is set. core.fileMode is off on the Windows mount, so chmod
# alone records nothing; this catches it at the commit, not minutes later
# in a full bin/check (#200's retro). Prints each failed case and nothing
# on success, so bin/check can run it.
#
#   tests/bin/test_exec_bits.sh
#
# bin/check name: exec bits test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

repo="$scratch/repo"
fail() { echo "exec bits: $*"; }
mkdir -p "$repo/bin" "$repo/.githooks" "$repo/tests/bin"
cp bin/exec-bits "$repo/bin/"
cp .githooks/pre-commit "$repo/.githooks/"
git init -q "$repo"
git -C "$repo" config core.fileMode false
git -C "$repo" config core.hooksPath .githooks
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x bin/exec-bits .githooks/pre-commit
git -C "$repo" commit -qm tools || fail "refused a commit whose scripts are all 100755"

# A new test, chmod'ed on disk but 100644 in the index.
printf '#!/bin/bash\n' > "$repo/tests/bin/test_new.sh"
chmod +x "$repo/tests/bin/test_new.sh"
git -C "$repo" add tests/bin/test_new.sh
git -C "$repo" ls-files -s tests/bin/test_new.sh | grep -q '^100644' ||
    fail "setup: the scratch index didn't hold test_new.sh as 100644; core.fileMode isn't off"
out="$(cd "$repo" && bin/exec-bits)"
[ "$out" = tests/bin/test_new.sh ] || fail "bin/exec-bits listed '$out', expected tests/bin/test_new.sh"
out="$(cd "$repo/tests/bin" && ../../bin/exec-bits)"
[ "$out" = tests/bin/test_new.sh ] || fail "bin/exec-bits from tests/bin listed '$out', expected tests/bin/test_new.sh"
out="$(git -C "$repo" commit -qm new 2>&1)" && fail "pre-commit let a 100644 test through"
grep -qF 'tests/bin/test_new.sh' <<< "$out" || fail "pre-commit's refusal doesn't name the file: $out"
grep -qF 'git update-index --chmod=+x tests/bin/test_new.sh' <<< "$out" ||
    fail "pre-commit's refusal doesn't give the fix: $out"

# Once the bit is in the index, the commit goes through and nothing is listed.
git -C "$repo" update-index --chmod=+x tests/bin/test_new.sh
[ -z "$(cd "$repo" && bin/exec-bits)" ] || fail "bin/exec-bits still lists a file set 100755"
git -C "$repo" commit -qm new > /dev/null 2>&1 || fail "pre-commit refused once the bit was set"

# A file outside the list, such as a sourced library, may stay 100644.
printf 'x=1\n' > "$repo/tests/bin/lib.sh"
git -C "$repo" add tests/bin/lib.sh
git -C "$repo" commit -qm lib > /dev/null 2>&1 || fail "pre-commit refused a sourced file left 100644"
