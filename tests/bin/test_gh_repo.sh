#!/bin/bash
# bin/check's "gh calls name their repo" check against throwaway trees,
# each with its own copy of bin/check and one script: a repo-scoped gh
# call, shell or Python, passes only with -R or --repo on its line, and a
# gh api call only without gh's {owner}/{repo} placeholders. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_gh_repo.sh
#
# bin/check name: gh repo test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
. tests/bin/lib.sh

name="gh calls name their repo"

# case_ <pass|fail> <case> <file> <line>: a tree whose <file> holds <line>,
# beside its copy of bin/check, which names gh calls and so passes only
# because the check leaves it out.
case_() {
    local want="$1" tree="$scratch/$2" file="$3" line="$4"
    mkdir -p "$tree/bin" "$(dirname "$tree/$file")"
    cp bin/check "$tree/bin/check"
    printf '%s\n' "$line" > "$tree/$file"
    git init -q "$tree"
    git -C "$tree" add -A
    expect "$want" "$tree" "$name"
}

case_ pass shell-R bin/tool 'gh pr list -R "$repo" --label ready'
case_ pass shell-repo lib/tool.sh 'id="$(gh run list --repo unsw-restech/iris --limit 20)"'
case_ pass shell-repo-eq bin/tool 'gh issue view 1 --repo=unsw-restech/iris'
case_ pass python-R bin/tool 'run(["gh", "pr", "view", str(n), "-R", github_repo()])'
case_ pass python-single-R bin/tool "run(['gh', 'pr', 'list', '-R', repo])"
case_ pass api-path bin/tool 'gh api -X PATCH "repos/$repo/issues/comments/1"'
case_ pass api-user bin/tool 'gh api user --jq .login'
case_ pass auth bin/tool 'gh auth status > /dev/null'
case_ pass comment bin/tool '# gh run list has no --commit on gh 2.4.0'
case_ pass prose bin/tool 'die "gh couldn'"'"'t list the ready pull requests"'
case_ pass markdown bin/notes.md 'gh issue view 1'
case_ pass markdown-lib lib/notes.md 'gh issue view 1'
case_ pass crlf bin/tool $'gh secret set X -R "$repo"\r'

case_ fail shell-bare bin/tool 'gh run watch "$id" --exit-status'
case_ fail shell-lib lib/tool.sh 'gh issue edit 1 --body-file -'
case_ fail hook .githooks/pre-push 'gh pr view 1 --json state'
case_ fail piped bin/tool 'printf x | gh secret set NAME'
case_ fail python-bare bin/tool 'run(["gh", "pr", "list", "--label", "ready"])'
case_ fail api-placeholder bin/tool 'gh api repos/{owner}/{repo}/pulls'
case_ fail python-api-placeholder bin/tool 'run(["gh", "api", "repos/{owner}/{repo}/pulls"])'
case_ fail flag-in-word bin/tool 'gh pr list --label -Rx'
case_ fail python-single bin/tool "run(['gh', 'pr', 'list', '--label', 'ready'])"
case_ fail api-branch bin/tool 'gh api repos/unsw-restech/iris/branches/{branch}'
# -R must be on the call's first line, so a call wrapped before it fails.
case_ fail wrapped bin/tool $'gh run list \\\n    -R "$repo" --limit 20'
