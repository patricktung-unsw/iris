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

full=('owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org' '  orcid: 0000-0002-1825-0097')

manifest full "${full[@]}"
reads full name "Jane Doe"
reads full github jdoe
reads full email jdoe@example.org
reads full orcid 0000-0002-1825-0097
# No field: checks the owner block, prints nothing.
reads full "" ""

manifest no-orcid 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org'
reads no-orcid orcid ""
reads no-orcid github jdoe

manifest orcid-x 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org' '  orcid: 0000-0002-1694-233X'
reads orcid-x orcid 0000-0002-1694-233X

manifest quoted-and-commented 'owner:  # the workflow owner' '  name: "Jane Doe"  # as on the page' "  github: 'jdoe'" '  email: "jdoe@example.org"  # the page links it'
reads quoted-and-commented name "Jane Doe"
reads quoted-and-commented github jdoe
reads quoted-and-commented email jdoe@example.org

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

manifest no-github 'owner:' '  name: Jane Doe' '  email: jdoe@example.org'
refuses no-github github
refuses no-github ""

manifest no-name 'owner:' '  github: jdoe' '  email: jdoe@example.org'
refuses no-name name
refuses no-name ""

manifest no-email 'owner:' '  name: Jane Doe' '  github: jdoe'
refuses no-email email
refuses no-email ""

manifest mailto 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: mailto:jdoe@example.org'
refuses mailto email

manifest not-an-address 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe'
refuses not-an-address email

manifest two-addresses 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org jane@example.org'
refuses two-addresses email

manifest at-sign 'owner:' '  name: Jane Doe' '  github: "@jdoe"' '  email: jdoe@example.org'
refuses at-sign github

manifest bad-login 'owner:' '  name: Jane Doe' '  github: jane_doe' '  email: jdoe@example.org'
refuses bad-login github

manifest bad-orcid 'owner:' '  name: Jane Doe' '  github: jdoe' '  email: jdoe@example.org' '  orcid: https://orcid.org/0000-0002-1825-0097'
refuses bad-orcid ""

manifest unknown-key "${full[@]}" '  phone: 555 0100'
refuses unknown-key ""

manifest flow-map 'owner: {name: Jane Doe, github: jdoe}'
refuses flow-map github

manifest two-blocks "${full[@]}" 'owner:' '  name: Joe Bloggs' '  github: jbloggs'
refuses two-blocks github

manifest unknown-field "${full[@]}"
refuses unknown-field phone

[ ! -e "$scratch/gone.yml" ]
refuses gone github
