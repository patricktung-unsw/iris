#!/bin/bash
# bin/manifest-owner against fixture manifests. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_manifest_owner.sh
#
# bin/check name: manifest-owner test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# manifest <name> <line>...: $scratch/<name>.yml, an OpenComposer manifest
# whose lines after the menu entry are those given.
manifest() {
    local name="$1"
    shift
    printf '%s\n' 'name: Seg' 'category: Imaging' 'description: |' '  Segments.' "$@" > "$scratch/$name.yml"
}

# reads <case> <field> <want>: the field's value is <want>, exit 0.
reads() {
    local out
    out="$(bin/manifest-owner "$scratch/$1.yml" "$2" 2>&1)" ||
        { echo "$1: $2: exit $?, expected 0"; echo "$out" | sed 's/^/  /'; return; }
    [ "$out" = "$3" ] || echo "$1: $2 read \"$out\", expected \"$3\""
}

# refuses <case> <field>: exit 1, with a message naming the manifest.
refuses() {
    local out rc
    out="$(bin/manifest-owner "$scratch/$1.yml" "$2" 2>&1)"
    rc=$?
    [ "$rc" = 1 ] && grep -qF "$scratch/$1.yml" <<< "$out" ||
        { echo "$1: $2: exit $rc, expected 1 naming the manifest"; echo "$out" | sed 's/^/  /'; }
}

full=('owner:' '  name: Jane Doe' '  github: jdoe' '  orcid: 0000-0002-1825-0097')

manifest full "${full[@]}"
reads full name "Jane Doe"
reads full github jdoe
reads full orcid 0000-0002-1825-0097
# No field: checks the owner block, prints nothing.
reads full "" ""

manifest no-orcid 'owner:' '  name: Jane Doe' '  github: jdoe'
reads no-orcid orcid ""
reads no-orcid github jdoe

manifest orcid-x 'owner:' '  name: Jane Doe' '  github: jdoe' '  orcid: 0000-0002-1694-233X'
reads orcid-x orcid 0000-0002-1694-233X

manifest quoted-and-commented 'owner:  # the workflow owner' '  name: "Jane Doe"  # as on the page' "  github: 'jdoe'"
reads quoted-and-commented name "Jane Doe"
reads quoted-and-commented github jdoe

# The owner block may come first, ended by the next top-level key.
printf '%s\n' "${full[@]}" 'name: Seg' > "$scratch/first.yml"
reads first github jdoe

manifest crlf "${full[@]}"
sed -i 's/$/\r/' "$scratch/crlf.yml"
reads crlf name "Jane Doe"
reads crlf github jdoe

manifest none
refuses none github
refuses none ""

manifest no-github 'owner:' '  name: Jane Doe'
refuses no-github github
refuses no-github ""

manifest no-name 'owner:' '  github: jdoe'
refuses no-name name
refuses no-name ""

manifest at-sign 'owner:' '  name: Jane Doe' '  github: "@jdoe"'
refuses at-sign github

manifest bad-login 'owner:' '  name: Jane Doe' '  github: jane_doe'
refuses bad-login github

manifest bad-orcid 'owner:' '  name: Jane Doe' '  github: jdoe' '  orcid: https://orcid.org/0000-0002-1825-0097'
refuses bad-orcid ""

manifest unknown-key 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org'
refuses unknown-key ""

manifest flow-map 'owner: {name: Jane Doe, github: jdoe}'
refuses flow-map github

manifest two-blocks "${full[@]}" 'owner:' '  name: Joe Bloggs' '  github: jbloggs'
refuses two-blocks github

manifest unknown-field "${full[@]}"
refuses unknown-field email

[ ! -e "$scratch/gone.yml" ]
refuses gone github
