#!/bin/bash
# bin/check's lab-tile check against throwaway site trees. Each tree gets
# its own copy of bin/check, which checks the tree it sits in. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_lab_tiles.sh
#
# bin/check name: lab tile test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="lab tiles count their lab sections"
stray='    <a href="#nowhere" class="lab-tile"><span class="lab-tile-counts">0 active · 0 planned</span></a>'
again='    <a href="#ct-lab" class="lab-tile"><span class="lab-tile-counts">1 active · 1 planned</span></a>'
# Moves the ct-lab tile to the end of the lab tiles, after mr-lab's.
swap='/href="#ct-lab" class="lab-tile"/,/<\/a>/{H;d};0,/^  <\/div>$/{/^  <\/div>$/{x;s/^\n//;G}}'

# tiles <pass|fail> <name> [<says> <sed script> [<never>]]: the check over
# a site with two labs, ct-lab holding seg (active) and denoise (planned)
# and mr-lab holding tumour (planned), with the sed script applied to
# index.html; a failure must print <says>, and never <never>.
tiles() {
    local want="$1" tree="$scratch/$2" out
    site_tree "$tree" seg:ct-lab:active denoise:ct-lab:planned tumour:mr-lab:planned
    [ $# -lt 4 ] || sed -i "$4" "$tree/index.html"
    out="$(expect "$want" "$tree" "$name")"
    [ -z "$out" ] || { echo "$out"; return; }
    [ "$want" = fail ] || return 0
    out="$("$tree/bin/check" "$name" 2>&1)"
    grep -qF -- "$3" <<< "$out" || { echo "$2: doesn't say \"$3\""; echo "$out" | sed 's/^/  /'; }
    [ -z "$5" ] || ! grep -qF -- "$5" <<< "$out" || { echo "$2: says \"$5\""; echo "$out" | sed 's/^/  /'; }
}

tiles pass agree
tiles fail active "index.html: the ct-lab tile says 2 active; its section has 1" 's/1 active · 1 planned/2 active · 1 planned/'
tiles fail planned "index.html: the mr-lab tile says 3 planned; its section has 1" 's/0 active · 1 planned/0 active · 3 planned/'
tiles fail no-tile "index.html: lab section mr-lab has no lab tile" '/href="#mr-lab" class="lab-tile"/,/<\/a>/d' "order"
tiles fail stray "index.html: a lab tile links #nowhere, which no lab section has" "/<div class=\"lab-tiles\">/a\\$stray" "order"
tiles fail order "index.html: the lab tiles' order (mr-lab ct-lab) differs from the lab sections' (ct-lab mr-lab)" "$swap"
tiles fail duplicate "index.html: two lab tiles link #ct-lab" "/href=\"#mr-lab\" class=\"lab-tile\"/i\\$again" "order"
tiles fail duplicate-last "index.html: two lab tiles link #ct-lab" "0,/^  <\\/div>\$/{/^  <\\/div>\$/i\\$again
}" "order"
tiles fail no-counts "index.html: the ct-lab tile has no \"N active · M planned\" counts" '0,/class="lab-tile-counts"/{/class="lab-tile-counts"/d}'

site_tree "$scratch/crlf" seg:ct-lab:active denoise:ct-lab:planned
sed -i 's/$/\r/' "$scratch/crlf/index.html"
expect pass "$scratch/crlf" "$name"
