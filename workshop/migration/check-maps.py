#!/usr/bin/env python3
"""Golden-master check for the maps migration (workshop bonus step).

Run from the repository root, in WSL/Linux, with GnuCOBOL (cobc) installed:

  python3 workshop/migration/check-maps.py baseline
      Compiles the ORIGINAL common/maps01.cbl, maps04.cbl and maps09.cbl, runs every
      case in workshop/migration/maps-cases.txt through them and saves the answers to
      workshop/migration/out/maps-golden.txt. Do this BEFORE you change anything.

  python3 workshop/migration/check-maps.py compare LIBDIR
      Runs the same cases against the maps01/04/09 modules found in LIBDIR (your Java
      build) and compares every output line with the golden file. Exit code 0 = identical.

The test driver below is written to a temp directory, never into the repository. It
calls the modules the way the real callers do (copybooks wsmaps01/03/09, same CALL
statements) and records RETURN-CODE after each call. maps09 is called both ways its
callers use it: with the 8-byte maps09-ws block, and with only the 7-byte customer
code, where the reply lands in the caller's next byte.
"""
import glob, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
CASES = os.path.join(HERE, "maps-cases.txt")
GOLDEN = os.path.join(HERE, "out", "maps-golden.txt")
MODULES = ("maps01", "maps04", "maps09")
# The only COBOL sources a maps migration may touch. Callers, copybooks and everything
# else must stay byte for byte as they are.
ALLOWED = {"common/%s.cbl" % m for m in MODULES}

DRIVER = r"""       >>source free
 identification division.
 program-id. tmaps.
 environment division.
 input-output section.
 file-control.
     select case-file assign to dynamic ws-in
            organization line sequential status fs1.
     select out-file assign to dynamic ws-out
            organization line sequential status fs2.
 data division.
 file section.
 fd  case-file.
 01  case-rec            pic x(60).
 fd  out-file.
 01  out-rec             pic x(100).
 working-storage section.
 01  ws-in               pic x(512).
 01  ws-out              pic x(512).
 01  fs1                 pic xx.
 01  fs2                 pic xx.
 01  eof                 pic x value "N".
 copy "wsmaps01.cob".
 copy "wsmaps03.cob".
 copy "wsmaps09.cob".
 01  short-blk.
     03  short-code.
         05  short-nos   pic x(6).
         05  short-cd    pic 9.
     03  short-next      pic x.
 01  bin-in-x            pic x(11).
 01  bin-in redefines bin-in-x  pic s9(10) sign leading separate.
 01  bin-out             pic s9(10) sign leading separate.
 01  rc                  pic s9(4) sign leading separate.
 procedure division.
     accept   ws-in  from environment "T_IN"
     accept   ws-out from environment "T_OUT"
     open     input case-file output out-file
     if       fs1 not = "00" or fs2 not = "00"
              display "test driver: cannot open the case or output file, status "
                      fs1 " " fs2 upon syserr
              move 9 to return-code
              stop run
     end-if
     perform  until eof = "Y"
              read case-file
              evaluate fs1
                when "00"  perform one-case
                when "10"  move "Y" to eof
                when other display "test driver: read error, status " fs1 upon syserr
                           move 9 to return-code
                           stop run
              end-evaluate
     end-perform
     close    case-file out-file
     goback.
 one-case.
     move     spaces to out-rec
     evaluate case-rec (1:2)
       when "01"
            move case-rec (4:1)  to encode
            move case-rec (5:4)  to pass-word
            move case-rec (9:32) to pass-name
            move zero to return-code
            call "maps01" using maps01-ws
            move return-code to rc
            string "01|" encode pass-word pass-name "|" rc
                   delimited by size into out-rec
       when "04"
            move case-rec (4:10) to u-date
            move case-rec (15:11) to bin-in-x
            move bin-in to u-bin
            move zero to return-code
            call "maps04" using maps03-ws
            move return-code to rc
            move u-bin to bin-out
            string "04|" function hex-of (u-date) "|" bin-out "|" rc
                   delimited by size into out-rec
       when "09"
            move case-rec (4:8) to maps09-ws
            move zero to return-code
            call "maps09" using maps09-ws
            move return-code to rc
            move case-rec (4:8) to short-blk
            call "maps09" using short-code
            string "09|" maps09-ws "|" short-blk "|" rc
                   delimited by size into out-rec
     end-evaluate
     write    out-rec.
"""


def sh(cmd, cwd=None, env=None, timeout=600):
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f"timed out after {timeout}s: {cmd}\n(a module that never returns, or a hung driver)")
    return p.returncode, (p.stdout + p.stderr)


def die(msg):
    sys.exit(msg)


def run_cases(libdir):
    """Run every case through the maps modules found in libdir; return the output lines."""
    if not os.path.exists(CASES):
        die(f"{os.path.relpath(CASES, REPO)} is missing. Regenerate it: python3 workshop/migration/gen-cases.py")
    work = tempfile.mkdtemp(prefix="maps-check-")
    try:
        with open(os.path.join(work, "tmaps.cbl"), "w") as f:
            f.write(DRIVER)
        rc, log = sh(f"cobc -x tmaps.cbl -I '{REPO}/copybooks' -o tmaps", work)
        if rc:
            die("test driver failed to compile:\n" + log[-1500:])
        out = os.path.join(work, "out.txt")
        env = dict(os.environ, COB_LIBRARY_PATH=libdir, T_IN=CASES, T_OUT=out)
        rc, log = sh("./tmaps", work, env, timeout=300)
        if rc or not os.path.exists(out):
            die("the test driver stopped (a module failed to load or crashed?):\n" + log[-1500:])
        with open(out, "rb") as f:
            return [l.rstrip(b"\r\n").decode("latin-1").rstrip() for l in f]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def git_changed():
    """COBOL files that differ from the last commit. CRLF-safe on a Windows checkout."""
    r = subprocess.run("git -c core.autocrlf=true status --porcelain -- '*.cbl' '*.cob' '*.cpy' '*.scb'",
                       cwd=REPO, shell=True, capture_output=True, text=True)
    if r.returncode:
        err = r.stderr.strip() or "git failed"
        if "dubious ownership" in err:     # a Windows checkout seen from WSL
            err += "\nFix: git config --global --add safe.directory '*'   (then run this again)"
        elif "not found" in err:
            err += "\nFix: sudo apt-get install -y git"
        return None, err
    return [l[3:].strip() for l in r.stdout.splitlines() if l.strip()], ""


def baseline():
    changed, err = git_changed()
    if changed is None:
        die("git can't tell whether the COBOL is unchanged: " + err)
    touched = [c for c in changed if c in ALLOWED]
    if touched:
        die("Run the baseline BEFORE you change the COBOL. These are already modified: "
            + ", ".join(touched) + "\n(git restore them, or run the baseline from a clean checkout.)")
    lib = tempfile.mkdtemp(prefix="maps-orig-")
    try:
        for m in MODULES:
            shutil.copy(os.path.join(REPO, "common", m + ".cbl"), lib)
            # Same flags as the release build (setup-acas.sh).
            rc, log = sh(f"cobc -m -lz {m}.cbl -I '{REPO}/copybooks' -Wlinkage", lib)
            if rc:
                die(f"original {m} failed to compile:\n" + log[-1500:])
        lines = run_cases(lib)
    finally:
        shutil.rmtree(lib, ignore_errors=True)
    os.makedirs(os.path.dirname(GOLDEN), exist_ok=True)
    with open(GOLDEN, "w", newline="\n", encoding="latin-1") as f:
        f.write("\n".join(lines) + "\n")
    n = {m: sum(l.startswith(m[-2:] + "|") for l in lines) for m in MODULES}
    print(f"Baseline: {len(lines)} cases run through the ORIGINAL COBOL "
          f"(maps01 {n['maps01']}, maps04 {n['maps04']}, maps09 {n['maps09']}).")
    print(f"Golden answers saved to {os.path.relpath(GOLDEN, REPO)}")


def uses_java(libdir, m):
    for so in glob.glob(os.path.join(libdir, m + "*.so")):
        if "libjvm" in sh(f"ldd '{so}'")[1]:
            return True
    return False


def compare(libdir):
    libdir = os.path.abspath(libdir)
    if not os.path.exists(GOLDEN):
        die("No golden file yet. Run the baseline first (before migrating).")
    missing = [m for m in MODULES if not os.path.exists(os.path.join(libdir, m + ".so"))]
    if missing:
        die("not found in %s: %s. Build all three modules into it first." % (libdir, ", ".join(m + ".so" for m in missing)))
    with open(GOLDEN, "rb") as f:
        golden = [l.rstrip(b"\r\n").decode("latin-1").rstrip() for l in f]
    actual = run_cases(libdir)

    per = {m: [0, 0] for m in MODULES}
    shown = []
    for k, exp in enumerate(golden):
        m = "maps" + exp[:2]
        got = actual[k] if k < len(actual) else "(no output)"
        per[m][1] += 1
        if got == exp:
            per[m][0] += 1
        elif len(shown) < 10:
            shown.append(f"  {m}  expected {exp!r}\n  {'':6}  got      {got!r}")
    extra = len(actual) - len(golden)

    changed, err = git_changed()
    # workshop/ is training material (it holds the reference solution's own COBOL copies), not repo source.
    bad = None if changed is None else [c for c in changed if c not in ALLOWED and not c.startswith("workshop/")]
    java = {m: uses_java(libdir, m) for m in MODULES}

    print(f"modules under test    : {libdir}")
    for m in MODULES:
        print(f"  {m}  runs Java (libjvm) : {'yes' if java[m] else 'NO - not a Java build'}")
    if bad is None:
        print(f"COBOL outside maps    : UNKNOWN ({err})")
    else:
        print(f"COBOL outside maps    : {'unchanged' if not bad else 'CHANGED:'}")
        for c in bad[:10]:
            print("  " + c)
    total = sum(v[1] for v in per.values())
    ok_n = sum(v[0] for v in per.values())
    print(f"Golden comparison     : {ok_n}/{total} lines identical  "
          + "  ".join(f"{m} {v[0]}/{v[1]}" for m, v in per.items()))
    if extra:
        print(f"  the driver wrote {extra:+d} lines compared with the baseline")
    for s in shown:
        print(s)
    ok = ok_n == total and not extra and all(java.values()) and bad == []
    print("RESULT: PASS" if ok else "RESULT: FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "baseline":
        baseline()
    elif len(sys.argv) == 3 and sys.argv[1] == "compare":
        compare(sys.argv[2])
    else:
        sys.exit(__doc__)
