#!/bin/bash
# bin/check's workflow-owner check against throwaway repo trees: a copy of
# bin/check in a scratch folder checks the workflows beside it. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_workflow_owner.sh
#
# bin/check name: workflow owner test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# A tree in $scratch/<name> holding bin/check and a catalogue that passes:
# a workflow with a form, its owner in its manifest and on its page;
# hello-world, which has a form and a manifest and no owner; and a Planned
# workflow, which has a page and no form.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active later:ct-lab:planned
    cp bin/manifest-owner "$tree/bin/"
    mkdir -p "$tree/workflows/hello-world"
    touch "$tree/workflows/seg/form.yml.erb" "$tree/workflows/hello-world/form.yml.erb"
    owner_line jdoe "Jane Doe" >> "$tree/workflows/seg/index.html"
    manifest_with jdoe "Jane Doe" > "$tree/workflows/seg/manifest.yml"
    echo 'name: Hello world' > "$tree/workflows/hello-world/manifest.yml"
    echo '<h1 class="wf-title">Hello world</h1>' > "$tree/workflows/hello-world/index.html"
}

# The page line naming <login> (<name>) as the workflow owner, with
# <email> (jdoe@example.org if not given) as their contact, as
# templates/workflow-page.html has it.
owner_line() {
    local email="${3:-jdoe@example.org}"
    echo "  <p class=\"wf-owner\">Workflow owner: <a href=\"https://github.com/$1\" target=\"_blank\">$2</a> · <a href=\"mailto:$email\">$email</a></p>"
}

# A manifest naming <login> (<name>) as the workflow owner, with <email>
# (jdoe@example.org if not given).
manifest_with() {
    printf '%s\n' 'name: Seg' 'category: Imaging' 'owner:' "  name: $2" "  github: $1" "  email: ${3:-jdoe@example.org}"
}

# replace_owner_line <tree> <line>: the seg page's owner line becomes <line>.
replace_owner_line() {
    sed -i '/wf-owner/d' "$scratch/$1/workflows/seg/index.html"
    echo "$2" >> "$scratch/$1/workflows/seg/index.html"
}

# owners <pass|fail> <name>: the check over $scratch/<name>, which the
# caller has built and changed.
owners() {
    expect "$1" "$scratch/$2" "workflow owner in the manifest"
}

make_tree clean
owners pass clean

make_tree no-owner-on-page
sed -i '/wf-owner/d' "$scratch/no-owner-on-page/workflows/seg/index.html"
owners fail no-owner-on-page

make_tree no-owner-in-manifest
echo 'name: Seg' > "$scratch/no-owner-in-manifest/workflows/seg/manifest.yml"
owners fail no-owner-in-manifest

make_tree no-manifest
rm "$scratch/no-manifest/workflows/seg/manifest.yml"
owners fail no-manifest

make_tree malformed-owner
manifest_with @jdoe "Jane Doe" > "$scratch/malformed-owner/workflows/seg/manifest.yml"
owners fail malformed-owner

make_tree manifest-names-someone-else
manifest_with someone "Jane Doe" > "$scratch/manifest-names-someone-else/workflows/seg/manifest.yml"
owners fail manifest-names-someone-else

make_tree page-names-someone-else
sed -i '/wf-owner/d' "$scratch/page-names-someone-else/workflows/seg/index.html"
owner_line someone "Jane Doe" >> "$scratch/page-names-someone-else/workflows/seg/index.html"
owners fail page-names-someone-else

make_tree names-differ
manifest_with jdoe "Joe Bloggs" > "$scratch/names-differ/workflows/seg/manifest.yml"
owners fail names-differ

make_tree no-contact-on-page
replace_owner_line no-contact-on-page '  <p class="wf-owner">Workflow owner: <a href="https://github.com/jdoe" target="_blank">Jane Doe</a></p>'
owners fail no-contact-on-page

make_tree page-contact-differs
replace_owner_line page-contact-differs "$(owner_line jdoe "Jane Doe" jane@example.org)"
owners fail page-contact-differs

make_tree link-text-differs-from-mailto
replace_owner_line link-text-differs-from-mailto '  <p class="wf-owner">Workflow owner: <a href="https://github.com/jdoe" target="_blank">Jane Doe</a> · <a href="mailto:jdoe@example.org">jane@example.org</a></p>'
owners fail link-text-differs-from-mailto

make_tree no-email-in-manifest
printf '%s\n' 'name: Seg' 'owner:' '  name: Jane Doe' '  github: jdoe' > "$scratch/no-email-in-manifest/workflows/seg/manifest.yml"
owners fail no-email-in-manifest

make_tree with-orcid
echo '  orcid: 0000-0002-1825-0097' >> "$scratch/with-orcid/workflows/seg/manifest.yml"
owners pass with-orcid

make_tree hello-world-with-owner
manifest_with jdoe "Jane Doe" > "$scratch/hello-world-with-owner/workflows/hello-world/manifest.yml"
owners pass hello-world-with-owner

# CODEOWNERS is no longer how an owner hears of a PR: a /workflows/ line
# in any file GitHub reads fails, other paths pass.
for f in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    t="codeowners-line-in-${f//\//-}"
    make_tree "$t"
    mkdir -p "$(dirname "$scratch/$t/$f")"
    echo '/workflows/seg/ @jdoe' > "$scratch/$t/$f"
    owners fail "$t"
done

make_tree codeowners-for-other-paths
mkdir -p "$scratch/codeowners-for-other-paths/.github"
echo '/bin/ @jdoe' > "$scratch/codeowners-for-other-paths/.github/CODEOWNERS"
owners pass codeowners-for-other-paths

make_tree crlf
sed -i 's/$/\r/' "$scratch/crlf/workflows/seg/manifest.yml" "$scratch/crlf/workflows/seg/index.html"
owners pass crlf
