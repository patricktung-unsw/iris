#!/bin/bash
# tests/bin/lib.sh's digest_map and digest_map_add on scratch copies of
# lib/katana.sh: the map ends up holding exactly the entries given, the
# tools version is set when asked, and each helper fails, naming the file,
# when the map or the tools version line isn't there, so a fixture can't
# keep the real map by mistake (#200); and, with SIGPIPE ignored, on a copy
# padded past a pipe's buffer, the helpers still pass and print nothing on
# stderr (#239). Prints each failed case and nothing on success, so
# bin/check can run it.
#
#   tests/bin/test_digest_map.sh
#
# bin/check name: digest map helper test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

a=sha256:$(printf 'a%.0s' {1..64})
f="$scratch/katana.sh"
fail() { echo "digest map helper: $*"; }
# map_of <file>: the lines between the map's opening line and its ")",
# read here on its own rather than through lib.sh's, so the check doesn't
# share the code it checks.
map_of() { sed -n '/^declare -gA IRIS_ENV_DIGESTS=($/,/^)$/p' "$1" | sed '1d;$d'; }

# Replacing: exactly the entries given, in order; the tools line and
# everything else untouched without --tools.
cp lib/katana.sh "$f"
out="$(digest_map "$f" "ct/1=$a" ct/2=unpublished 2>&1)" || fail "refused a real lib/katana.sh: $out"
[ -z "$out" ] || fail "printed on success: $out"
[ "$(map_of "$f")" = "$(printf '    [ct/1]=%s\n    [ct/2]=unpublished' "$a")" ] ||
    { fail "map isn't the entries given:"; map_of "$f" | sed 's/^/  /'; }
[ "$(grep '^IRIS_TOOLS_ENV_VERSION=' "$f")" = "$(grep '^IRIS_TOOLS_ENV_VERSION=' lib/katana.sh)" ] ||
    fail "changed the tools version without --tools"
grep -q '^declare -gA IRIS_LAB_ENVS=($' "$f" || fail "lost the lab table"

# --tools sets the tools version; no entries empties the map.
cp lib/katana.sh "$f"
digest_map "$f" --tools ct/1 > /dev/null || fail "refused --tools with no entries"
grep -qx 'IRIS_TOOLS_ENV_VERSION=ct/1' "$f" || fail "--tools didn't set the tools version"
[ -z "$(map_of "$f")" ] || fail "no entries left a map of: $(map_of "$f")"

# No map: fails, naming the file.
grep -v '^declare -gA IRIS_ENV_DIGESTS=(' lib/katana.sh > "$f"
out="$(digest_map "$f" ct/1=unpublished 2>&1)" && fail "passed on a file with no map"
grep -qF -- "$f" <<< "$out" || fail "no-map failure doesn't name the file: $out"
out="$(digest_map_add "$f" ct/1=unpublished 2>&1)" && fail "digest_map_add passed on a file with no map"
grep -qF -- "$f" <<< "$out" || fail "digest_map_add's no-map failure doesn't name the file: $out"

# No closing ")": fails, naming the file.
grep -vx ')' lib/katana.sh > "$f"
out="$(digest_map "$f" ct/1=unpublished 2>&1)" && fail "passed on a map with no closing )"
grep -qF -- "$f" <<< "$out" || fail "unclosed-map failure doesn't name the file: $out"

# No tools version line, with --tools: fails, naming the file.
grep -v '^IRIS_TOOLS_ENV_VERSION=' lib/katana.sh > "$f"
out="$(digest_map "$f" --tools ct/1 ct/1=unpublished 2>&1)" && fail "passed on a file with no tools version line"
grep -qF -- "$f" <<< "$out" || fail "no-tools-line failure doesn't name the file: $out"

# Adding: one line at the top of the map, the rest kept.
cp lib/katana.sh "$f"
out="$(digest_map_add "$f" ct/9=unpublished 2>&1)" || fail "digest_map_add refused a real lib/katana.sh: $out"
[ "$(map_of "$f")" = "$(printf '    [ct/9]=unpublished\n'; map_of lib/katana.sh)" ] ||
    { fail "digest_map_add's map isn't the line plus the real map:"; map_of "$f" | sed 's/^/  /'; }

# With SIGPIPE ignored, a writer whose reader exits early prints "Broken
# pipe" on stderr rather than dying silently, which fails any test that
# prints it (#239: once in CI, where what made sed see the closed pipe is
# still unknown). The trap below reproduces that every time: the padded
# copy holds far more than a pipe's buffer inside the map and after its
# ")", so a helper whose reader stops at its first match always leaves its
# writer blocked on a closed pipe, rather than only now and then.
# padded <file>: lib/katana.sh with 4,000 extra map entries and 4,000
# comment lines after the map's ")".
padded() {
    awk '{ print }
        $0 == "declare -gA IRIS_ENV_DIGESTS=(" { for (i = 0; i < 4000; i++) printf "    [pad/%d]=unpublished\n", i; in_map = 1 }
        in_map && $0 == ")" { for (i = 0; i < 4000; i++) printf "# padding line %d, past the digest map\n", i; in_map = 0 }' \
        lib/katana.sh > "$1"
}
# sigpipe_ignored <name> <cmd>...: runs <cmd> with SIGPIPE ignored, leaving
# its stdout in $out and returning its status, and fails <name> if it
# printed anything on stderr.
sigpipe_ignored() {
    local name="$1" err="$scratch/stderr" rc
    shift
    out="$(trap '' PIPE; "$@" 2> "$err")"
    rc=$?
    [ ! -s "$err" ] || { fail "$name printed on stderr with SIGPIPE ignored:"; sed 's/^/  /' "$err"; }
    return "$rc"
}
padded "$f"
sigpipe_ignored _digest_map_open _digest_map_open test "$f" ||
    fail "_digest_map_open refused a padded lib/katana.sh with SIGPIPE ignored: $out"
padded "$f"
sigpipe_ignored digest_map_add digest_map_add "$f" ct/9=unpublished ||
    fail "digest_map_add refused a padded lib/katana.sh with SIGPIPE ignored: $out"
padded "$f"
sigpipe_ignored digest_map digest_map "$f" "ct/1=$a" ||
    fail "digest_map refused a padded lib/katana.sh with SIGPIPE ignored: $out"
padded "$f"
grep -vx ')' "$f" > "$f.open" && mv "$f.open" "$f"
sigpipe_ignored "_digest_map_open on an unclosed map" _digest_map_open test "$f" &&
    fail "_digest_map_open passed on a padded map with no closing )"
[ "$out" = "test: $f's digest map has no closing ) line" ] ||
    fail "_digest_map_open's unclosed-map failure with SIGPIPE ignored isn't its message: $out"
