#!/bin/bash
# bin/check's rule that a GLOSSARY.md entry's definition uses none of its
# own Avoid words, against throwaway trees: Minting was first defined as
# "Publishing a citable version" with publishing on its Avoid list (#213).
# Prints each failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_glossary_avoid.sh
#
# bin/check name: glossary Avoid test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="glossary entry uses its own Avoid word"

# make_glossary <name> <entry text>: a passing site whose GLOSSARY.md is
# one clean entry followed by <entry text>.
make_glossary() {
    local tree="$scratch/$1"
    site_tree "$tree"
    printf '%s\n' "# Glossary" "" "**Run**:" "One submission of a form." "_Avoid_: Execution" "" "$2" > "$tree/GLOSSARY.md"
    git -C "$tree" add -A
}

make_glossary clean $'**Minting**:\nMaking a citable version public on WorkflowHub.\n_Avoid_: Releasing, tagging, publishing'
expect pass "$scratch/clean" "$name"
make_glossary other-forms $'**Minting**:\nGiving a citable version its DOI, once published.\n_Avoid_: Releasing, tagging, publishing'
expect pass "$scratch/other-forms" "$name"
# A pair bin/check names on purpose: Container says registries call it an image.
make_glossary kept $'**Container**:\nRegistries call it an image; IRIS never does.\n_Avoid_: Image'
expect pass "$scratch/kept" "$name"

make_glossary own-word $'**Minting**:\nPublishing a citable version on WorkflowHub.\n_Avoid_: Releasing, tagging, publishing'
expect fail "$scratch/own-word" "$name"
make_glossary second-line $'**Minting**:\nMaking a citable version public.\nThe owner is releasing it.\n_Avoid_: Releasing, tagging, publishing'
expect fail "$scratch/second-line" "$name"
make_glossary multi-word $'**Container**:\nThe file a run starts inside, a container image.\n_Avoid_: Image, container image'
expect fail "$scratch/multi-word" "$name"
# A kept pair covers its own entry only.
make_glossary kept-elsewhere $'**Volume**:\nOne image stack.\n_Avoid_: Image, scan'
expect fail "$scratch/kept-elsewhere" "$name"
make_glossary crlf $'**Minting**:\r\nPublishing a citable version.\r\n_Avoid_: Releasing, tagging, publishing\r'
expect fail "$scratch/crlf" "$name"

# The failure names the line, the term and the word.
out="$("$scratch/own-word/bin/check" "$name" 2>&1)"
grep -qF "GLOSSARY.md:8: Minting's definition uses its own Avoid word \"publishing\"" <<< "$out" ||
    { echo "own-word: the failure doesn't name the line, term and word:"; echo "$out" | sed 's/^/  /'; }
