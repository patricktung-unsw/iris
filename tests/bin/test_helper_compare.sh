#!/bin/bash
# bin/helper-compare, for real, on the fork commit lib/tests/form_helper.rb's
# header names: every case matches (#187). Then on a scratch copy of the
# clone whose helper prints a final newline, #167's one-byte difference,
# every case differs, names it and exits 1; and a run stopped mid-way
# leaves no process and nothing in its TMPDIR, as neither of the others
# does. Prints each failed case and nothing on success, so bin/check can
# run it. It covers bin/helper-compare, bin/helper-compare.py,
# lib/tests/form_helper.rb, workflows/hello-world/form.yml.erb and
# workflows/microct-2d-segmentation/form.yml.erb.
#
#   tests/bin/test_helper_compare.sh
#
# It needs the fork's clone beside this clone, ../OpenComposer, holding
# that commit, and what bin/helper-compare's header lists. With no clone
# there, as in CI or a workflow author's clone, it runs nothing and passes:
# run it on the desktop, where the IRIS maintainer keeps the fork's clone.
#
# bin/check name: helper compare test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fork="$(dirname "$PWD")/OpenComposer"
git -C "$fork" rev-parse --git-dir > /dev/null 2>&1 || exit 0

fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
mkdir "$fake/tmp"
export TMPDIR="$fake/tmp"
# The header line bin/ocpull reads the commit from.
commit=$(sed -nE 's/^# ([0-9a-f]{7,40}), the commit bin\/ocpull keeps .*/\1/p' lib/tests/form_helper.rb)
[ -n "$commit" ] || { echo "helper compare: no commit in lib/tests/form_helper.rb's header"; exit 0; }
cases="hello-world defaults
hello-world changed
microct-2d-segmentation defaults
microct-2d-segmentation changed"

# leftovers <what>: names anything a run left in TMPDIR or still running.
leftovers() {
    local left
    left="$(ls -A "$TMPDIR")"
    [ -z "$left" ] || echo "helper compare: $1 left in TMPDIR: $left"
    left="$(pgrep -af -- "$TMPDIR")"
    [ -z "$left" ] || echo "helper compare: $1 left running: $left"
}

out="$(bin/helper-compare "$commit" 2>&1)"
code=$?
[ "$code" = 0 ] || echo "helper compare: on $commit, exit $code, not 0:"$'\n'"$out"
[ "$(sed -n 's/^same: //p' <<< "$out")" = "$cases" ] ||
    echo "helper compare: on $commit, not every case printed same:"$'\n'"$out"
leftovers "a passing run"

# The scratch copy: the tool, the helper and the two forms' folders.
copy="$fake/iris"
mkdir -p "$copy/bin" "$copy/lib/tests" "$copy/workflows"
cp bin/helper-compare bin/helper-compare.py "$copy/bin/"
cp lib/tests/form_helper.rb "$copy/lib/tests/"
cp -r workflows/hello-world workflows/microct-2d-segmentation "$copy/workflows/"
sed -i 's/^  print FormHelper.script(form, values)$/  puts FormHelper.script(form, values)/' "$copy/lib/tests/form_helper.rb"
grep -qx '  puts FormHelper.script(form, values)' "$copy/lib/tests/form_helper.rb" ||
    echo "helper compare: the copy's helper still prints no final newline; the test's sed needs updating"
out="$("$copy/bin/helper-compare" --repo "$fork" "$commit" 2>&1)"
code=$?
[ "$code" = 1 ] || echo "helper compare: with a final newline, exit $code, not 1:"$'\n'"$out"
[ "$(sed -n 's/^DIFFERENT: //p' <<< "$out")" = "$cases" ] ||
    echo "helper compare: with a final newline, not every case printed DIFFERENT:"$'\n'"$out"
[ "$(grep -c '^\\ No newline at end of file$' <<< "$out")" = 4 ] ||
    echo "helper compare: with a final newline, the diffs don't each mark it:"$'\n'"$out"
leftovers "a failing run"

# Stopped once its instance is up: TERM, as a closed terminal or a kill
# sends, ends it at once with 143.
bin/helper-compare "$commit" > "$fake/out" 2>&1 &
pid=$!
for _ in $(seq 100); do
    compgen -G "$TMPDIR/helper-compare.*/work/instance/rackup.log" > /dev/null && break
    sleep 0.1
done
compgen -G "$TMPDIR/helper-compare.*/work/instance/rackup.log" > /dev/null ||
    echo "helper compare: no instance started within 10 s:"$'\n'"$(cat "$fake/out")"
kill -TERM "$pid"
wait "$pid"
code=$?
[ "$code" = 143 ] || echo "helper compare: stopped, exit $code, not 143:"$'\n'"$(cat "$fake/out")"
grep -q '^same: microct-2d-segmentation changed$' "$fake/out" &&
    echo "helper compare: stopped, it ran on to the end:"$'\n'"$(cat "$fake/out")"
leftovers "a stopped run"
