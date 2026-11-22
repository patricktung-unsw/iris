"""bin/helper-compare's driver: submit each case through a browser and compare.

Run by bin/helper-compare, inside its user and mount namespace, where /srv
is a tmpfs of the namespace's own, with the fork's test venv's Python:

    helper-compare.py <fork tree> <fork commit> <workflows> <work dir>

<fork tree> is the fork at <fork commit>, extracted; <workflows> the
clone's workflows/, which the instance serves as its apps_dir; <work dir>
an empty folder for the instance, the stand-in qsub and the scripts.
bin/helper-compare lays an overlay over /usr/share, so the stand-in
modulecmd can go where hello-world's form looks for Katana's. It
starts the instance with the fork's own browser-test code
(misc/tests/browser/instance.py, start and stop), with a stand-in qsub
that keeps the script it is handed. For each case in CASES it loads the
form, fills its fields, submits it, and compares the script the stand-in
qsub kept with lib/tests/form_helper.rb's for the same fields, byte for
byte, printing a unified diff for each that differs. Exits 0 if every case
matches, 1 if any differs or the fork refused one, and 2 if it couldn't
run: an instance or browser that didn't start, or any other error, such as
a field a step names that the page doesn't show.
"""

import os
import signal
import subprocess
import sys
from pathlib import Path

USER = os.environ["USER"]
# Where the microCT form's check: looks for a dataset: inside the
# researcher's scratch, on the namespace's own /srv.
DATASET = f"/srv/scratch/{USER}/iris-helper-compare"
# Where hello-world's form runs Katana's modulecmd to list modules; with
# none listed, the fork's page fails (form.rb's get_oc_disable_attrs reads
# the module field's options, nil, when the form has a disable- widget).
MODULECMD = "/usr/share/Modules/libexec/modulecmd.tcl"
# Lines of what Katana's modulecmd printed for hello-world's MODULEPATH,
# `sh avail -t`, on 2026-11-22, verbatim: a folder line, then module names,
# some with (default) after them.
MODULES = """/apps/Modules/linux-rocky8-ivybridge:
adios2/2.8.3
cuda/11.8.0(default)
cuda/12.1.0
python/3.10.8(default)
python/3.11.3
samtools/1.9
/usr/share/Modules/modulefiles:
"""
# Each form's cases: a name, the browser's steps, and the fields the helper
# is given for the same submission, in the helper's terms (a select's or a
# checkbox's data value, a multi_select's values joined by its separator,
# time as time_1 and time_2). A step is ("fill", <element id>, <text>),
# ("select", <element id>, <option label>), ("check", <element id>) or
# ("add", <multi_select key>, <option label>). Advanced fields are hidden
# until their form's "Show advanced options" box is ticked, so that comes
# first.
CASES = {
    "hello-world": [
        ("defaults", [], {}),
        ("changed", [
            ("check", "show_advanced_option_1"),
            ("check", "log_1"),
            ("fill", "ncpus", "4"),
            ("select", "mem", "16 GB"),
            ("fill", "time_1", "3"),
            ("fill", "time_2", "5"),
            ("select", "mail_events", "Never"),
            ("add", "module", "python/3.11.3"),
            ("add", "module", "cuda/11.8.0(default)"),
        ], {"log": "oe", "ncpus": "4", "mem": "16gb", "time_1": "3", "time_2": "5",
            "mail_events": "n", "module": "python/3.11.3 cuda/11.8.0(default)"}),
    ],
    "microct-2d-segmentation": [
        # The dataset is required and has no default.
        ("defaults", [("fill", "dataset", DATASET)], {"dataset": DATASET}),
        ("changed", [
            ("fill", "dataset", DATASET),
            ("fill", "epochs", "3"),
            ("select", "mem", "32 GB"),
            ("fill", "time_1", "0"),
            ("fill", "time_2", "45"),
            ("check", "show_advanced_option_1"),
            ("fill", "seed", "7"),
            ("fill", "job_name", "iris_helper_compare"),
            ("select", "mail_events", "When the job starts, ends or ends abnormally"),
        ], {"dataset": DATASET, "epochs": "3", "mem": "32gb", "time_1": "0", "time_2": "45",
            "seed": "7", "job_name": "iris_helper_compare", "mail_events": "abe"}),
    ],
}


def make_fixtures():
    """The stand-in modulecmd, and a dataset the microCT form's check: takes."""
    Path(MODULECMD).parent.mkdir(parents=True, exist_ok=True)
    Path(MODULECMD).write_text("#!/bin/sh\ncat <<'EOF'\n" + MODULES + "EOF\n")
    Path(MODULECMD).chmod(0o755)
    for sub in ("volume", "train/images", "train/labels"):
        Path(DATASET, sub).mkdir(parents=True, exist_ok=True)
    Path(DATASET, "volume", "block_0.nc").write_bytes(b"")
    Path(DATASET, "train", "images", "slice_0000.tif").write_bytes(b"")
    Path(DATASET, "train", "labels", "slice_0000.tif").write_bytes(b"")


def stand_in_pbs(work):
    """A bin folder whose qsub copies the script it is handed to work/kept.sh."""
    bin_dir = work / "pbs-bin"
    bin_dir.mkdir()
    kept = work / "kept.sh"
    # qsub's last argument is the script's path (lib/schedulers/pbspro.rb);
    # it prints the job ID as Katana's does, in bin/qwait's example.
    qsub = (f'#!/bin/sh\nfor last; do :; done\ncp "$last" "{kept}" || exit 1\n'
            'echo 9551129.kman.restech.unsw.edu.au\n')
    for name, body in [("qsub", qsub), ("qstat", "#!/bin/sh\ntrue\n")]:
        (bin_dir / name).write_text(body)
        (bin_dir / name).chmod(0o755)
    return bin_dir, kept


def submit(page, url, slug, steps, script_dir):
    """Fill and submit the form; return the fork's error message, or None."""
    page.goto(f"{url}/{slug}")
    # The script goes to a folder of the case's own, not the default home;
    # the fork runs check: in it, so it must exist.
    script_dir.mkdir(parents=True)
    page.fill("#_script_location", str(script_dir))
    for kind, element, *value in steps:
        target = page.locator(f"#{element}")
        if kind == "fill":
            target.fill(value[0])
        elif kind == "select":
            target.select_option(label=value[0])
        elif kind == "add":
            target.fill(value[0])
            page.click(f"#addButton_{element}")
        elif kind == "check":
            target.check()
        else:
            raise ValueError(f"no step kind {kind!r}")
    with page.expect_navigation():
        page.click("#_submitButton")
    if "Job was successfully submitted" in page.content():
        return None
    alerts = page.locator(".alert").all_inner_texts()
    return " | ".join(a.strip() for a in alerts if a.strip()) or "no success message on the page"


def helper_script(helper, apps_dir, slug, fields):
    """The helper's script for the form and fields, as bytes."""
    form = Path(apps_dir, slug, "form.yml.erb")
    pairs = [f"{k}={v}" for k, v in fields.items()]
    return subprocess.run(
        ["ruby", helper, "--apps-dir", apps_dir, "--no-check", str(form), *pairs],
        check=True, capture_output=True).stdout


def main(argv):
    fork, commit, apps_dir, work = argv[1], argv[2], argv[3], Path(argv[4])
    helper = str(Path(__file__).resolve().parent.parent / "lib" / "tests" / "form_helper.rb")
    sys.path.insert(0, str(Path(fork, "misc", "tests", "browser")))
    import instance  # the fork's, at the commit compared
    from playwright.sync_api import Error as PlaywrightError
    from playwright.sync_api import sync_playwright

    # The driver is the PID namespace's first process, which the kernel
    # sends no signal it has no handler for (pid_namespaces(7)): handle
    # SIGTERM, ending through finally, which stops the instance.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(2))
    make_fixtures()
    bin_dir, kept = stand_in_pbs(work)
    (work / "instance").mkdir()
    try:
        url, proc, _ = instance.start({"apps_dir": apps_dir, "bin": str(bin_dir)}, work / "instance")
    except RuntimeError as e:
        print(f"helper-compare: could not start the fork's instance: {e}", file=sys.stderr)
        return 2
    status = 0
    try:
        with sync_playwright() as p:
            try:
                browser = p.chromium.launch()
            except PlaywrightError as e:
                print(f"helper-compare: could not start Chromium: {e}", file=sys.stderr)
                return 2
            page = browser.new_page()
            for slug, cases in CASES.items():
                for case, steps, fields in cases:
                    name = f"{slug} {case}"
                    kept.unlink(missing_ok=True)
                    refused = submit(page, url, slug, steps, Path(DATASET + "-scripts", slug, case))
                    if refused is not None or not kept.exists():
                        print(f"REFUSED: {name}: the fork at {commit} didn't submit it: "
                              f"{refused or 'its qsub was never called'}")
                        status = 1
                        continue
                    helper_out = helper_script(helper, apps_dir, slug, fields)
                    fork_out = kept.read_bytes()
                    if helper_out == fork_out:
                        print(f"same: {name}")
                        continue
                    status = 1
                    print(f"DIFFERENT: {name}")
                    helper_file, fork_file = work / "helper.sh", work / "fork.sh"
                    helper_file.write_bytes(helper_out)
                    fork_file.write_bytes(fork_out)
                    diff = subprocess.run(
                        ["diff", "-u", "--label", f"form_helper.rb: {name}",
                         "--label", f"fork {commit}: {name}", str(helper_file), str(fork_file)],
                        capture_output=True, text=True)
                    sys.stdout.write(diff.stdout)
            browser.close()
    finally:
        instance.stop(proc)
    return status


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as e:  # any other failure is the tool's, not a difference
        print(f"helper-compare: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(2)
