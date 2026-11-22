# Deploying to Katana

The deploys beyond a push to `main`: the system clone on its own, the fork's two checkouts, and a review batch. `AGENTS.md`'s **Deploying** keeps what every push needs, including the system clone's go-ahead inside a push request.

## System clone

`/srv/scratch/katana_ai/iris/code/`, beside `envs/` and `wheelhouse/`. It lives there because researchers can't read the dev clone's home folder (IRIS maintainer, 2026-10-23). The IRIS instance, Katana OnDemand's `OpenComposer` app, serves its `workflows/`, and every Run button opens `https://kod.restech.unsw.edu.au/pun/sys/OpenComposer/<slug>` (ADR-0012). Any git change there (pull, reset, checkout) deploys to the pilot, so it is the OpenComposer deploy.

To deploy it apart from a push:

1. Run `bin/syspull` to list what a pull would deploy.
2. Get the IRIS maintainer's go-ahead, naming that path and quoting verbatim every commit it lists.
3. Run the `bin/syspull --apply <sha>` line it prints.

## Fork checkouts

The IRIS instance and the test instance each have a checkout of the fork, `OpenComposer-iris` and `OpenComposer-iris-test`, beside the system clone (`lib/katana.sh`). Each runs one pinned fork commit, detached, and keeps its own `manifest.yml` with `skip-worktree` (#170).

- Katana OnDemand's `OpenComposer` system app serves the first, as the sysadmin set it up, though its folder keeps the `-iris` name.
- The second is a dev app that each workflow author links into their own `~/ondemand/dev` (ADR-0012).

Moving them deploys OpenComposer itself to both instances, so they move together, forward along the fork's `main`:

1. Run `bin/ocpull` to list what a move would deploy to each. If it warns that `lib/tests/form_helper.rb` renders as another commit, run `bin/helper-compare <sha>` on its `--apply` line's commit, bring the helper and its header's commit to that commit until it passes, and commit that before the move.
2. Get the IRIS maintainer's go-ahead, naming both paths and quoting verbatim every commit it lists.
3. Run the `bin/ocpull --apply <sha>` line it prints.

`--apply` moves neither checkout unless both can move. When a move changes a file a checkout keeps its own copy of, it refuses and prints the steps to take the change by hand, for every checkout at once.

It never moves the IRIS maintainer's dev install, `~/ondemand/dev/OpenComposer` (#159, #162):

- When the listing shows the dev install behind, name it in the go-ahead request too. Once `--apply` has deployed, run the line it ends with, which moves the install to the same commit.
- When the listing shows it anywhere else, ahead or off the fork's `main`, take it to the IRIS maintainer (#179's retro).

## Review batch

1. `bin/review-batch` lists every `ready` PR. Show the IRIS maintainer its listing and its `--apply` line.
2. Their yes to that line is the go-ahead for `--apply` and for each step it then prints, the copies, push and dev pull included. Run each as its own command.
3. The system clone gets its own go-ahead, from the `bin/syspull` it prints last.

CONTRIBUTING's Review batch has the steps.
