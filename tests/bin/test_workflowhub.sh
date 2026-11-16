#!/bin/bash
# bin/workflowhub against a fixture tree, with a fake browser opener,
# `curl` and `git` on PATH: the values it reads from a workflow's folder,
# the workflows it refuses, and whole walkthroughs answered on stdin,
# on the development instance and on WorkflowHub itself. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_workflowhub.sh
#
# bin/check name: workflowhub test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
tree="$fake/tree"
mkdir -p "$fake/bin" "$fake/home" "$tree/bin"
cp bin/workflowhub bin/manifest-owner "$tree/bin/"

# seg: a catalogue workflow with a form, an entry script, an owner and
# tags. later: a Planned workflow, a page and nothing else. hello-world:
# onboarding, with a form and a manifest.
mkdir -p "$tree/workflows/seg/src" "$tree/workflows/later" "$tree/workflows/hello-world"
touch "$tree/workflows/seg/form.yml.erb" "$tree/workflows/seg/src/run.py" \
    "$tree/workflows/hello-world/form.yml.erb"
cat > "$tree/workflows/seg/manifest.yml" <<'YAML'
name: Seg Thing (U-Net)
category: Imaging
icon: bi-layers
# Read by bin/workflowhub: the WorkflowHub entry's tags.
tags: microCT, segmentation, imaging
description: |
  Segment a volume.

  Pick a dataset folder holding `volume/`.

  Documentation: https://docs.restech.unsw.edu.au/iris/workflows/seg/
owner:
  name: Jane Doe
  github: jdoe
  email: jdoe@example.org  # the page links it
  orcid: "0000-0002-1825-0097"
YAML
printf '%s\n' 'name: IRIS Hello World' 'description: |' '  A test.' > "$tree/workflows/hello-world/manifest.yml"
cite_page() {  # cite_page [<li> line]: seg's page, listing that citable version
    printf '%s\n' '<h1 class="wf-title">Seg</h1>' '  <details id="cite">' '    <ul>' "$1" \
        '      <!-- <li><a href="https://doi.org/DOI" target="_blank">DOI</a> · YYYY-MM-DD · commit <code>SHORT-SHA</code></li> -->' \
        '    </ul>' '  </details>' > "$tree/workflows/seg/index.html"
}
cite_page ""
echo '<h1 class="wf-title">Later</h1>' > "$tree/workflows/later/index.html"

# The fakes: wslview logs each URL it is asked to open; git answers
# ls-remote with a fixed main; curl serves $fake/entry.json, failing like
# a 404 while there is none.
main_sha=1111111aaaaaaabbbbbbbcccccccdddddddeeeee
cat > "$fake/bin/wslview" <<'FAKE'
#!/bin/bash
echo "$1" >> "$(dirname "$0")/../opened"
FAKE
cat > "$fake/bin/git" <<FAKE
#!/bin/bash
[ "\$1" = ls-remote ] && printf '%s\trefs/heads/%s\n' $main_sha "\${3#refs/heads/}"
FAKE
cat > "$fake/bin/curl" <<'FAKE'
#!/bin/bash
json="$(dirname "$0")/../entry.json"
[ -f "$json" ] && cat "$json" && exit 0
echo "curl: (22) The requested URL returned error: 404" >&2
exit 22
FAKE
chmod +x "$fake/bin/"*

# run <answers> <arg>...: bin/workflowhub with the fakes, its answers kept
# in a fresh env file and fed <answers> on stdin; sets $out and $rc. The
# timeout stops a prompt that loops on end of input.
run() {
    local answers="$1"
    shift
    rm -f "$fake/opened" "$fake/wizard.env"
    out="$(printf '%b' "$answers" | HOME="$fake/home" IRIS_WIZARD_ENV="$fake/wizard.env" \
        PATH="$fake/bin:$PATH" timeout 20 "$tree/bin/workflowhub" "$@" 2>&1)"
    rc=$?
}
# has <case> <text>...: fail <case> unless the last run's output holds each text.
has() {
    local case="$1" t
    shift
    for t in "$@"; do
        grep -qF -- "$t" <<< "$out" || { echo "$case: output lacks '$t'"; echo "$out" | sed 's/^/  /'; return; }
    done
}
lacks() {
    local case="$1" t
    shift
    for t in "$@"; do
        ! grep -qF -- "$t" <<< "$out" || { echo "$case: output has '$t'"; echo "$out" | sed 's/^/  /'; return; }
    done
}
exits() { [ "$rc" = "$2" ] || { echo "$1: exit $rc, expected $2"; echo "$out" | sed 's/^/  /'; }; }
opened() { grep -qxF -- "$2" "$fake/opened" 2>/dev/null || echo "$1: never opened $2"; }

# The values come from seg's manifest and page.
run "" --values seg
exits values 0
has values "Title: UNSW HPC Katana - Seg Thing (U-Net)" "Tags: microCT, segmentation, imaging" \
    "Main workflow file: workflows/seg/src/run.py" "Creator: Jane Doe, ORCID 0000-0002-1825-0097" \
    "Segment a volume." "Pick a dataset folder holding \`volume/\`." \
    "Documentation: https://docs.restech.unsw.edu.au/iris/workflows/seg/" \
    "Entry: none yet, so it registers a new one" "Team: https://workflowhub.eu/projects/472"
[ "$(grep -c 'Documentation:' <<< "$out")" = 1 ] || echo "values: the page link is not given exactly once"

# A citable version on the page names the entry, so the next is a new version of it.
cite_page '      <li><a href="https://doi.org/10.48546/workflowhub.workflow.77.2" target="_blank">10.48546/workflowhub.workflow.77.2</a> · 2026-10-26 · commit <code>23e9314</code></li>'
run "" --values seg
has values-listed "Entry: https://workflowhub.eu/workflows/77 (from 10.48546/workflowhub.workflow.77.2 on the page), so it adds a new version"
# ...but not on the development instance, whose entries are its own.
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run "" --values seg
has values-dev "Entry: none yet, so it registers a new one" "Team: https://dev.workflowhub.eu/projects/9"
cite_page ""

# The workflows it refuses, and a manifest missing what it reads.
run "" --values hello-world
exits hello-world 2
has hello-world "hello-world is onboarding, not a catalogue workflow"
run "" --values later
exits planned 2
has planned "workflows/later has no form.yml.erb"
run "" --values gone
exits missing 2
run "" seg extra
exits usage 2
has usage "usage:"
cp "$tree/workflows/seg/manifest.yml" "$fake/manifest.yml"
sed -i '/^tags:/d' "$tree/workflows/seg/manifest.yml"
run "" --values seg
exits no-tags 2
has no-tags "workflows/seg/manifest.yml has no tags:"
cp "$fake/manifest.yml" "$tree/workflows/seg/manifest.yml"
# The owner is read by bin/manifest-owner, so an owner block it refuses is
# refused with its reason, and an unset ORCID is asked for.
sed -i '/^  email:/d' "$tree/workflows/seg/manifest.yml"
run "" --values seg
exits no-email 2
has no-email "owner has no email"
cp "$fake/manifest.yml" "$tree/workflows/seg/manifest.yml"
sed -i '/^owner:/,$d' "$tree/workflows/seg/manifest.yml"
run "" --values seg
exits no-owner 2
has no-owner "no owner block"
cp "$fake/manifest.yml" "$tree/workflows/seg/manifest.yml"
sed -i '/^  orcid:/d' "$tree/workflows/seg/manifest.yml"
run "" --values seg
exits no-orcid 0
has no-orcid "Creator: Jane Doe, ORCID asked for"
cp "$fake/manifest.yml" "$tree/workflows/seg/manifest.yml"
IRIS_WORKFLOWHUB=http://example.com run "" --values seg
exits bad-host 2
has bad-host "IRIS_WORKFLOWHUB"

# A first registration on the development instance: every stage up to
# Register, the clicks listed before the first, and no DOI.
dev_answers='\ny\n\n\ny\nhttps://dev.workflowhub.eu/workflows/12\ny\n\n'
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run "$dev_answers" seg
exits dev 0
opened dev https://dev.workflowhub.eu/projects/9
opened dev https://dev.workflowhub.eu/workflows/new
opened dev https://dev.workflowhub.eu/workflows/12
has dev "1. Register, which makes the version public and freezes it." "Stage 5/5 · Check the published entry" \
    "Import Git Repository" "right-click → Copy" "Done up to Register" "Press Enter to finish." \
    "main is at $main_sha" "UNSW HPC Katana - Seg Thing (U-Net)" "microCT, segmentation, imaging" \
    "1. Jane Doe, ORCID 0000-0002-1825-0097" "DOIs mint only on https://workflowhub.eu"
lacks dev "Stage 6" "workflowhub.eu/projects/472" "Generate a DOI"
grep -qx "WH_ENTRY_URL='https://dev.workflowhub.eu/workflows/12'" "$fake/wizard.env" ||
    echo "dev: the entry URL was not kept"
# Published, the entry is read back, there as before a DOI: with no API
# to read, it says to check by eye; a different commit is warned of.
has dev "What the published entry says:" "couldn't read the entry's commit from WorkflowHub"
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"'$main_sha'"}]}}}' > "$fake/entry.json"
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run "$dev_answers" seg
exits dev-read-back 0
has dev-read-back "✓ title: UNSW HPC Katana - Seg Thing (U-Net)" "✓ licence: Apache-2.0" "✓ commit: $main_sha"
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"2222222"}]}}}' > "$fake/entry.json"
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run "$dev_answers" seg
exits dev-other-commit 0
has dev-other-commit "the entry's commit is \"2222222\", not \"$main_sha\"" "a version's commit can't be edited" \
    "but the entry differs from what this walkthrough expected"
lacks dev-other-commit "Done up to Register" "fix it with Actions → Edit Workflow"
rm -f "$fake/entry.json"
# An entry URL on the wrong host is asked for again.
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 \
    run '\ny\n\n\ny\nhttps://workflowhub.eu/workflows/12\nhttps://dev.workflowhub.eu/workflows/12\ny\n\n' seg
exits dev-wrong-host 0
has dev-wrong-host "expected https://dev.workflowhub.eu/workflows/<number>"

# Declining a gate stops there, with nothing after it done: not yet in
# the team, it says how to join; not ready to publish, it stops before
# Register.
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run '\ny\n\n\nn\n' seg
exits decline-register 0
has decline-register "Stopped before Register."
lacks decline-register "Paste the new entry's URL" "DOIs mint only"
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run '\nn\n' seg
exits not-in-team 0
has not-in-team "Request Membership on https://dev.workflowhub.eu/projects/9, and re-run once you're listed."
lacks not-in-team "Stage 2/5"

# A different title on WorkflowHub is fixed by editing, even frozen; the
# licence is still checked.
printf '%s' '{"data":{"attributes":{"title":"IRIS","license":"Apache-2.0","versions":[{"version":1,"commit":"'$main_sha'","doi":"10.48546/workflowhub.workflow.12.1"}]}}}' > "$fake/entry.json"
run '\ny\n\n\ny\nhttps://workflowhub.eu/workflows/12\ny\n\ny\n\n' seg
exits prod-other-title 0
has prod-other-title "the entry's title is \"IRIS\"" "✓ licence: Apache-2.0" "fix it with Actions → Edit Workflow before the DOI"
lacks prod-other-title "a version's commit can't be edited"
rm -f "$fake/entry.json"

# A new version on the development instance: its entry from
# IRIS_WORKFLOWHUB_ENTRY, published by Update, read back, and no DOI.
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"2222222"},{"version":2,"commit":"'$main_sha'"}]}}}' > "$fake/entry.json"
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 IRIS_WORKFLOWHUB_ENTRY=https://dev.workflowhub.eu/workflows/12 \
    run '\ny\n\n\ny\n\ny\n\n' seg
exits dev-new-version 0
opened dev-new-version https://dev.workflowhub.eu/workflows/12
has dev-new-version "Stage 2/5 · Add a new version from git" "Actions → New Version." \
    "✓ commit: $main_sha" "Done up to Update on https://dev.workflowhub.eu"
lacks dev-new-version "Paste the new entry's URL" "Generate a DOI"
rm -f "$fake/entry.json"

# A version Register didn't freeze: a warning on the development
# instance, and no DOI on WorkflowHub.
IRIS_WORKFLOWHUB=https://dev.workflowhub.eu IRIS_WORKFLOWHUB_TEAM=9 run '\ny\n\n\ny\nhttps://dev.workflowhub.eu/workflows/12\nn\n\n' seg
exits dev-not-frozen 0
has dev-not-frozen "not frozen on Register" "DOIs mint only"
run '\ny\n\n\ny\nhttps://workflowhub.eu/workflows/12\nn\n' seg
exits prod-not-frozen 0
has prod-not-frozen "Stopped before the DOI: a DOI points at a frozen version."
lacks prod-not-frozen "Stage 6/7"

# A first registration on WorkflowHub: the DOI read back, then the lines
# that list the citable version on the page and in CITATION.cff.
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"'$main_sha'","doi":"10.48546/workflowhub.workflow.12.1"}]}}}' > "$fake/entry.json"
run '\ny\n\n\ny\nhttps://workflowhub.eu/workflows/12\ny\n\ny\n\n' seg
exits prod 0
opened prod https://workflowhub.eu/projects/472
opened prod https://doi.org/10.48546/workflowhub.workflow.12.1
has prod "2. Generate a DOI, which is permanent." "Stage 7/7 · List the citable version" "✓ title: UNSW HPC Katana - Seg Thing (U-Net)" "✓ commit: $main_sha" \
    "<li><a href=\"https://doi.org/10.48546/workflowhub.workflow.12.1\" target=\"_blank\">10.48546/workflowhub.workflow.12.1</a> · $(date +%F) · commit <code>1111111</code></li>" \
    "    value: 10.48546/workflowhub.workflow.12.1" \
    "    description: \"seg's citable version of $(date +%F), commit 1111111\""

# A different commit on WorkflowHub is warned of before the DOI, which
# still goes ahead on a yes.
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"2222222","doi":"10.48546/workflowhub.workflow.12.1"}]}}}' > "$fake/entry.json"
run '\ny\n\n\ny\nhttps://workflowhub.eu/workflows/12\ny\n\ny\n\n' seg
exits prod-other-commit 0
has prod-other-commit "the entry's commit is \"2222222\", not \"$main_sha\"" \
    "a version's commit can't be edited" "Stage 7/7 · List the citable version"
lacks prod-other-commit "fix it with Actions → Edit Workflow"

# A later citable version: the page names the entry, so it is not asked
# for, and the walkthrough adds a new version to it.
cite_page '      <li><a href="https://doi.org/10.48546/workflowhub.workflow.12.1" target="_blank">10.48546/workflowhub.workflow.12.1</a> · 2026-10-26 · commit <code>23e9314</code></li>'
printf '%s' '{"data":{"attributes":{"title":"UNSW HPC Katana - Seg Thing (U-Net)","license":"Apache-2.0","versions":[{"version":1,"commit":"23e9314","doi":"10.48546/workflowhub.workflow.12.1"},{"version":2,"commit":"'$main_sha'","doi":"10.48546/workflowhub.workflow.12.2"}]}}}' > "$fake/entry.json"
run '\ny\n\n\ny\n\ny\n\ny\n\n' seg
exits new-version 0
opened new-version https://workflowhub.eu/workflows/12
has new-version "Add a new version from git" "Actions → New Version." "Click Update, then OK on the sharing preview." \
    "1. Update, which makes the version public and freezes it." "Tags and creators come filled in" "10.48546/workflowhub.workflow.12.2</a> · $(date +%F)"
lacks new-version "expected https://workflowhub.eu/workflows/<number>" "Main workflow file"
cite_page ""
rm -f "$fake/entry.json"
