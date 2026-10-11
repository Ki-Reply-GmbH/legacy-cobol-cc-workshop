#!/usr/bin/env python3
"""Create or check the files in seed/: the ACAS start-up data setup-acas.sh installs.

The first time ACAS starts it asks for its system parameters (company name,
sub-systems, dates, ...), stores them in system.dat, and then creates the default
Sales and Purchase analysis records (analysis.dat, value.dat). This script does
all of that by running the real ACAS screens in a pseudo-terminal and answering
them, so every file is written by ACAS itself, never edited by hand.

Needs an installed ACAS (bash setup-acas.sh) with its settings loaded, i.e.
ACAS on PATH and COB_LIBRARY_PATH pointing at ~/bin. Linux, WSL or macOS.
Python 3.8+, standard library only.

  python3 seed/make-seed.py               write seed/system.dat, analysis.dat, value.dat
  python3 seed/make-seed.py --verify      check them: ACAS must open on its main menu,
                                          Sales and every ledger must open and exit cleanly
Options: --out-dir DIR  --company NAME  --year YYYY  --verify [DIR]  --debug

The answers are listed in seed/README.md. Nothing in your own ~/ACAS is touched:
both modes work in a temporary data directory.
"""
import argparse, fcntl, os, re, select, shutil, signal, struct, subprocess, sys, tempfile, termios, time

ROWS, COLS = 24, 80
HERE = os.path.dirname(os.path.abspath(__file__))
DEBUG = False


# --- a minimal terminal emulator ----------------------------------------------
# ACAS draws with ncurses, which sends only what changed on the screen. Matching on
# the raw output would miss text that didn't need redrawing, so keep a screen model.
class Screen:
    def __init__(self):
        self.grid = [[" "] * COLS for _ in range(ROWS)]
        self.r = self.c = 0
        self.saved = (0, 0)
        self.last = " "
        self.buf = ""

    def _clamp(self):
        self.r = max(0, min(ROWS - 1, self.r))
        self.c = max(0, min(COLS - 1, self.c))

    def _scroll(self, n=1):
        for _ in range(n):
            self.grid.pop(0)
            self.grid.append([" "] * COLS)

    def _put(self, ch):
        if self.c >= COLS:                      # deferred auto-wrap, as xterm does
            self.c = 0
            self.r += 1
            if self.r >= ROWS:
                self._scroll()
                self.r = ROWS - 1
        self.grid[self.r][self.c] = ch
        self.c += 1
        self.last = ch

    def _csi(self, params, final):
        priv = params.startswith("?")
        nums = [int(p) if p.isdigit() else 0 for p in params.lstrip("?>=").split(";")] if params.lstrip("?>=") else []
        n = nums[0] if nums and nums[0] else 1
        if final in "Hf":
            self.r = (nums[0] if len(nums) > 0 and nums[0] else 1) - 1
            self.c = (nums[1] if len(nums) > 1 and nums[1] else 1) - 1
        elif final == "A": self.r -= n
        elif final == "B": self.r += n
        elif final == "C": self.c += n
        elif final == "D": self.c -= n
        elif final in "G`": self.c = n - 1
        elif final == "d": self.r = n - 1
        elif final == "J":
            mode = nums[0] if nums else 0
            if mode == 0:
                self.grid[self.r][self.c:] = [" "] * (COLS - self.c)
                for row in range(self.r + 1, ROWS): self.grid[row] = [" "] * COLS
            elif mode == 1:
                for row in range(self.r): self.grid[row] = [" "] * COLS
                self.grid[self.r][:self.c + 1] = [" "] * (self.c + 1)
            else:
                self.grid = [[" "] * COLS for _ in range(ROWS)]
        elif final == "K":
            mode = nums[0] if nums else 0
            if mode == 0: self.grid[self.r][self.c:] = [" "] * (COLS - self.c)
            elif mode == 1: self.grid[self.r][:self.c + 1] = [" "] * (self.c + 1)
            else: self.grid[self.r] = [" "] * COLS
        elif final == "X":
            for i in range(self.c, min(COLS, self.c + n)): self.grid[self.r][i] = " "
        elif final == "b":
            for _ in range(n): self._put(self.last)
        elif final == "@":
            row = self.grid[self.r]
            self.grid[self.r] = (row[:self.c] + [" "] * n + row[self.c:])[:COLS]
        elif final == "P":
            row = self.grid[self.r]
            self.grid[self.r] = row[:self.c] + row[self.c + n:] + [" "] * n
        elif final == "L":
            for _ in range(n):
                self.grid.insert(self.r, [" "] * COLS); self.grid.pop()
        elif final == "M":
            for _ in range(n):
                self.grid.pop(self.r); self.grid.append([" "] * COLS)
        elif final == "S": self._scroll(n)
        elif final in "hl" and priv and 1049 in nums:
            self.grid = [[" "] * COLS for _ in range(ROWS)]
        # colours (m), modes (h/l), scroll region (r) and reports don't change the text
        self._clamp()

    def feed(self, data):
        s = self.buf + data
        self.buf = ""
        i = 0
        while i < len(s):
            ch = s[i]
            if ch == "\x1b":
                if i + 1 >= len(s):
                    self.buf = s[i:]; return
                nxt = s[i + 1]
                if nxt == "[":
                    m = re.compile(r"\x1b\[([0-9;?>=]*)[ -/]*([@-~])").match(s, i)
                    if not m:
                        self.buf = s[i:]; return
                    self._csi(m.group(1), m.group(2))
                    i = m.end(); continue
                if nxt in "()*+":                # character set selection
                    if i + 2 >= len(s):
                        self.buf = s[i:]; return
                    i += 3; continue
                if nxt == "]":                   # operating system command (title)
                    end = s.find("\x07", i)
                    st = s.find("\x1b\\", i)
                    cut = min([e for e in (end, st) if e != -1], default=-1)
                    if cut == -1:
                        self.buf = s[i:]; return
                    i = cut + (1 if cut == end else 2); continue
                if nxt == "7": self.saved = (self.r, self.c)
                elif nxt == "8": self.r, self.c = self.saved
                elif nxt == "c": self.grid = [[" "] * COLS for _ in range(ROWS)]; self.r = self.c = 0
                elif nxt == "M":
                    if self.r == 0: self.grid.insert(0, [" "] * COLS); self.grid.pop()
                    else: self.r -= 1
                elif nxt in "DE":
                    if nxt == "E": self.c = 0
                    if self.r == ROWS - 1: self._scroll()
                    else: self.r += 1
                i += 2; continue
            if ch == "\r": self.c = 0
            elif ch == "\n":
                if self.r == ROWS - 1: self._scroll()
                else: self.r += 1
            elif ch == "\b": self.c = max(0, self.c - 1)
            elif ch == "\t": self.c = min(COLS - 1, (self.c // 8 + 1) * 8)
            elif ch >= " " and ch != "\x7f": self._put(ch)
            i += 1
        self._clamp()

    def rows(self):
        return ["".join(r).rstrip() for r in self.grid]

    def text(self):
        # one space between words, so "S-L  Data 1" matches "S-L Data 1"
        return "\n".join(" ".join(r.split()) for r in self.rows())

    def dump(self):
        return "\n".join("|" + r for r in self.rows())


# --- driving a program in a pseudo-terminal ------------------------------------
class Session:
    def __init__(self, argv, data_dir):
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        env = dict(os.environ, TERM="xterm", LINES=str(ROWS), COLUMNS=str(COLS),
                   ACAS_LEDGERS=data_dir, COB_SCREEN_ESC="YES", COB_SCREEN_EXCEPTIONS="YES",
                   COB_EXIT_WAIT="0")
        self.proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, cwd=data_dir,
                                     env=env, start_new_session=True, close_fds=True)
        os.close(slave)
        self.fd = master
        self.screen = Screen()
        self.raw = b""

    def pump(self, seconds):
        """Read output for up to `seconds`; returns False once the program has gone."""
        end = time.time() + seconds
        while True:
            left = end - time.time()
            if left <= 0:
                return True
            r, _, _ = select.select([self.fd], [], [], left)
            if not r:
                return True
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            self.raw += chunk
            self.screen.feed(chunk.decode("latin-1"))

    def settle(self, quiet=0.4, limit=15):
        """Wait until output has been quiet for `quiet` seconds."""
        end = time.time() + limit
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], quiet)
            if not r:
                return True
            try:
                chunk = os.read(self.fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            self.raw += chunk
            self.screen.feed(chunk.decode("latin-1"))
        return True

    def has(self, text):
        return " ".join(text.split()) in self.screen.text()

    def wait_for(self, text, timeout=30):
        end = time.time() + timeout
        while time.time() < end:
            if self.has(text):
                self.settle()
                return
            if not self.pump(0.3) and not self.has(text):
                break
        raise Failure("Waited for '%s' but it didn't appear." % text, self)

    def send(self, keys, pause=0.15):
        if DEBUG:
            sys.stderr.write("\n----- screen -----\n%s\n----- sending %r\n" % (self.screen.dump(), keys))
        for k in keys:
            os.write(self.fd, k.encode("latin-1"))
            time.sleep(0.02)
        time.sleep(pause)
        self.settle()

    def finish(self, timeout=20):
        """Wait for the program to exit; returns its exit status (negative = signal)."""
        end = time.time() + timeout
        while self.proc.poll() is None and time.time() < end:
            self.pump(0.3)
        if self.proc.poll() is None:
            raise Failure("The program didn't exit.", self)
        try:
            os.close(self.fd)
        except OSError:
            pass
        return self.proc.returncode

    def kill(self):
        if self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except OSError:
                pass
            self.proc.wait()


class Failure(Exception):
    def __init__(self, msg, session=None):
        if session is not None:
            msg += "\nScreen at that moment:\n" + session.screen.dump()
        super().__init__(msg)


ERRORS = ("SY005", "SY105", "Cycle Error", "Print Spool Name must be defined", "SY10", "SY11",
          "SLA12", "SLA14", "FS-Reply =", "Segmentation", "libcob: error", "invalid memory address")


def check_errors(s):
    for e in ERRORS:
        if s.has(e):
            raise Failure("ACAS showed an error: '%s'." % e, s)


def exit_status_ok(code, what):
    if code < 0 or code >= 128:
        sig = -code if code < 0 else code - 128
        raise Failure("%s ended with signal %d (%s)." % (what, sig, signal.Signals(sig).name if sig in signal.Signals._value2member_map_ else "?"))
    if code != 0:
        raise Failure("%s ended with exit status %d." % (what, code))


# --- the answers ----------------------------------------------------------------
def answer_setup(s, company, year):
    """Answer every set-up screen. Returns the names of the screens answered once
    ACAS reaches its main menu, or once ACAS ends after the last screen (see below)."""
    s.wait_for("Enter the Company name")
    s.send(company + "\r")
    s.wait_for("Please VERIFY that name is correct")
    s.send("Y\r")
    s.wait_for("Using Invoicing")
    for _ in range(6):                          # the six "Using ..." questions: Y is the default
        s.send("\r")
    s.wait_for("Please confirm (Y/N)")
    s.send("Y\r")

    done = set()
    for _ in range(40):                         # far more than the screens there are
        s.settle()
        if "print" in done and s.proc.poll() is not None:
            # ACAS.cbl's first-run block then calls sl070 with two of the four
            # arguments it needs, which crashes (upstream bug). system.dat is saved
            # by then; make() creates sl070's records the correct way afterwards.
            return done
        check_errors(s)
        if s.has("ACAS System Menu"):
            return done
        if s.has("OK to file (Y/N)"):           # each screen's confirmation box; default Y
            s.send("\r"); continue
        if s.has("Do you want printed copy"):   # N: there is no printer to print to
            s.send("N\r"); done.add("print")
            for _ in range(20):                 # main menu, or ACAS ends (see above)
                if s.proc.poll() is not None or s.has("ACAS System Menu"):
                    break
                s.pump(0.5)
            continue
        if s.has("Date Format") and "user" not in done:
            # address 1-4, post code, country, date format (7 fields), then the dates,
            # stats year, print lines. Everything else keeps its default.
            s.send("\t" * 7 + "01/01/%d" % year + "\t" + "31/12/%d" % year + "\t\t" + "048" + "\r")
            done.add("user"); continue
        if s.has("Cups Print Spooler name 1") and "spool" not in done:
            s.send("none\tnone\tnone\r"); done.add("spool"); continue
        if s.has("Operating System") and "ops" not in done:
            s.send("\t\t" + "6" + "\r"); done.add("ops"); continue       # 6 = Linux
        if s.has("Use IRS instead of GL") and "gl" not in done:
            s.send("\t" * 11 + "Y" + "\r"); done.add("gl"); continue    # field 12 of 12
        if s.has("IRS Client") and "irs" not in done:
            s.send(company + "\r"); done.add("irs"); continue
        before = s.screen.text()
        s.send("\r")                            # any other screen: keep its defaults
        if s.screen.text() == before:
            s.pump(2)
            if s.screen.text() == before:
                raise Failure("A set-up screen didn't react to Enter.", s)
    raise Failure("The set-up screens never reached the ACAS System Menu.", s)


SEED_FILES = ("system.dat", "analysis.dat", "value.dat")


def leave_acas_menu(s):
    """X on the ACAS System Menu ends ACAS."""
    s.send("X")
    if s.proc.poll() is None and s.has("ACAS System Menu"):
        s.send("\r")


def open_acas_menu(s):
    """ACAS must go straight to its main menu, with no set-up screens first."""
    s.wait_for("ACAS System Menu")
    if b"Setup Routine" in s.raw:
        raise Failure("The set-up screens appeared, so the settings file wasn't accepted.", s)


def enter_sales(s):
    """From the ACAS menu: B, accept the date ACAS offers, wait for the Sales menu."""
    s.send("B")
    for _ in range(6):
        s.pump(1)
        check_errors(s)
        if s.has("Set-Up Sales Analysis Codes"):
            return
        s.send("\r")
    s.wait_for("Set-Up Sales Analysis Codes")


def open_analysis_setup(s):
    """Sales menu L runs sl070 (with all four arguments it needs), which creates the
    default analysis records if there are none. Its option 5 then reads them back from
    analysis.dat; "Default Sales" is one of the defaults. X ends the list, 9 goes back."""
    s.send("L")
    s.wait_for("Set-up P/A records")
    check_errors(s)
    s.send("5")
    s.wait_for("Default Sales")
    check_errors(s)
    s.send("X\r")
    s.wait_for("Set-up P/A records")
    s.send("9")
    s.wait_for("Set-Up Sales Analysis Codes")


def sha256(path):
    import hashlib
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def write_checksums(out_dir):
    with open(os.path.join(out_dir, "SHA256SUMS"), "w", newline="\n") as f:
        for name in SEED_FILES:
            f.write("%s  %s\n" % (sha256(os.path.join(out_dir, name)), name))


def check_checksums(seed_dir):
    """The files must be byte for byte what make() wrote: a changed byte in an indexed
    file isn't always visible on screen."""
    sums = os.path.join(seed_dir, "SHA256SUMS")
    if not os.path.isfile(sums):
        raise Failure("%s has no SHA256SUMS, so the files can't be checked. Regenerate them with "
                      "make-seed.py." % seed_dir)
    want = {}
    with open(sums) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2:
                want[parts[1].lstrip("*")] = parts[0].lower()
    for name in SEED_FILES:
        if name not in want:
            raise Failure("SHA256SUMS has no line for %s." % name)
        if sha256(os.path.join(seed_dir, name)) != want[name]:
            raise Failure("%s isn't the file make-seed.py wrote (its SHA-256 doesn't match SHA256SUMS). "
                          "It was changed or damaged, for example by line-ending conversion; "
                          "see .gitattributes." % name)


def leave_sales(s):
    """X on the Sales menu returns to ACAS (Sales runs a data backup on the way out)."""
    for _ in range(3):
        if s.has("ACAS System Menu"):
            break
        s.send("X")
        s.pump(3)
    s.wait_for("ACAS System Menu")
    check_errors(s)


def find_acas():
    acas = shutil.which("ACAS")
    if not acas:
        sys.exit("ACAS isn't on PATH. Install it (bash setup-acas.sh), open a new terminal so its "
                 "settings load, then run this again.")
    if not os.environ.get("COB_LIBRARY_PATH"):
        sys.exit("COB_LIBRARY_PATH isn't set: open a new terminal after bash setup-acas.sh.")
    return acas


def make(out_dir, company, year):
    acas = find_acas()
    with tempfile.TemporaryDirectory(prefix="acas-seed.") as d:
        # 1. A first launch: ACAS finds no system.dat and runs its set-up screens.
        s = Session([acas], d)
        crashed = None
        try:
            answered = answer_setup(s, company, year)
            missing = {"user", "ops", "spool", "gl", "irs", "print"} - answered
            if missing:
                raise Failure("These set-up screens never appeared: %s." % ", ".join(sorted(missing)), s)
            if s.proc.poll() is None:          # reached the main menu
                leave_acas_menu(s)
                exit_status_ok(s.finish(), "ACAS")
            else:                              # the upstream sl070 crash, see answer_setup()
                crashed = s.proc.returncode
        finally:
            s.kill()
        if not os.path.isfile(os.path.join(d, "system.dat")):
            raise Failure("The set-up screens finished, but ACAS wrote no system.dat.")

        # 2. Create the default Sales and Purchase analysis records the way the
        #    Sales menu does (L), which is what the first launch was meant to do.
        s = Session([acas], d)
        try:
            open_acas_menu(s)
            enter_sales(s)
            open_analysis_setup(s)
            leave_sales(s)
            leave_acas_menu(s)
            exit_status_ok(s.finish(), "ACAS")
        finally:
            s.kill()

        missing = [f for f in SEED_FILES if not os.path.isfile(os.path.join(d, f))]
        if missing:
            raise Failure("ACAS didn't create %s." % ", ".join(missing))
        os.makedirs(out_dir, exist_ok=True)
        for f in SEED_FILES:
            shutil.copyfile(os.path.join(d, f), os.path.join(out_dir, f))
        write_checksums(out_dir)
    print("Wrote %s and SHA256SUMS to %s." % (", ".join(SEED_FILES), out_dir))
    if crashed is not None:
        print("Note: after the set-up screens ACAS ended with status %d: the known upstream bug in "
              "ACAS.cbl's first-run call of sl070 (see seed/README.md). The analysis records were "
              "created afterwards through the Sales menu instead." % crashed)
    print("Check the result with:  python3 %s --verify %s" % (os.path.relpath(__file__), out_dir))


def verify(seed_dir):
    acas = find_acas()
    missing = [f for f in SEED_FILES if not os.path.isfile(os.path.join(seed_dir, f))]
    if missing:
        raise Failure("Not in %s: %s" % (seed_dir, ", ".join(missing)))
    check_checksums(seed_dir)
    steps = ["The files match SHA256SUMS byte for byte"]
    with tempfile.TemporaryDirectory(prefix="acas-verify.") as d:
        for f in SEED_FILES:
            shutil.copyfile(os.path.join(seed_dir, f), os.path.join(d, f))

        # 1. ACAS opens on its main menu; Sales and its analysis set-up open and
        #    close; ACAS exits cleanly.
        s = Session([acas], d)
        try:
            open_acas_menu(s)
            steps.append("ACAS opens on the ACAS System Menu, with no set-up screens")
            enter_sales(s)
            open_analysis_setup(s)
            leave_sales(s)
            steps.append("Sales Ledger opens, its analysis codes are read back from analysis.dat (L, 5), "
                         "and Sales returns to ACAS")
            leave_acas_menu(s)
            exit_status_ok(s.finish(), "ACAS")
            steps.append("ACAS exits cleanly (exit status 0)")
        finally:
            s.kill()

        # 2. The other ledgers start directly by name, show their menu and exit cleanly.
        for prog, title in (("irs", "IRS System Menu"), ("stock", "Stock Control System Menu"),
                            ("purchase", "Purchase Ledger System Menu"), ("general", "General Ledger System Menu")):
            exe = shutil.which(prog)
            if not exe:
                raise Failure("%s isn't on PATH." % prog)
            s = Session([exe], d)
            try:
                for _ in range(6):
                    s.pump(1)
                    check_errors(s)
                    if s.has(title):
                        break
                    s.send("\r")                    # accept the date ACAS offers
                s.wait_for(title)
                if b"Setup Routine" in s.raw:
                    raise Failure("%s showed the set-up screens." % prog, s)
                for _ in range(3):
                    if s.proc.poll() is not None:
                        break
                    s.send("X")
                    s.pump(2)
                exit_status_ok(s.finish(), prog)
                steps.append("%s opens on '%s' and exits cleanly" % (prog, title))
            finally:
                s.kill()

    print("OK: %s holds working ACAS start-up data." % seed_dir)
    for st in steps:
        print("  - " + st)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out-dir", default=HERE, help="where to write the files (default: this folder)")
    ap.add_argument("--company", default="ACAS Workshop")
    ap.add_argument("--year", type=int, default=2026, help="financial year (01/01 to 31/12)")
    ap.add_argument("--verify", metavar="DIR", nargs="?", const=HERE,
                    help="check the files in DIR (default: this folder) instead of writing them")
    ap.add_argument("--debug", action="store_true", help="print every screen and the keys sent to it")
    a = ap.parse_args()
    global DEBUG
    DEBUG = a.debug
    if len(a.company) > 32:
        sys.exit("--company: ACAS allows at most 32 characters.")
    try:
        if a.verify:
            verify(a.verify)
        else:
            make(a.out_dir, a.company, a.year)
    except Failure as e:
        sys.exit("FAILED: %s" % e)


if __name__ == "__main__":
    main()
