# Sourced from the repo root by the fixture tests of bin/check's site
# checks, which build scratch trees each holding a copy of bin/check, which
# checks the tree it sits in, and by every test that gives a scratch copy of
# lib/katana.sh a digest map of its own.

# digest_map <file> [--tools <env>/<n>] [<env>/<n>=<value>]...: replaces the
# whole digest map (IRIS_ENV_DIGESTS) in <file>, a scratch copy of
# lib/katana.sh, with one "    [<env>/<n>]=<value>" line per entry, in the
# order given, and with --tools sets IRIS_TOOLS_ENV_VERSION to <env>/<n>.
# It leaves the rest of the file alone. If the map, its closing ")" or,
# with --tools, the tools version line isn't there, or the file doesn't
# end up holding exactly what was asked, it prints why, naming <file>, and
# returns 1, so no fixture keeps the real map's versions by mistake.
# The digest map's opening line in lib/katana.sh, which the helpers below
# match whole. Its characters are literal in a sed basic regex, which
# _digest_map_lines reads it as.
_DIGEST_MAP_OPEN='declare -gA IRIS_ENV_DIGESTS=('

digest_map() {
    local file="$1" tools="" e lines=""
    shift
    if [ "${1-}" = --tools ]; then tools="$2"; shift 2; fi
    for e in "$@"; do lines+="    [${e%%=*}]=${e#*=}"$'\n'; done
    _digest_map_open digest_map "$file" || return 1
    if [ -n "$tools" ] && ! grep -q '^IRIS_TOOLS_ENV_VERSION=' "$file"; then
        echo "digest_map: $file has no IRIS_TOOLS_ENV_VERSION= line to set"
        return 1
    fi
    OPEN_="$_DIGEST_MAP_OPEN" LINES_="$lines" TOOLS_="$tools" awk '
        in_map { if ($0 == ")") { in_map = 0; printf "%s", ENVIRON["LINES_"]; print }; next }
        $0 == ENVIRON["OPEN_"] { print; in_map = 1; next }
        ENVIRON["TOOLS_"] != "" && /^IRIS_TOOLS_ENV_VERSION=/ { print "IRIS_TOOLS_ENV_VERSION=" ENVIRON["TOOLS_"]; next }
        { print }' "$file" > "$file.digest-map" && mv "$file.digest-map" "$file" || return 1
    if [ "$(_digest_map_lines "$file")" != "${lines%$'\n'}" ]; then
        echo "digest_map: $file's digest map isn't the entries given: $*"
        return 1
    fi
    if [ -n "$tools" ] && ! grep -qxF "IRIS_TOOLS_ENV_VERSION=$tools" "$file"; then
        echo "digest_map: $file's tools version isn't $tools"
        return 1
    fi
}

# digest_map_add <file> <env>/<n>=<value>: adds "    [<env>/<n>]=<value>"
# as the first line of <file>'s digest map, keeping the rest, and fails as
# digest_map does, naming <file>, if the map isn't there or the line
# didn't go in.
digest_map_add() {
    local file="$1" line="    [${2%%=*}]=${2#*=}"
    _digest_map_open digest_map_add "$file" || return 1
    OPEN_="$_DIGEST_MAP_OPEN" LINE_="$line" awk '{ print } $0 == ENVIRON["OPEN_"] { print ENVIRON["LINE_"] }' \
        "$file" > "$file.digest-map" && mv "$file.digest-map" "$file" || return 1
    # A here-string, not a pipe: grep -q stops at its first match, and a
    # writer still holding output would then meet a closed pipe (#239).
    if ! grep -qxF -- "$line" <<< "$(_digest_map_lines "$file")"; then
        echo "digest_map_add: $file's digest map didn't take $2"
        return 1
    fi
}

# _digest_map_open <caller> <file>: fails, naming <caller> and <file>,
# unless <file> has the map's opening line and a ")" line after it.
_digest_map_open() {
    if ! grep -qxF "$_DIGEST_MAP_OPEN" "$2"; then
        echo "$1: $2 has no '$_DIGEST_MAP_OPEN' line to replace"
        return 1
    fi
    # One reader of the file itself, so no writer is left holding output
    # when the match is found (#239).
    if ! OPEN_="$_DIGEST_MAP_OPEN" awk '
        in_map && $0 == ")" { found = 1; exit }
        $0 == ENVIRON["OPEN_"] { in_map = 1 }
        END { exit !found }' "$2"; then
        echo "$1: $2's digest map has no closing ) line"
        return 1
    fi
}

# _digest_map_lines <file>: the lines inside <file>'s digest map.
_digest_map_lines() {
    sed -n "/^$_DIGEST_MAP_OPEN\$/,/^)\$/p" "$1" | sed '1d;$d'
}

# expect <pass|fail> <tree> <check name>: runs <tree>/bin/check on the
# checks whose name holds <check name>, and prints the tree's name and the
# output if the verdict isn't the one wanted. A failure must be that
# check's own, and named again on the run's last line, FAILED: <names>.
expect() {
    local want="$1" tree="$2" name="$3" out rc
    out="$("$tree/bin/check" "$name" 2>&1)"
    rc=$?
    if [ "$want" = pass ] && [ "$rc" != 0 ]; then
        echo "${tree##*/}: failed, expected a pass"
    elif [ "$want" = fail ] && { [ "$rc" != 1 ] || ! grep -qF -- "$name" <<< "$(grep '^FAIL: ' <<< "$out")"; }; then
        echo "${tree##*/}: passed (exit $rc), expected a failure"
    elif [ "$want" = fail ] && ! grep -qF -- "$name" <<< "$(tail -n1 <<< "$out" | grep '^FAILED: ')"; then
        echo "${tree##*/}: its last line doesn't name the failed check: $(tail -n1 <<< "$out")"
    else
        return 0
    fi
    echo "$out" | sed 's/^/  /'
}

# site_tree <tree> [<slug>:<lab>:<tier>]...: a site in <tree> that passes
# bin/check's site rules, as a git repo with every file added, holding a
# copy of bin/check, the Avoid-word list it reads (.githooks/avoid-names) and
#   - index.html: a lab tile per lab, linking #<lab> and counting its
#     active and planned workflows, then a lab section (id="<lab>") per lab,
#     in the order given, holding a card per workflow whose status label
#     follows its tier; an unmaintained workflow has no card
#   - workflows/<slug>/index.html per workflow, its breadcrumb linking its
#     lab, with the unmaintained-banner if it is unmaintained
#   - guide/ and contribute/ pages; every page has the same logo
#   - CONTRIBUTING.md: a tier table row per tier given, and a line citing
#     a job for each active workflow
#   - README.md: a repo map naming bin/ and, with a workflow,
#     workflows/<workflow>/
# <tier> is active (Run and verified), planned or unmaintained. A test then breaks the part its rule
# reads; a rule that reads git's index needs git -C <tree> add -A after.
site_tree() {
    local tree="$1" spec slug lab tier t list planned active labs=()
    shift
    local -A title=([active]="Run and verified" [planned]=Planned [unmaintained]=Unmaintained)
    local -A status=([active]=Active [planned]=Planned)
    mkdir -p "$tree/bin" "$tree/guide" "$tree/contribute" "$tree/.githooks"
    cp bin/check "$tree/bin/check"
    cp .githooks/avoid-names .githooks/avoid-names.pl "$tree/.githooks/"
    for spec in "$@"; do
        IFS=: read -r slug lab tier <<< "$spec"
        [[ " ${labs[*]} " == *" $lab "* ]] || labs+=("$lab")
        mkdir -p "$tree/workflows/$slug"
        {
            echo '<nav><a href="../../"><span class="nav-logo-text">UNSW IRIS</span></a></nav>'
            echo "<div class=\"breadcrumb\"><a href=\"../../\">IRIS</a> / <a href=\"../../#$lab\">$lab</a> / $slug</div>"
            [ "$tier" != unmaintained ] ||
                echo '<div class="unmaintained-banner"><strong>Unmaintained.</strong> This workflow cannot be run.</div>'
            echo "<h1 class=\"wf-title\">$slug</h1>"
        } > "$tree/workflows/$slug/index.html"
    done
    {
        echo '<nav><a href="./"><span class="nav-logo-text">UNSW IRIS</span></a></nav>'
        echo '<section id="workflows">'
        echo '  <div class="lab-tiles">'
        for t in "${labs[@]}"; do
            active=0; planned=0
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$lab" = "$t" ] || continue
                [ "$tier" != active ] || active=$((active + 1))
                [ "$tier" != planned ] || planned=$((planned + 1))
            done
            echo "    <a href=\"#$t\" class=\"lab-tile\">"
            echo "      <span class=\"lab-tile-name\">$t</span>"
            echo "      <span class=\"lab-tile-counts\">$active active · $planned planned</span>"
            echo '    </a>'
        done
        echo '  </div>'
        for t in "${labs[@]}"; do
            echo "  <div class=\"lab\" id=\"$t\">"
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$lab" = "$t" ] && [ "$tier" != unmaintained ] || continue
                planned=""; [ "$tier" != planned ] || planned=" planned"
                echo "    <a href=\"workflows/$slug/\" class=\"workflow-card$planned\">"
                echo "      <div class=\"card-name\">$slug</div>"
                echo "      <span><span class=\"status-dot$planned\"></span> ${status[$tier]}</span>"
                echo '    </a>'
            done
            echo '  </div>'
        done
        echo '</section>'
    } > "$tree/index.html"
    for t in guide contribute; do
        printf '%s\n' '<nav><a href="../"><span class="nav-logo-text">UNSW IRIS</span></a></nav>' "<h1>$t</h1>" \
            > "$tree/$t/index.html"
    done
    {
        printf '%s\n' '| Tier | Workflows | What exists |' '|---|---|---|'
        for t in active planned unmaintained; do
            list=""
            for spec in "$@"; do
                IFS=: read -r slug lab tier <<< "$spec"
                [ "$tier" != "$t" ] || list+="${list:+, }\`$slug\`"
            done
            [ -z "$list" ] || echo "| **${title[$t]}** | $list | Page |"
        done
        echo
        for spec in "$@"; do
            IFS=: read -r slug lab tier <<< "$spec"
            [ "$tier" != active ] || echo "\`$slug\` ran from the system OnDemand (job 1001)."
        done
    } > "$tree/CONTRIBUTING.md"
    {
        printf '%s\n' '# IRIS' '' '| Path | What it holds |' '|---|---|' '| `bin/` | Tools |'
        [ $# = 0 ] || echo '| `workflows/<workflow>/` | A workflow |'
    } > "$tree/README.md"
    git init -q "$tree"
    git -C "$tree" add -A
}
