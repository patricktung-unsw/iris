#!/bin/bash
# bin/new-workflow against throwaway clones of this working tree: the
# workflow it makes fails bin/check while any placeholder it leaves
# remains, on the page, its card, its manifest or the tier table's job
# citation, and passes once they are all filled. It extends a Planned
# workflow's folder in place, and refuses, writing nothing, a slug that is
# taken or malformed, a lab with no lab table line and an owner
# bin/manifest-owner refuses. Prints each failed case and nothing on
# success, so bin/check can run it.
#
#   tests/bin/test_new_workflow.sh
#
# bin/check name: new-workflow test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# The checks a workflow's folder, card and tier row meet: everything in
# bin/check but the tests, the linters and the containers' Python tests,
# which a scaffold changes nothing for, or which are this test.
placeholder_checks=(
    "page template rules"
    "placeholders left in index.html or a manifest"
    "Run and verified workflows cite a job"
)
other_checks=(
    "untracked file the checks can't see"
    "usage tag matches the folder"
    "workflows' library copies match lib/"
    "run directory file names come from iris.rundir"
    "Katana constants match lib/katana.sh"
    "environment versions match the digest map"
    "form script: and check: sections"
    "imaging forms' rendered scripts"
    "form fields"
    "rendered-form tests"
    "manifests use a built-in bi- icon"
    "broken local links"
    "README repo map names real paths"
    "pre-launch notices match the Run buttons"
    "card status matches the CONTRIBUTING tier table"
    "cards sit in a lab section"
    "unmaintained workflows"
    "workflow page repeats the guide"
    "page uses a glossary Avoid word"
    "name uses a glossary Avoid word"
    "workflow owner in the manifest and on the page"
    "citable versions on workflow pages"
)

# clone <name>: a clone of this repo at HEAD, with history, so the
# library copies' commits are in it, and this working tree's files,
# tracked and not yet added, committed on top.
clone() {
    local c="$scratch/$1"
    git clone -q --shared --no-checkout . "$c"
    git -C "$c" checkout -q --detach "$(git rev-parse HEAD)"
    git ls-files -z --cached --others --exclude-standard |
        tar --null -T - --ignore-failed-read -cf - 2> /dev/null | tar -xf - -C "$c"
    git -C "$c" add -A
    git -C "$c" -c user.name=t -c user.email=t@example.org commit -q --allow-empty -m "The working tree"
}

# new <name> <arg>...: bin/new-workflow <arg>... in clone <name>, then
# every file it wrote added; prints its output to $scratch/<name>.out.
new() {
    local name="$1"
    shift
    (cd "$scratch/$name" && bin/new-workflow "$@") > "$scratch/$name.out" 2>&1 ||
        { echo "$name: bin/new-workflow $* failed:"; sed 's/^/  /' "$scratch/$name.out"; }
    git -C "$scratch/$name" add -A
}

# fill <name> <file>...: each {{TODO: ...}} in <file>s replaced with text,
# and the tier table's job citation with a job ID.
fill() {
    local c="$scratch/$1" f
    shift
    for f in "$@"; do
        if [ "$f" = CONTRIBUTING.md ]; then
            perl -i -pe 's/\(job \{\{TODO:[^}]*\}\}/(job 9999999/' "$c/$f"
        else
            perl -i -pe 's/\{\{TODO:[^}]*\}\}/Filled in./g' "$c/$f"
        fi
    done
    git -C "$c" add -A
}

# all <pass|fail> <name> <check>...: each check's verdict in clone <name>.
all() {
    local want="$1" name="$2" n
    shift 2
    for n in "$@"; do expect "$want" "$scratch/$name" "$n"; done
}

owner=(--owner-name "Jane Doe" --owner-github jdoe --owner-email jdoe@example.org)

# A new workflow in a lab: placeholders fail it, one kind at a time, and
# filled it passes.
clone fresh
new fresh scaffold-test --title "Scaffold Test" --lab microct-lab "${owner[@]}"
c="$scratch/fresh"
all fail fresh "${placeholder_checks[@]}"
all pass fresh "${other_checks[@]}"
fill fresh workflows/scaffold-test/index.html
expect pass "$c" "page template rules"
all fail fresh "placeholders left in index.html or a manifest" "Run and verified workflows cite a job"
fill fresh index.html workflows/scaffold-test/manifest.yml
expect pass "$c" "placeholders left in index.html or a manifest"
expect fail "$c" "Run and verified workflows cite a job"
fill fresh CONTRIBUTING.md
all pass fresh "${placeholder_checks[@]}" "${other_checks[@]}"

# What it made: the slug everywhere the reference's was, the library copy,
# the owner in the manifest, the card in its lab before the Planned cards,
# and the to-do list.
d="$c/workflows/scaffold-test"
for f in form.yml.erb src/run.py tests/test_form.rb tests/test_synthetic.py; do
    [ -f "$d/$f" ] || echo "fresh: no workflows/scaffold-test/$f"
done
! grep -rl 'microct-2d-segmentation\|iris_microct' "$d" > /dev/null ||
    echo "fresh: the reference's slug or job name is left in $(grep -rl 'microct-2d-segmentation\|iris_microct' "$d" | tr '\n' ' ')"
grep -qx '  #PBS -A iris-scaffold-test' "$d/form.yml.erb" || echo "fresh: the form's usage tag isn't iris-scaffold-test"
grep -qx '    value: "scaffold-test"' "$d/form.yml.erb" || echo "fresh: the experiment name default isn't scaffold-test"
grep -qx '    value: "iris_scaffold_test"' "$d/form.yml.erb" || echo "fresh: the job name default isn't iris_scaffold_test"
grep -qx '  IRIS_ENV_VERSION=microct/1' "$d/form.yml.erb" || echo "fresh: the form doesn't pin microct-lab's version, microct/1"
cmp -s "$c/lib/iris-job.sh" "$d/lib/iris-job.sh" && [ -s "$d/lib/copied-from" ] ||
    echo "fresh: workflows/scaffold-test/lib/ isn't bin/libcopy's copy of the library's job side"
[ ! -e "$d/run-proof.json" ] || echo "fresh: it copied the reference's run proof"
[ "$(cd "$c" && bin/manifest-owner workflows/scaffold-test/manifest.yml email)" = jdoe@example.org ] ||
    echo "fresh: the manifest's owner email isn't jdoe@example.org"
[ "$(cd "$c" && bin/manifest-owner workflows/scaffold-test/manifest.yml name)" = "Jane Doe" ] ||
    echo "fresh: the manifest's owner name isn't Jane Doe"
order=$(grep -o 'href="workflows/[a-z0-9-]*/" class="workflow-card[^"]*"' "$c/index.html" | sed -n '1,3p' | tr '\n' ' ')
[[ "$order" == *'microct-2d-segmentation/" class="workflow-card" href="workflows/scaffold-test/" class="workflow-card" href="workflows/microct-denoising/" class="workflow-card planned"'* ]] ||
    echo "fresh: the card isn't after the lab's Active card and before its Planned ones: $order"
for want in 'bin/check' 'run-proof' 'CONTRIBUTING.md' 'index.html' 'manifest.yml' 'commit'; do
    grep -qF "$want" "$scratch/fresh.out" || echo "fresh: what it prints as left to do doesn't name $want"
done

# A Planned workflow: its folder is extended, its card becomes Active in
# place, and its tier row moves, its title and lab read from its card.
clone planned
new planned microct-denoising "${owner[@]}" --owner-orcid 0000-0002-1825-0097
c="$scratch/planned"
expect fail "$c" "page template rules"
fill planned workflows/microct-denoising/index.html index.html workflows/microct-denoising/manifest.yml CONTRIBUTING.md
all pass planned "${placeholder_checks[@]}" "${other_checks[@]}"
[ "$(grep -c 'href="workflows/microct-denoising/"' "$c/index.html")" = 1 ] || echo "planned: not one card for microct-denoising"
grep -q '<h1 class="wf-title">microCT Denoising</h1>' "$c/workflows/microct-denoising/index.html" ||
    echo "planned: the page's title isn't its card's, microCT Denoising"
[ "$(cd "$c" && bin/manifest-owner workflows/microct-denoising/manifest.yml orcid)" = 0000-0002-1825-0097 ] ||
    echo "planned: the manifest has no owner ORCID"
grep '^| \*\*Planned' "$c/CONTRIBUTING.md" | grep -q 'microct-denoising' && echo "planned: still in the Planned row"
grep '^| \*\*Planned' "$c/CONTRIBUTING.md" | grep -qF '`microct-super-resolution`, `microct-reconstruction` (microCT), `mri-rat-brain-tumour-segmentation` (MRI) |' ||
    echo "planned: the Planned row lost more than microct-denoising: $(grep '^| \*\*Planned' "$c/CONTRIBUTING.md")"

# Refused, writing nothing: a taken slug, a malformed one, a lab with no
# lab table line, a lab that isn't a section, an owner bin/manifest-owner
# refuses, a missing owner field.
clone refused
c="$scratch/refused"
refuse() {
    local why="$1"
    shift
    (cd "$c" && bin/new-workflow "$@") > "$scratch/refused.out" 2>&1
    rc=$?
    [ "$rc" = 1 ] || [ "$rc" = 2 ] || { echo "refused: $why: exit $rc, expected a refusal"; sed 's/^/  /' "$scratch/refused.out"; }
    [ -s "$scratch/refused.out" ] || echo "refused: $why: no reason given"
    [ -z "$(git -C "$c" status --porcelain)" ] || { echo "refused: $why: wrote"; git -C "$c" status --porcelain | sed 's/^/  /'; git -C "$c" reset -q --hard; git -C "$c" clean -qfd; }
}
refuse "a live workflow" microct-2d-segmentation --title T --lab microct-lab "${owner[@]}"
refuse "onboarding" hello-world --title T --lab microct-lab "${owner[@]}"
refuse "a malformed slug" Bone_Seg --title T --lab microct-lab "${owner[@]}"
refuse "a lab with no lab table line" mri-seg --title T --lab bril "${owner[@]}"
refuse "no such lab" scaffold-test --title T --lab no-lab "${owner[@]}"
refuse "a bad owner email" scaffold-test --title T --lab microct-lab --owner-name "Jane Doe" --owner-github jdoe --owner-email "mailto:jdoe@example.org"
refuse "a login with an @" scaffold-test --title T --lab microct-lab --owner-name "Jane Doe" --owner-github @jdoe --owner-email jdoe@example.org
refuse "no owner email" scaffold-test --title T --lab microct-lab --owner-name "Jane Doe" --owner-github jdoe
refuse "no title" scaffold-test --lab microct-lab "${owner[@]}"
refuse "a title with markup" scaffold-test --title "Bone <b>Seg</b>" --lab microct-lab "${owner[@]}"
