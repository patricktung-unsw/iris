#!/bin/bash
# IRIS's GitHub repo, the one every repo-scoped gh call in bin/ names, with
# -R or as repos/<repo>/ in gh api, rather than the repo of the current
# directory: a run from the fork's clone or worktree otherwise reaches
# unsw-restech/OpenComposer (#179's retro, #207). bin/issue-tick, bin/ciwait
# and bin/workflowhub source it; bin/review-batch, in Python, reads the line
# below. Sourcing it only sets the name.
# shellcheck disable=SC2034  # used by the scripts that source it
IRIS_GITHUB_REPO=unsw-restech/iris
