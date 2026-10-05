# Running ACAS v3.3

[`setup-acas.sh`](setup-acas.sh) installs the compiler, builds ACAS (COBOL files only, no database) and installs it. It copies the sources to `~/cobolsrc/ACAS` and builds there, so this repo is left untouched. You run it **once**; after that you only need the two commands under [Start ACAS](#start-acas).

| System | How | Status |
|---|---|---|
| Windows 10/11 | Inside **WSL2 Ubuntu** (the build scripts are bash) | Tested on Ubuntu 26.04 + GnuCOBOL 3.2.0 |
| Debian / Ubuntu | Directly | Same path as WSL; tested there |
| macOS | Homebrew | Install logic simulated on Linux; **not yet run on a real Mac** |
| Other Linux (Fedora, Arch, …) | Install the packages yourself, then `SKIP_DEPS=1` | Untested |

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

1. Install [Homebrew](https://brew.sh). The script starts `xcode-select --install` for you if the Command Line Tools are missing; if it does, let that finish and re-run.
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

The first run asks for the system parameters (Enter or Tab = next field, Esc = quit):

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
| Print parameters at the end | `N` (no printer) |

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
| `ACAS: command not found` | Open a new terminal (or `exec bash` / `exec zsh`) so the settings load. |
| Garbled screen | Terminal is smaller than 80×24. Enlarge it. |
| `Printer or class does not exist` | Expected without a CUPS printer. Everything except printing works. |
| `fh-logger.txt` appears in `~/ACAS` | The maintainer ships with file-access logging switched on for testing (`common/fhlogger.cbl`). It's a file-access log, not accounting data (see the 2020-06-23 note in `README`). |

Hand-fix for the PATH error (WSL/Linux):

```bash
cp ~/.bashrc ~/.bashrc.bak
sed -i 's|^export PATH=~/bin:\.:.*$|export PATH="$HOME/bin:.:$PATH"|' ~/.bashrc
exec bash
```
