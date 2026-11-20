#!/bin/bash
# bin/check's early-exit pipes rule against throwaway trees: a pipe into
# grep -q or head in a shell file fails, a here-string or file argument
# passes, and _archive/ and a workflow's library copy aren't read. Prints
# each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_early_exit_pipes.sh
#
# bin/check name: early-exit pipes test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="early-exit pipes"
# The pipe symbol, kept out of this file's own lines so the rule, which
# reads this file too, finds no pipe here.
p='|'

# make_tree <name> <path> <line>...: a site tree holding <path>, a bash
# script of a shebang line and then each <line>.
make_tree() {
    local tree="$scratch/$1" path="$2"
    shift 2
    site_tree "$tree"
    mkdir -p "$(dirname "$tree/$path")"
    printf '%s\n' '#!/bin/bash' "$@" > "$tree/$path"
    git -C "$tree" add -A
}

# refused <name> <path> <line>...: the rule fails on the tree, naming
# <path> and the last line's number.
refused() {
    local tree="$scratch/$1" path="$2" out
    make_tree "$@"
    expect fail "$tree" "$name"
    out="$("$tree/bin/check" "$name" 2>&1)"
    grep -qF -- "  $path:$(($# - 1)): " <<< "$out" || echo "$1: the failure doesn't name $path:$(($# - 1)): $out"
}

# allowed <name> <path> <line>...: the rule passes on the tree.
allowed() {
    make_tree "$@"
    expect pass "$scratch/$1" "$name"
}

refused grep-q bin/tool "cat f $p grep -q x"
refused grep-combined bin/tool.sh "tr -d '\r' < f $p grep -qxF -- x && echo y"
refused grep-later-option bin/tool "cat f $p grep -E -q x"
refused grep-quiet bin/tool "cat f $p command grep --quiet x"
refused head bin/tool "x=\$(cat f $p head)"
refused head-1 bin/tool "x=\$(cat f $p head -1)"
refused line-end bin/tool "x=\$(cat f $p" "    head -n1)"
refused quoted bin/tool "echo \"git ls-files $p grep -q '^S'\""
refused pbs lib/tests/katana/job.pbs ': first' "cat f $p grep -q x"
refused second-pipe bin/tool "cat f $p sed 1d $p grep -q x"
refused stderr-too bin/tool "cat f $p& grep -q x" "cat f $p&head"
refused assignment bin/tool "cat f $p LC_ALL=C grep -q x"

allowed here-string bin/tool "grep -q x <<< \"\$(cat f)\""
allowed file-argument bin/tool "grep -q x f" "head -n1 f"
allowed or bin/tool "grep -q x f $p$p head -n1 f"
allowed other-readers bin/tool "cat f $p grep -c x" "cat f $p sed -n 1p" "cat f $p grep -e q"
allowed in-a-word bin/tool "not_sent preview \"tail${p}head\""
allowed comment bin/tool "# cat f $p grep -q x"
allowed archive _archive/old/run.sh "cat f $p grep -q x"
allowed library-copy workflows/w/lib/iris-job.sh "cat f $p head -1"

# A file with neither .sh nor a sh or bash shebang isn't a shell file.
make_tree not-shell assets/notes.txt
printf '%s\n' 'Notes' "cat f $p grep -q x" > "$scratch/not-shell/assets/notes.txt"
git -C "$scratch/not-shell" add -A
expect pass "$scratch/not-shell" "$name"
