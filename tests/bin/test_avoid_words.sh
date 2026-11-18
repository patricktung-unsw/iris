#!/bin/bash
# bin/check's rule that page text keeps to GLOSSARY.md's terms, against
# throwaway trees: "staging" is Transfer's Avoid word, and "stage" stays
# out of the rule since "stages" is ordinary English (#215). Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_avoid_words.sh
#
# bin/check name: page Avoid words test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="page uses a glossary Avoid word"

# make_page <name> <line>: a passing site whose guide page holds <line>.
make_page() {
    local tree="$scratch/$1"
    site_tree "$tree"
    printf '%s\n' "$2" >> "$tree/guide/index.html"
    git -C "$tree" add -A
}

make_page stages "<p>The diagram's four stages run from Transfer to Cite &amp; share.</p>"
expect pass "$scratch/stages" "$name"
make_page anchor '<a href="#stage">Transfer your dataset</a>'
expect pass "$scratch/anchor" "$name"

make_page staging '<p>Staging a dataset copies it into your scratch.</p>'
expect fail "$scratch/staging" "$name"
make_page staging-comment '<!-- Globus as the first staging route -->'
expect fail "$scratch/staging-comment" "$name"
make_page upload '<p>Upload your dataset.</p>'
expect fail "$scratch/upload" "$name"
