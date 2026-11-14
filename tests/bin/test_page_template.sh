#!/bin/bash
# bin/check's page template rules against throwaway trees: a copy of
# bin/check and of templates/workflow-page.html in a scratch folder checks
# the workflow pages beside them. A page is the template with every
# placeholder filled, then broken in one way. Prints each failed case and
# nothing on success, so bin/check can run it.
#
#   tests/bin/test_page_template.sh
#
# bin/check name: page template test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

# The template with each {{NAME}} bin/new-workflow fills and each
# {{TODO: ...}} the author writes filled in.
filled() {
    sed -e 's/{{SLUG}}/seg/g; s/{{TITLE}}/Segmentation/g; s/{{LAB_ID}}/ct-lab/g; s/{{LAB_NAME}}/CT Lab/g' \
        -e 's/{{OWNER_LOGIN}}/jdoe/g; s/{{OWNER_NAME}}/Jane Doe/g; s/{{OWNER_EMAIL}}/j.doe@unsw.edu.au/g' \
        -e 's/{{TODO:[^}]*}}/Text the author wrote./g' templates/workflow-page.html
}

# A tree in $scratch/<name> holding bin/check, the template and a site
# with seg, a workflow with a form and the filled template as its page;
# hello-world, with a form and its own styles; and later, a Planned
# workflow with a page and no form.
make_tree() {
    local tree="$scratch/$1"
    site_tree "$tree" seg:ct-lab:active later:ct-lab:planned
    mkdir -p "$tree/templates" "$tree/workflows/hello-world"
    cp templates/workflow-page.html "$tree/templates/"
    touch "$tree/workflows/seg/form.yml.erb" "$tree/workflows/hello-world/form.yml.erb"
    filled > "$tree/workflows/seg/index.html"
    printf '%s\n' '<style>body { color: red; }</style>' '<h1 class="wf-title">Hello world</h1>' \
        > "$tree/workflows/hello-world/index.html"
}

# rules <pass|fail> <name>: the check over $scratch/<name>, which the
# caller has built and changed.
rules() {
    expect "$1" "$scratch/$2" "page template rules"
}

# edit <name> <file under the tree> <sed script>: make the tree, change one file.
edit() {
    make_tree "$1"
    sed -i "$3" "$scratch/$1/$2"
}

seg=workflows/seg/index.html

make_tree filled
rules pass filled

# Template sanity: it has every placeholder kind the rules catch, and
# filling them leaves none.
grep -q '{{TODO:' templates/workflow-page.html || echo "templates/workflow-page.html: no {{TODO: ...}} placeholder"
grep -q '{{SLUG}}' templates/workflow-page.html || echo "templates/workflow-page.html: no {{SLUG}} placeholder"
if filled | grep -n '{{'; then echo "test: filled() leaves a placeholder"; fi

make_tree todo-left
cp templates/workflow-page.html "$scratch/todo-left/$seg"
rules fail todo-left

edit slug-left "$seg" 's|OpenComposer/seg|OpenComposer/{{SLUG}}|'
rules fail slug-left

edit script "$seg" 's|</body>|<script>alert(1)</script></body>|'
rules fail script

edit script-uppercase "$seg" 's|</body>|<SCRIPT SRC="https://example.com/x.js"></SCRIPT></body>|'
rules fail script-uppercase

edit event-handler "$seg" 's|class="run-btn"|class="run-btn" onclick="steal()"|'
rules fail event-handler

edit javascript-url "$seg" 's|href="../../guide/#stage"|href="javascript:steal()"|'
rules fail javascript-url

edit iframe "$seg" 's|</body>|<iframe src="https://example.com/"></iframe></body>|'
rules fail iframe

edit style-element "$seg" 's|</head>|<style>body { color: red; }</style></head>|'
rules fail style-element

edit style-attribute "$seg" 's|<h1 class="wf-title">|<h1 class="wf-title" style="color: red">|'
rules fail style-attribute

edit outside-stylesheet "$seg" 's|</head>|<link rel="stylesheet" href="https://example.com/theme.css"></head>|'
rules fail outside-stylesheet

edit iris-sheet-elsewhere "$seg" 's|href="../../assets/iris.css"|href="../../assets/other.css"|'
rules fail iris-sheet-elsewhere

# Prose that mentions these words is not a script or a style.
edit prose-words "$seg" 's|</body>|<p>The script pane, its style and the word onward=on are prose.</p></body>|'
rules pass prose-words

edit no-data-section "$seg" 's| id="data"||'
rules fail no-data-section

edit no-cite-section "$seg" 's| id="cite"||'
rules fail no-cite-section

edit no-owner-section "$seg" 's| id="owner"||'
rules fail no-owner-section

edit no-review-line "$seg" '/class="wf-review"/d'
rules fail no-review-line

edit review-reworded "$seg" '/class="wf-review"/s/safety and fit/safety/'
rules fail review-reworded

edit hello-world-script workflows/hello-world/index.html 's|</h1>|</h1><script>x()</script>|'
rules fail hello-world-script

edit hello-world-placeholder workflows/hello-world/index.html 's|Hello world|{{TITLE}}|'
rules fail hello-world-placeholder

# A Planned workflow has no form, so no sections, but no script either.
edit planned-script workflows/later/index.html 's|</h1>|</h1><iframe src="x"></iframe>|'
rules fail planned-script

edit planned-placeholder workflows/later/index.html 's|</h1>|</h1><p>{{TODO: what it will do}}</p>|'
rules fail planned-placeholder

make_tree no-template
rm "$scratch/no-template/templates/workflow-page.html"
rules fail no-template

edit crlf "$seg" 's/$/\r/'
sed -i 's/$/\r/' "$scratch/crlf/templates/workflow-page.html"
rules pass crlf
