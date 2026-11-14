#!/bin/bash
# bin/run-proof <run dir> against a throwaway clone, run directory, test
# instance job history and stand-in ruby: a finished test-instance run
# whose code is the clone's writes the run proof, which the proof check
# then passes; a run it can't prove, from another instance, unfinished,
# edited, in another environment version or on code the clone has moved
# on from, or whose form tests fail or skip, writes nothing. Prints each
# failed case and nothing on success, so bin/check can run it.
#
#   tests/bin/test_run_proof.sh
#
# bin/check name: run proof test

cd "$(dirname "$(readlink -f "$0")")/../.." || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
digest="sha256:$(printf 'b%.0s' {1..64})"

commit() {
    git -C "$1" add -A
    git -C "$1" -c user.name=t -c user.email=t@example.org commit -q -m "${2:-change}"
}

# history <home> <job ID>:<slug>...: the test instance's job history in
# <home>, as OpenComposer's pbspro.sqlite3 holds it.
history() {
    local home="$1"
    shift
    mkdir -p "$home/composer/iris-test"
    python3 - "$home/composer/iris-test/pbspro.sqlite3" "$@" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE jobs (_job_id TEXT PRIMARY KEY, _app_name TEXT, _app_dir_name TEXT, _status TEXT, payload_json TEXT NOT NULL DEFAULT '{}')")
for job in sys.argv[2:]:
    job_id, slug = job.split(":")
    db.execute("INSERT INTO jobs (_job_id, _app_name, _app_dir_name, _status) VALUES (?, ?, ?, 'COMPLETED')", (job_id, slug, slug))
db.commit()
EOF
}

# make_case <name>: in $scratch/<name>, a clone at clone/ whose seg
# workflow pins ct/1 and has form tests, committed; the test instance's
# checkout, its data_dir in home/, whose history holds job 9000001 of seg;
# and that job's run directory, data/runs/9000001, a finished, unedited
# run at the clone's HEAD in ct/1, with its job output saying exit status
# 0. A stand-in ruby on bin/'s PATH prints passing minitest totals.
make_case() {
    local c="$scratch/$1" r
    r="$c/clone"
    mkdir -p "$r/bin" "$r/lib" "$r/workflows/seg/lib" "$r/workflows/seg/tests" "$r/workflows/seg/src" \
        "$c/checkout" "$c/home" "$c/data/runs/9000001" "$c/path"
    cp bin/run-proof "$r/bin/run-proof"
    echo "IRIS_TEST_INSTANCE_CHECKOUT=$c/checkout" > "$r/lib/katana.sh"
    printf '%s\n' 'script: |' '  IRIS_ENV_VERSION=ct/1' > "$r/workflows/seg/form.yml.erb"
    echo "0123456789abcdef0123456789abcdef01234567" > "$r/workflows/seg/lib/copied-from"
    echo "print(1)" > "$r/workflows/seg/src/run.py"
    echo "# form tests" > "$r/workflows/seg/tests/test_form.rb"
    git init -q -b main "$r"
    commit "$r" main
    git -C "$r" update-ref refs/remotes/origin/main main
    printf '%s\n' '---' 'apps_dir: "<%= ENV['"'HOME'"'] %>/iris/workflows"' \
        'data_dir: "<%= ENV['"'HOME'"'] %>/composer/iris-test"' > "$c/checkout/conf.yml.erb"
    history "$c/home" 9000001:seg
    run_json "$1" "$(git -C "$r" rev-parse HEAD)" ct/1 FINISHED false
    printf '%s\n' "Job Id: 9000001" "Job execution was successful. Exit Status 0. " \
        > "$c/data/runs/9000001.kman.restech.unsw.edu.au.OU"
    cat > "$c/path/ruby" <<'EOF'
#!/bin/bash
echo "Run options: --seed 1"
echo "${RUBY_TOTALS:-3 runs, 5 assertions, 0 failures, 0 errors, 0 skips}"
exit "${RUBY_EXIT:-0}"
EOF
    chmod +x "$c/path/ruby"
}

# run_json <name> <commit> <version> <status> <edited>: the run record.
run_json() {
    cat > "$scratch/$1/data/runs/9000001/run.json" <<EOF
{
  "format": 2,
  "run": {"experiment": "seg", "workflow": "seg", "dir": "$scratch/$1/data/runs/9000001",
          "status": "$4", "start_time": 1.0, "end_time": 2.0},
  "job": {"id": "9000001", "queue": "general"},
  "code": {"commit": "$2", "edited": $5},
  "environment": {"version": "$3", "digest": "$digest"},
  "extras": {}
}
EOF
}

# prove <name> [<env>=<value>...]: runs the tool on the case's run
# directory as its author, from the clone; prints its output.
prove() {
    local c="$scratch/$1"
    shift
    env HOME="$c/home" PATH="$c/path:$PATH" "$@" "$c/clone/bin/run-proof" "$c/data/runs/9000001" 2>&1
}

# refused <name> <what> [<env>=<value>...]: the tool must exit 1, say why
# (matching <what>) and write no proof.
refused() {
    local name="$1" what="$2" out rc
    shift 2
    out="$(prove "$name" "$@")"
    rc=$?
    [ "$rc" = 1 ] || echo "$name: exit $rc, expected 1"
    grep -qiE -- "$what" <<< "$out" || echo "$name: the refusal doesn't say '$what': $out"
    [ ! -e "$scratch/$name/clone/workflows/seg/run-proof.json" ] || echo "$name: wrote a run proof"
}

# A finished test-instance run writes the proof, from the run record, the
# job output and the form tests, and the proof check passes it.
make_case good
out="$(prove good)" || echo "good: refused: $out"
proof="$scratch/good/clone/workflows/seg/run-proof.json"
head="$(git -C "$scratch/good/clone" rev-parse HEAD)"
python3 - "$proof" "$head" "$digest" <<'EOF' || echo "good: the proof is not what the run shows"
import json, re, sys
p = json.load(open(sys.argv[1]))
want = {"format": 1, "workflow": "seg", "commit": sys.argv[2],
        "job": {"id": "9000001", "exit_status": 0},
        "environment": {"version": "ct/1", "digest": sys.argv[3]},
        "form_tests": {"test": "tests/test_form.rb",
                       "result": "3 runs, 5 assertions, 0 failures, 0 errors, 0 skips"}}
written = p.pop("written", "")
assert p == want, p
assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", written), written
EOF
grep -qF "workflows/seg/run-proof.json" <<< "$out" || echo "good: it doesn't name the proof to commit: $out"
commit "$scratch/good/clone" "seg's run proof"
out="$("$scratch/good/clone/bin/run-proof" --check origin/main 2>&1)" || echo "good: the proof check failed it: $out"
git -C "$scratch/good/clone" diff --quiet HEAD~1 HEAD -- workflows/seg/src || echo "good: the proof commit changed seg's code"

# Proving again over a committed proof is fine: the proof isn't the code.
out="$(prove good)" || echo "good: refused to prove again over its own proof: $out"

# Only the test instance's runs: a job its history lacks, as one submitted
# from the IRIS instance or a dev install, or no history at all.
make_case other-instance
rm "$scratch/other-instance/home/composer/iris-test/pbspro.sqlite3"
history "$scratch/other-instance/home" 9000002:seg
refused other-instance "test instance"
make_case other-workflow
rm "$scratch/other-workflow/home/composer/iris-test/pbspro.sqlite3"
history "$scratch/other-workflow/home" 9000001:hello
refused other-workflow "test instance"
make_case no-history
rm -r "$scratch/no-history/home/composer"
refused no-history "test instance"

# The run must have finished, with exit status 0, from the code as
# committed, in the version its form pins.
make_case failed
run_json failed "$(git -C "$scratch/failed/clone" rev-parse HEAD)" ct/1 FAILED false
refused failed FAILED
make_case nonzero
sed -i 's/Exit Status 0/Exit Status 1/' "$scratch/nonzero/data/runs/9000001.kman.restech.unsw.edu.au.OU"
refused nonzero "exit status 1"
make_case no-output
rm "$scratch/no-output/data/runs/9000001.kman.restech.unsw.edu.au.OU"
refused no-output "job output"
make_case edited
run_json edited "$(git -C "$scratch/edited/clone" rev-parse HEAD)" ct/1 FINISHED true
refused edited edited
make_case unknown-edit
run_json unknown-edit "$(git -C "$scratch/unknown-edit/clone" rev-parse HEAD)" ct/1 FINISHED '"unknown"'
refused unknown-edit edited
make_case other-version
run_json other-version "$(git -C "$scratch/other-version/clone" rev-parse HEAD)" ct/2 FINISHED false
refused other-version "ct/2"
make_case format-1
sed -i '/"format"/d' "$scratch/format-1/data/runs/9000001/run.json"
refused format-1 "format"
make_case no-record
rm "$scratch/no-record/data/runs/9000001/run.json"
refused no-record "run.json"

# The clone's workflow folder must be the run's commit, uncommitted edits
# included; a change elsewhere in the clone doesn't matter.
make_case moved
echo "print(2)" > "$scratch/moved/clone/workflows/seg/src/run.py"
commit "$scratch/moved/clone"
refused moved "src/run.py"
make_case uncommitted
echo "print(2)" > "$scratch/uncommitted/clone/workflows/seg/src/run.py"
refused uncommitted "src/run.py"
make_case untracked
echo "x" > "$scratch/untracked/clone/workflows/seg/src/new.py"
refused untracked "src/new.py"
make_case elsewhere
echo "# other" > "$scratch/elsewhere/clone/README.md"
commit "$scratch/elsewhere/clone"
out="$(prove elsewhere)" || echo "elsewhere: refused for a change outside the folder: $out"

# The form tests must pass, none skipped.
make_case tests-fail
refused tests-fail "form tests" RUBY_EXIT=1 RUBY_TOTALS="3 runs, 5 assertions, 1 failures, 0 errors, 0 skips"
make_case tests-skip
refused tests-skip "skip" RUBY_TOTALS="3 runs, 0 assertions, 0 failures, 0 errors, 3 skips"
make_case no-tests
git -C "$scratch/no-tests/clone" rm -q workflows/seg/tests/test_form.rb
commit "$scratch/no-tests/clone"
run_json no-tests "$(git -C "$scratch/no-tests/clone" rev-parse HEAD)" ct/1 FINISHED false
refused no-tests "test_form.rb"
