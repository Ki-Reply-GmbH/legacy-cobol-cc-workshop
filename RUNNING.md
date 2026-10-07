# Running ACAS v3.3

[`setup-acas.sh`](setup-acas.sh) installs the compiler, builds ACAS (COBOL files only, no database) and installs it. It copies the sources to `~/cobolsrc/ACAS` and builds there, so this repo is left untouched. You run it **once**; after that you only need the two commands under [Start ACAS](#start-acas).

| System | How | Status |
|---|---|---|
| Windows 10/11 | Inside **WSL2 Ubuntu** (the build scripts are bash) | Tested on Ubuntu 26.04 + GnuCOBOL 3.2.0 |
| Debian / Ubuntu | Directly | Same path as WSL; tested there |
| macOS | Homebrew | Install logic simulated on Linux; **not yet run on a real Mac** |
| Other Linux (Fedora, Arch, …) | Install the packages yourself, then `SKIP_DEPS=1` | Untested |

## Check your machine first (optional, changes nothing)

```bash
bash setup-acas.sh --check
```

It reports, with `[ok]`, `[..]` (note) or `[!!]` (blocking): your system, whether GnuCOBOL 3.x is installed **and can compile a small program**, whether the package step needs `sudo` (and whether `sudo` can ask for a password here), free disk space, and the terminal size. It installs nothing.

**What the script installs, and what it doesn't.** It installs packages only if GnuCOBOL 3.x isn't already usable. On Debian/Ubuntu it uses `apt-get`, which is always there; on macOS it uses Homebrew, which is **not** installed with macOS and which the script never installs for you.

## Windows

1. In **PowerShell as Administrator** (once), then reboot if asked:
   ```powershell
   wsl --install -d Ubuntu
   ```
2. Open **Ubuntu** from the Start menu and create your Linux username and password.
3. In the Ubuntu terminal (replace `<you>` with your Windows user name):
   ```bash
   bash /mnt/c/Users/<you>/Documents/Projects/Code-v3.3/setup-acas.sh
   ```
   Enter your Linux password when `sudo` asks. It ends with `==> ACAS is installed`.
4. Load the new settings, then [start ACAS](#start-acas):
   ```bash
   exec bash
   ```

## Debian / Ubuntu

```bash
cd Code-v3.3
bash setup-acas.sh
exec bash
```

Another distro? Install GnuCOBOL 3.2 and the Berkeley DB, ncurses and zlib development packages with your package manager, then run `SKIP_DEPS=1 bash setup-acas.sh`.

## macOS

1. Install [Homebrew](https://brew.sh) first (check with `brew --version`). It doesn't come with macOS, and the script stops with this instruction if it can't find it. The script starts `xcode-select --install` for you if the Command Line Tools are missing; if it does, let that finish and re-run.
2. In Terminal:
   ```bash
   cd Code-v3.3
   bash setup-acas.sh
   exec zsh
   ```
   (Homebrew installs GnuCOBOL. The settings go into `~/.zshrc`, or `~/.bash_profile` if your shell is bash.)

## Start ACAS

Every time, in a terminal at least **80 columns × 24 lines**:

```bash
cd ~/ACAS
ACAS
```

`irs`, `stock`, `purchase` and `general` also start by name. **Sales has no command of its own in this build; open it from the `ACAS` menu.**

## First launch: setup screens

The first run asks for the system parameters (Tab = next field, Enter = accept the whole screen, Esc = quit):

| Field | Enter |
|---|---|
| Company name | Your real name. Asked **once**; can't be changed later. Then `Y` to verify. |
| The six "Using …" questions | `Y` for all (asked once), then `Y` to confirm |
| Date format | `1` = dd/mm/yyyy |
| Start / End date, VAT rates | Your financial year and rates |
| **Data File Handling (1-13)** | **`0`** (plain files; this build has no database) |
| **Operating System (2-03)** | **`6`** Linux (also for WSL), **`3`** Mac |
| Print spool names | A name, e.g. `none`. Real printing needs a CUPS printer with exactly that name. |
| **Use IRS instead of GL?** | **`Y`**: IRS is the tested ledger; General Ledger hasn't been re-verified |
| Print parameters at the end ("Do you want printed copy") | `N`. Without a printer, `Y` ends in a segmentation fault (see Troubleshooting) |

Everything else: keep the defaults. Details are in `ACAS-Manuals/ACAS - Building the ACAS System.pdf`, chapter 19.

## Re-running or starting over

- **Rebuild only** (e.g. after editing a `.cbl` file): `bash setup-acas.sh --clean`. Your accounting data in `~/ACAS` is kept.
- **Remove everything and start from scratch.** This **deletes all accounting data** in `~/ACAS`:
  ```bash
  rm -rf ~/cobolsrc/ACAS ~/bin ~/ACAS ~/ACAS-practice ~/tmp
  ```
  Then remove the ACAS block from your shell settings and open a new terminal:
  ```bash
  # Linux / WSL
  sed -i '/^export COB_SCREEN_ESC=YES$/,/^# above not needed/d' ~/.bashrc
  # macOS
  sed -i '' '/^# ACAS (added by setup-acas.sh)$/,/^export TMPDIR=/d' ~/.zshrc
  ```
- Run `bash setup-acas.sh --help` for all options (`ACAS_BUILD_DIR=path`, `SKIP_DEPS=1`).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ERROR: ... already exists` | A previous build copy exists. Re-run with `--clean`. |
| `ERROR: The build reported the errors above` | A compile failed. The full log is `~/cobolsrc/ACAS/build.log`. |
| `export: ... not a valid identifier` when opening a terminal (WSL) | The upstream installer wrote an unquoted PATH line. `setup-acas.sh` repairs it; to fix an older install by hand, see below. |
| `syntax error near unexpected token` with `\r` in it, or `command not found` with `\r`, or `bad interpreter` |  The script has Windows line endings, for example after downloading a zip. Fix: `sed -i 's/\r$//' setup-acas.sh` (Linux/WSL) and re-run. A git checkout doesn't do this; `.gitattributes` keeps `*.sh` as LF. |
| `This is Windows (MINGW64...)` | You ran it in Git Bash or PowerShell. Open **Ubuntu** (WSL) and run it there. |
| `Don't run this with sudo` | Run `bash setup-acas.sh` as yourself. It asks for `sudo` only if it must install packages; under `sudo` ACAS would be installed into root's home. |
| `sudo needs a password but there's no terminal` | You ran it from a pipe, a script or CI. Run it from a terminal, or install GnuCOBOL 3.x, a C compiler, make and the Berkeley DB, ncurses and zlib development packages yourself and use `SKIP_DEPS=1`. |
| `This Linux has no apt-get` | Only Debian/Ubuntu are automated. Install the packages named in the message with your own package manager, then `SKIP_DEPS=1 bash setup-acas.sh`. |
| `Homebrew was not found` | macOS only. Install Homebrew from https://brew.sh, open a **new** Terminal, re-run. |
| `cobc ... can't compile and link a small test program` | GnuCOBOL is there but a C compiler, or the zlib or ncurses development files, are missing. The message includes cobc's own error. |
| `GnuCOBOL 3.1` warning | Your system's package is older than the 3.2 ACAS is tested with. Most of the build may still work; if it fails, build GnuCOBOL 3.2 from https://gnucobol.sourceforge.io. |
| `sudo didn't accept the password, or you aren't allowed to use sudo` | Asked once, before anything is installed. Retype it, or ask an administrator to install the packages and use `SKIP_DEPS=1`. |
| `This is the copy of setup-acas.sh inside a build directory` | You ran `~/cobolsrc/ACAS/setup-acas.sh`. Run the one in your clone; with `--clean`, the copy would delete its own sources. |
| `ACAS_BUILD_DIR must be a directory of its own` or `contains the sources` | `ACAS_BUILD_DIR` is `/`, your home, the repository or a folder above it, which `--clean` would delete. Pick an empty, separate directory. |
| `The ACAS settings aren't in ~/.bashrc (it may be read-only)` | The build is installed; only the settings are missing. Add the lines printed with the warning to your shell start-up file yourself. |
| `The installer reported problems` | A module wasn't copied into `~/bin`. The lines after the warning name it; fix the cause (disk space, permissions) and run `--clean`. The missing `sales` executable is expected and isn't reported. || A space in `HOME` or `ACAS_BUILD_DIR` | The vendor scripts can't handle spaces. Use paths without spaces. |
| `ACAS: command not found` | Open a new terminal (or `exec bash` / `exec zsh`) so the settings load. |
| Garbled screen | Terminal is smaller than 80×24. Enlarge it. |
| `Printer or class does not exist` | Expected without a CUPS printer. Everything except printing works. |
| `lpr: not found`, then `Segmentation fault` in `sl070` at the end of the first launch | You answered `Y` to "printed copy" and there's no `lpr`. The parameters are already saved: run `ACAS` again. |
| `fh-logger.txt` appears in `~/ACAS` | The maintainer ships with file-access logging switched on for testing (`common/fhlogger.cbl`). It's a file-access log, not accounting data (see the 2020-06-23 note in `README`). |

Hand-fix for the PATH error (WSL/Linux):

```bash
cp ~/.bashrc ~/.bashrc.bak
sed -i 's|^export PATH=~/bin:\.:.*$|export PATH="$HOME/bin:.:$PATH"|' ~/.bashrc
exec bash
```
