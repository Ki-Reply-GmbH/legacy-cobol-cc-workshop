#!/usr/bin/env bash
# =============================================================================
# setup-acas.sh - build and install ACAS v3.3 (COBOL-files-only, no RDBMS)
# =============================================================================
#
# Repeats the steps that got ACAS building and installing on Windows (WSL2
# Ubuntu), and adds a macOS path. It leaves this source tree untouched: it
# copies the sources to a separate build directory and builds there.
#
# -----------------------------------------------------------------------------
# WINDOWS (tested: WSL2 + Ubuntu)
# -----------------------------------------------------------------------------
# 1. One time, in PowerShell run as Administrator:
#        wsl --install -d Ubuntu
#    Reboot if asked. Open "Ubuntu" from the Start menu and create your
#    Linux username and password when prompted.
# 2. In the Ubuntu terminal, run this script from its Windows location, e.g.:
#        bash /mnt/c/Users/<you>/Documents/Projects/Code-v3.3/setup-acas.sh
#    Enter your Linux password when sudo asks for it (package install). If
#    GnuCOBOL 3.x is already installed and works, no password is needed.
#
# -----------------------------------------------------------------------------
# macOS (install logic simulated on Linux; not yet run on a real Mac)
# -----------------------------------------------------------------------------
# 1. Install Homebrew first (https://brew.sh): it does NOT come with macOS, and
#    this script never installs it for you. The Xcode Command Line Tools are
#    different: the script starts `xcode-select --install` if they're missing.
# 2. From the repo root in Terminal:
#        bash ./setup-acas.sh
#    Differences from Windows/WSL that the script handles:
#    - Packages come from Homebrew (`brew install gnucobol`); zlib comes with
#      the Command Line Tools.
#    - GnuCOBOL on macOS may build modules as .dylib instead of .so. The
#      vendor install scripts hard-code .so, so on macOS this script does
#      the install step itself.
#    - The default shell is zsh, which doesn't read ~/.bashrc, so the env
#      vars go into ~/.zshrc (or ~/.bash_profile if your shell is bash).
#    - APFS is usually case-insensitive, so the fixed build script written
#      below replaces the broken comp-common-No-rdbms.sh in the build copy.
#      That's fine: it's the file the build calls either way.
#
# -----------------------------------------------------------------------------
# OPTIONS
# -----------------------------------------------------------------------------
#   --check              change nothing: report what is ready and what is missing
#                        (package manager, sudo, GnuCOBOL, disk space), then exit
#   --clean              delete a build directory this script created earlier,
#                        then rebuild
#   ACAS_BUILD_DIR=path  build directory (default: ~/cobolsrc/ACAS; no spaces)
#   SKIP_DEPS=1          don't install packages (you installed them yourself)
#   ACAS_NO_JAVA=1       don't install the JDK 17 and python3 that the workshop's bonus
#                        Java step (step 16) needs; SKIP_DEPS=1 skips them too
#   ACAS_NO_SEED=1       don't pre-fill ~/ACAS: the first launch shows ACAS's own
#                        set-up screens instead (see "Start-up data" below)
#
# -----------------------------------------------------------------------------
# WHAT THE SCRIPT CHECKS (and what it does not do)
# -----------------------------------------------------------------------------
#   - It installs packages only when it must: if GnuCOBOL 3.x is already there
#     and compiles a small screen program, the package step is skipped, so no
#     sudo or network is needed.
#   - Debian/Ubuntu: uses apt-get (always present there). Other Linux: stops
#     and says what to install; then re-run with SKIP_DEPS=1.
#   - macOS: needs Homebrew, which it does not install (see above).
#   - Separately, and never fatal: if a JDK 17 (javac, or $JAVA_HOME/bin/javac) or
#     python3 is missing, it installs openjdk-17-jdk-headless and python3 with
#     apt-get, for the workshop's bonus Java step. ACAS itself needs neither. A
#     failure (no sudo, no network, no package) only prints a warning with the
#     manual command. On macOS this is not automated: it prints the brew command.
#   - Run it as your normal user, not with sudo: it asks for sudo itself.
#   - After installing, it runs a test program that loads maps04 from ~/bin.
#
# -----------------------------------------------------------------------------
# START-UP DATA (seed/)
# -----------------------------------------------------------------------------
#   On a fresh install (no ~/ACAS/system.dat yet) it copies seed/system.dat,
#   analysis.dat and value.dat into ~/ACAS, so ACAS opens straight on its main
#   menu instead of the set-up screens: company "ACAS Workshop", financial year
#   2026, the default analysis codes. ACAS wrote those files itself (made with
#   seed/make-seed.py, answers in seed/README.md). If python3 is available, it
#   first runs ACAS against them in a temporary folder, and installs nothing if
#   that fails. Existing ACAS data is never overwritten. ACAS_NO_SEED=1 skips it.
#
# -----------------------------------------------------------------------------
# FIXES APPLIED TO THE BUILD COPY (upstream v3.3 problems found in the session)
# -----------------------------------------------------------------------------
# 1. comp-all-no-rdbms.sh calls common/comp-common-no-rdbms.sh, which doesn't
#    exist upstream. The only similar file, comp-common-No-rdbms.sh, is
#    marked "DO NOT USE" by its author and compiles dummy-rdbms.cbl, which
#    doesn't exist either (the stub is dummy-rdbmsMT.cbl). The script writes
#    a corrected comp-common-no-rdbms.sh, based on the working
#    comp-common-no-rdbms-diags.sh without its debug flags.
# 2. The build links -lz, so the zlib dev package is required.
# 3. CRLF line endings are stripped from *.sh and execute bits restored, in
#    case the sources came from a Windows checkout.
#
# -----------------------------------------------------------------------------
# AFTER THE SCRIPT FINISHES
# -----------------------------------------------------------------------------
#   - Open a NEW terminal (or run `exec bash` / `exec zsh`) to load the env vars.
#   - Make the terminal at least 80 columns x 24 lines.
#   - Run:  cd ~/ACAS && ACAS
#     (irs, stock, purchase and general also run directly by name; Sales has
#     no standalone executable in this build, so open it from the ACAS menu)
#   - With the start-up data installed, ACAS opens on its main menu. Settings
#     can be changed later with Z (System Setup), except the company name.
#   - Without it (ACAS_NO_SEED=1), the first run opens the System Parameter
#     set-up (manual chapter 19); RUNNING.md lists the answers. Known upstream
#     bug: right after those screens ACAS.cbl calls sl070 with too few
#     arguments and ACAS crashes. The settings are saved by then, so start it
#     again; seed/README.md has the details.
# =============================================================================
[ -n "${BASH_VERSION:-}" ] || { echo "Run this script with bash:  bash $0" >&2; exit 1; }
set -eu

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER=".acas-build-copy"
CLEAN=0
CHECK=0
MIN_MB=200            # the build copy plus the install need about 45 MB; keep a margin

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    --check) CHECK=1 ;;
    -h|--help) awk 'NR > 1 { if (/^#/) print; else exit }' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# SKIP_DEPS=1, yes or true all mean "don't install packages".
case "$(printf '%s' "${SKIP_DEPS:-0}" | tr 'A-Z' 'a-z')" in
  ""|0|no|false|off) SKIP_DEPS=0 ;;
  *)                 SKIP_DEPS=1 ;;
esac

# Temp files: ACAS's own shell settings point TMPDIR at ~/tmp, which may have been
# deleted since. cobc also needs a working TMPDIR, so repair it before anything else.
if [ -n "${TMPDIR:-}" ]; then
  case "$TMPDIR" in *[[:space:]]*) TMPDIR="" ;; esac
fi
if [ -n "${TMPDIR:-}" ] && [ ! -d "$TMPDIR" ]; then mkdir -p "$TMPDIR" 2>/dev/null || TMPDIR=""; fi
if [ -n "${TMPDIR:-}" ] && [ ! -w "$TMPDIR" ]; then TMPDIR=""; fi
export TMPDIR="${TMPDIR:-/tmp}"
TEMP_DIRS=""
cleanup() { if [ -n "$TEMP_DIRS" ]; then rm -rf $TEMP_DIRS; fi; }
trap cleanup EXIT
trap 'exit 130' INT     # Ctrl-C: exit through the EXIT trap so temp dirs are removed
trap 'exit 143' TERM
# Sets NEW_TEMP (not echoed: a $(...) subshell would lose the TEMP_DIRS update).
new_temp_dir() { NEW_TEMP="$(mktemp -d "$TMPDIR/acas-$1.XXXXXX")" || return 1; TEMP_DIRS="$TEMP_DIRS $NEW_TEMP"; }

# --- 0. Where and as whom are we running? ------------------------------------
OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  MINGW*|MSYS*|CYGWIN*) die "This is Windows ($OS). ACAS builds on Linux: open the Ubuntu (WSL) app from the Start menu and run this script there. See RUNNING.md." ;;
  *) die "Unsupported OS '$OS'. ACAS builds on Linux, macOS, or Windows through WSL." ;;
esac

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  die "Don't run this with sudo: ACAS would be installed into root's home and you couldn't start it. Run it as yourself (bash $0); it asks for sudo only when it has to install packages."
fi
[ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ] || die "HOME is not a writable directory ('${HOME:-unset}'). ACAS installs into your home directory."

BUILD_DIR="${ACAS_BUILD_DIR:-$HOME/cobolsrc/ACAS}"
case "$BUILD_DIR" in
  "~")  BUILD_DIR="$HOME" ;;
  "~/"*) BUILD_DIR="$HOME/${BUILD_DIR:2}" ;;     # a quoted "~/x" isn't expanded by the shell
esac
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$PWD/$BUILD_DIR" ;; esac
while [ "$BUILD_DIR" != "/" ] && [ "${BUILD_DIR%/}" != "$BUILD_DIR" ]; do BUILD_DIR="${BUILD_DIR%/}"; done
case "$HOME|$BUILD_DIR" in
  *[[:space:]]*) die "A space in '$HOME' or '$BUILD_DIR' would break the vendor build and install scripts. Use a home directory and ACAS_BUILD_DIR without spaces." ;;
esac

[ -f "$SRC_DIR/comp-all-no-rdbms.sh" ] || die "Run this from the ACAS source tree (comp-all-no-rdbms.sh not found in $SRC_DIR)."

# The build directory gets deleted by --clean, so it must never be the sources, home or /.
real_path() { if [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s\n' "$1"; fi; }
SRC_REAL="$(real_path "$SRC_DIR")"; BUILD_REAL="$(real_path "$BUILD_DIR")"; HOME_REAL="$(real_path "$HOME")"
[ ! -f "$SRC_DIR/$MARKER" ] || die "This is the copy of setup-acas.sh inside a build directory ($SRC_DIR). Run the one in your clone of the repository instead."
case "$BUILD_REAL" in
  /|"$HOME_REAL"|"$SRC_REAL") die "ACAS_BUILD_DIR must be a directory of its own, not '$BUILD_DIR'." ;;
esac
case "$SRC_REAL/" in
  "$BUILD_REAL"/*) die "ACAS_BUILD_DIR ('$BUILD_DIR') contains the sources, and --clean would delete them. Choose another directory." ;;
esac

# --- 1. Helpers: GnuCOBOL, sudo, package managers ----------------------------
# LC_ALL=C wherever output is parsed: translated messages would break the parsing.
cobc_version() { LC_ALL=C cobc --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true; }

# Compile and link a small screen program the way the ACAS build does, then run it.
# This catches a missing C compiler, zlib or curses support, or a libcob that
# can't be loaded at run time, in a second instead of 90 seconds into the build.
SMOKE_STAGE=""
cobol_smoke() {
  local d out
  SMOKE_STAGE="temp"; SMOKE_LOG="couldn't create a temporary directory in $TMPDIR"
  new_temp_dir smoke || return 1
  d="$NEW_TEMP"
  cat > "$d/smoke.cbl" << 'EOS'
       >>source free
 identification division.
 program-id. smoke.
 data division.
 working-storage section.
 copy "screenio.cpy".
 procedure division.
     if 1 = 2
        display "never shown" at 0101
     end-if
     display "SMOKE-OK"
     goback.
EOS
  SMOKE_STAGE="compile"
  if ! (cd "$d" && cobc -x -lz smoke.cbl -o smoke) > "$d/log" 2>&1; then
    SMOKE_LOG="$(tail -n 6 "$d/log")"; return 1
  fi
  SMOKE_STAGE="run"
  out="$(cd "$d" && ./smoke 2>&1)" || true
  case "$out" in *SMOKE-OK*) SMOKE_STAGE="ok"; return 0 ;; esac
  SMOKE_LOG="$out"; return 1
}

# True when cobc is a usable 3.x or later. Sets COBOL_WHY when it isn't.
COBOL_WHY=""
SMOKE_LOG=""
have_cobol() {
  COBOL_WHY=""
  if ! command -v cobc >/dev/null 2>&1; then COBOL_WHY="cobc (GnuCOBOL) is not on PATH."; return 1; fi
  case "$(cobc_version)" in
    3.*|[4-9].*) ;;
    *) COBOL_WHY="cobc $(cobc_version) is too old: GnuCOBOL 3.x is required (3.2 recommended by the ACAS manual)."; return 1 ;;
  esac
  if ! cobol_smoke; then
    case "$SMOKE_STAGE" in
      run) COBOL_WHY="cobc compiles, but the compiled test program doesn't run (the GnuCOBOL runtime libcob can't be loaded? after building GnuCOBOL from source, run 'sudo ldconfig'). It said: $SMOKE_LOG" ;;
      temp) COBOL_WHY="$SMOKE_LOG" ;;
      *) COBOL_WHY="cobc is installed but can't compile and link a small test program (a C compiler, or the zlib or ncurses development files, may be missing). cobc said: $SMOKE_LOG" ;;
    esac
    return 1
  fi
}

# Homebrew isn't on PATH in some shells (Apple Silicon: /opt/homebrew, Intel: /usr/local).
find_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; command -v brew >/dev/null 2>&1 && return 0; fi
  done
  return 1
}

# sudo asks for the password on /dev/tty, not on stdin, so "is there a terminal"
# means "can /dev/tty be opened" (stdin may be redirected while a terminal exists).
has_tty() { [ -t 0 ] && return 0; { : < /dev/tty; } 2>/dev/null; }

# root | passwordless | prompt | noterminal | none
sudo_mode() {
  if [ "$(id -u)" -eq 0 ]; then echo root
  elif ! command -v sudo >/dev/null 2>&1; then echo none
  elif sudo -n true >/dev/null 2>&1; then echo passwordless
  elif has_tty; then echo prompt
  else echo noterminal
  fi
}

free_mb() { df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }'; }
# The nearest directory that exists on the way to $1 (the build dir may not exist yet).
existing_parent() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; printf '%s\n' "$d"; }
# True (and DISK_MSG set) when ~ or the build directory's disk has less than MIN_MB free.
# They can be different disks when ACAS_BUILD_DIR points elsewhere.
DISK_MSG=""
disk_short() {
  local where mb
  for where in "$HOME" "$(existing_parent "$BUILD_DIR")"; do
    mb="$(free_mb "$where")"
    if [ -n "$mb" ] && [ "$mb" -lt "$MIN_MB" ]; then
      DISK_MSG="Only $mb MB free on the disk holding $where; the build needs about $MIN_MB MB."
      return 0
    fi
  done
  return 1
}

# Start-up data copied into a fresh ~/ACAS (see "START-UP DATA" above).
SEED_DIR="$SRC_DIR/seed"
SEED_FILES="system.dat analysis.dat value.dat"
# off | kept | missing | ready
seed_plan() {
  local f
  case "$(printf '%s' "${ACAS_NO_SEED:-0}" | tr 'A-Z' 'a-z')" in
    ""|0|no|false|off) ;;
    *) echo off; return 0 ;;
  esac
  if [ -f "$HOME/ACAS/system.dat" ]; then echo kept; return 0; fi
  for f in $SEED_FILES SHA256SUMS; do
    if [ ! -f "$SEED_DIR/$f" ]; then echo missing; return 0; fi
  done
  echo ready
}
# Without python3 this is the only check: the files must match seed/SHA256SUMS.
# Returns 0 (match), 1 (mismatch, SEED_MSG says which), 2 (no checksum tool).
SEED_MSG=""
seed_checksums() {
  local tool line want name got
  if command -v sha256sum >/dev/null 2>&1; then tool="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then tool="shasum -a 256"
  else return 2; fi
  while read -r want name; do
    [ -n "$name" ] || continue
    got="$($tool "$SEED_DIR/${name#\*}" 2>/dev/null | awk '{ print $1 }')"
    if [ "$got" != "$want" ]; then SEED_MSG="seed/${name#\*} doesn't match seed/SHA256SUMS"; return 1; fi
  done < "$SEED_DIR/SHA256SUMS"
  return 0
}

PKG_LIST="GnuCOBOL 3.x, a C compiler and make, and the development packages for Berkeley DB, ncurses and zlib"
other_manager() { local m; for m in dnf yum pacman zypper apk emerge; do command -v "$m" >/dev/null 2>&1 && { echo "$m"; return 0; }; done; return 0; }
no_apt_message() {
  local m; m="$(other_manager)"
  printf "This Linux has no apt-get%s, and only Debian/Ubuntu are automated. Install %s yourself (package names differ by distro), then re-run with:  SKIP_DEPS=1 bash %s" \
    "${m:+ (found: $m)}" "$PKG_LIST" "$0"
}

# The unversioned 'gnucobol' package is not always the 3.x line (on Ubuntu 26.04 it
# isn't), so prefer gnucobol3 and verify the version after installing.
pick_cobol_pkg() {
  local p c
  for p in gnucobol3 gnucobol; do
    c="$(LC_ALL=C apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')"
    if [ -n "$c" ] && [ "$c" != "(none)" ]; then echo "$p"; return 0; fi
  done
  return 0
}

SUDO=""
apt_get() { $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 "$@"; }

install_deps_linux() {
  local pkg
  command -v apt-get >/dev/null 2>&1 || die "$(no_apt_message)"
  case "$(sudo_mode)" in
    root)          SUDO="" ;;
    passwordless)  SUDO="sudo" ;;
    prompt)        SUDO="sudo"; echo "sudo will ask for your password to install packages."
                   # Ask once, up front: a wrong password or a user who isn't allowed to
                   # use sudo would otherwise surface as a confusing apt-get failure.
                   sudo -v || die "sudo didn't accept the password, or you aren't allowed to use sudo on this machine. Ask an administrator to install $PKG_LIST, then re-run with:  SKIP_DEPS=1 bash $0" ;;
    none)          die "Packages are missing, and you aren't root and sudo isn't installed. Ask an administrator to install $PKG_LIST, then re-run with:  SKIP_DEPS=1 bash $0" ;;
    noterminal)    die "Packages are missing, and sudo needs a password but there's no terminal to ask in (a pipe, CI or a script?). Run this from a terminal, or install $PKG_LIST yourself and re-run with:  SKIP_DEPS=1 bash $0" ;;
  esac
  apt_get update || warn "apt-get update failed (often a broken third-party repository). Trying the install with the package lists you already have."
  pkg="$(pick_cobol_pkg)"
  [ -n "$pkg" ] || die "No GnuCOBOL package ('gnucobol3' or 'gnucobol') in your apt sources. Install GnuCOBOL 3.x another way (https://gnucobol.sourceforge.io), then re-run with:  SKIP_DEPS=1 bash $0"
  echo "Installing $pkg and its build dependencies."
  apt_get install -y "$pkg" libdb-dev libncurses-dev zlib1g-dev build-essential \
    || die "apt-get couldn't install the packages (its message is above). With no network or no admin rights, install '$pkg libdb-dev libncurses-dev zlib1g-dev build-essential' another way, then re-run with:  SKIP_DEPS=1 bash $0"
}

homebrew_message() {
  printf 'Homebrew was not found. It does not come with macOS, and this script does not install it for you. Install it from https://brew.sh (one command, pasted into Terminal), open a NEW Terminal, then re-run this script.'
}

install_deps_macos() {
  xcode-select -p >/dev/null 2>&1 || { xcode-select --install || true; die "Finish installing the Xcode Command Line Tools (a window just opened), then re-run this script."; }
  find_brew || die "$(homebrew_message)"
  brew install gnucobol || die "'brew install gnucobol' failed (its message is above). Fix that (network? 'brew doctor'), then re-run."
}

# Tools for the workshop's bonus Java step (maps module to Java): a JDK 17 or later
# and python3. ACAS itself needs neither, so installing them never stops the build:
# every failure below is a warning that says how to install them by hand.
JDK_PKG="openjdk-17-jdk-headless"
javac_path() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then echo "$JAVA_HOME/bin/javac"
  else command -v javac 2>/dev/null || true; fi
}
# Major version of the JDK that build-maps09.sh would use ("javac 17.0.20" -> 17); empty if none.
java_major() {
  local j; j="$(javac_path)"
  [ -n "$j" ] || return 0
  LC_ALL=C "$j" -version 2>&1 | grep -oE '[0-9]+' | head -n1 || true
}
have_jdk() { local v; v="$(java_major)"; [ -n "$v" ] && [ "$v" -ge 17 ]; }
have_python() { command -v python3 >/dev/null 2>&1; }
# off | ready | install
tools_plan() {
  case "$(printf '%s' "${ACAS_NO_JAVA:-0}" | tr 'A-Z' 'a-z')" in
    ""|0|no|false|off) ;;
    *) echo off; return 0 ;;
  esac
  [ "${SKIP_DEPS:-0}" = "1" ] && { echo off; return 0; }
  if have_jdk && have_python; then echo ready; else echo install; fi
}
tools_missing() {
  local m=""
  have_jdk || m="a JDK 17"
  have_python || m="${m:+$m and }python3"
  printf '%s' "$m"
}
tools_manual() {
  if [ "$OS" = "Darwin" ]; then
    printf "Install what is missing yourself: brew install openjdk@17 (then set JAVA_HOME to \$(brew --prefix openjdk@17)). python3 comes with the Xcode Command Line Tools."
  else
    printf "Install what is missing yourself: sudo apt-get install -y %s python3 (or set ACAS_NO_JAVA=1 to skip this step if you won't do the bonus Java step)." "$JDK_PKG"
  fi
}

install_tools() {
  local pkgs="" cand
  step "Installing the tools for the bonus Java step ($(tools_missing))"
  if [ "$OS" = "Darwin" ]; then
    warn "Not automated on macOS (Homebrew's JDK is keg-only and needs JAVA_HOME). $(tools_manual)"
    return 0
  fi
  command -v apt-get >/dev/null 2>&1 || { warn "No apt-get here. $(tools_manual)"; return 0; }
  have_jdk || pkgs="$JDK_PKG"
  have_python || pkgs="${pkgs:+$pkgs }python3"
  case "$(sudo_mode)" in
    root)          SUDO="" ;;
    passwordless)  SUDO="sudo" ;;
    prompt)        SUDO="sudo"; echo "sudo will ask for your password to install: $pkgs"
                   sudo -v || { warn "sudo didn't accept the password, or you aren't allowed to use sudo. $(tools_manual)"; return 0; } ;;
    *)             warn "Can't use sudo here (not installed, or no terminal to ask for a password). $(tools_manual)"; return 0 ;;
  esac
  apt_get update || warn "apt-get update failed. Trying the install with the package lists you already have."
  if ! have_jdk; then
    cand="$(LC_ALL=C apt-cache policy "$JDK_PKG" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')"
    if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
      warn "No $JDK_PKG package in your apt sources. Install a JDK 17 another way and set JAVA_HOME."
      pkgs="${pkgs#$JDK_PKG}"; pkgs="${pkgs# }"
    fi
  fi
  if [ -n "$pkgs" ]; then
    # shellcheck disable=SC2086   # $pkgs is a short list of package names
    apt_get install -y $pkgs || { warn "apt-get couldn't install $pkgs (its message is above). $(tools_manual)"; return 0; }
  fi
  if have_jdk; then echo "JDK $(java_major) is ready ($(javac_path))."; else warn "A JDK 17 is still missing. $(tools_manual)"; fi
  if have_python; then echo "$(python3 --version 2>&1) is ready."; else warn "python3 is still missing. $(tools_manual)"; fi
}

# --- 1a. --check: report, change nothing -------------------------------------
PROBLEMS=0
ok()   { printf '  [ok] %s\n' "$*"; }
bad()  { printf '  [!!] %s\n' "$*"; PROBLEMS=$((PROBLEMS + 1)); }
note() { printf '  [..] %s\n' "$*"; }

run_check() {
  local where mb cols lines
  step "Checking this machine (nothing is changed)"
  where="$OS $(uname -m)"
  if [ "$OS" = "Linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then where="$where, Windows Subsystem for Linux"; fi
  ok "System: $where"

  if have_cobol; then
    ok "GnuCOBOL $(cobc_version) is installed, compiles and runs a test program, so no packages are needed"
  else
    note "$COBOL_WHY"
    if [ "${SKIP_DEPS:-0}" = "1" ]; then
      bad "SKIP_DEPS=1 is set, so the script won't install anything, and GnuCOBOL isn't usable."
    elif [ "$OS" = "Linux" ]; then
      if ! command -v apt-get >/dev/null 2>&1; then
        bad "$(no_apt_message)"
      else
        case "$(sudo_mode)" in
          root)          ok "Will install GnuCOBOL and build tools with apt-get (you are root)" ;;
          passwordless)  ok "Will install GnuCOBOL and build tools with apt-get (sudo works without a password)" ;;
          prompt)        ok "Will install GnuCOBOL and build tools with apt-get; sudo will ask for your password" ;;
          none)          bad "Packages are missing, and you aren't root and sudo isn't installed. Ask an administrator to install $PKG_LIST." ;;
          noterminal)    bad "Packages are missing, and sudo needs a password but there's no terminal to ask in. Run this from a terminal." ;;
        esac
      fi
    else
      xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools are installed" || note "Xcode Command Line Tools are missing: the script will start their installer, then ask you to re-run it"
      if find_brew; then ok "Homebrew found: will run 'brew install gnucobol'"; else bad "$(homebrew_message)"; fi
    fi
  fi

  case "$(tools_plan)" in
    ready)   ok "JDK $(java_major) and $(python3 --version 2>&1) are installed (bonus Java step)" ;;
    off)     note "Bonus Java step: ACAS_NO_JAVA or SKIP_DEPS is set, so a JDK 17 and python3 won't be installed" ;;
    install) note "Bonus Java step: $(tools_missing) is missing; the script will try to install it (a failure there is only a warning, ACAS still builds)" ;;
  esac
  if disk_short; then bad "$DISK_MSG"; else ok "Disk space: enough free for the build directory and ~/bin"; fi
  if [ -e "$BUILD_DIR" ]; then note "$BUILD_DIR already exists: add --clean to rebuild it"; else ok "Build directory $BUILD_DIR is free"; fi
  if [ -f "$HOME/bin/ACAS" ]; then note "ACAS is already installed in ~/bin"; fi
  case "$(seed_plan)" in
    ready)   ok "Start-up data: ~/ACAS will be pre-filled from seed/, so ACAS opens on its main menu"
             command -v python3 >/dev/null 2>&1 || note "python3 isn't installed: the start-up data will be installed without being tested against your build first" ;;
    kept)    note "~/ACAS/system.dat exists: your ACAS settings and data will be kept as they are" ;;
    off)     note "ACAS_NO_SEED is set: the first launch will show ACAS's set-up screens" ;;
    missing) note "seed/ is incomplete ($SEED_FILES SHA256SUMS): the first launch will show ACAS's set-up screens" ;;
  esac
  cols="$(tput cols 2>/dev/null || echo 0)"; lines="$(tput lines 2>/dev/null || echo 0)"
  if [ "$cols" -ge 80 ] && [ "$lines" -ge 24 ]; then ok "Terminal is ${cols}x${lines} (ACAS needs at least 80x24)"; else note "Terminal is ${cols}x${lines}; ACAS needs at least 80x24 to run"; fi

  printf '\n'
  if [ "$PROBLEMS" -eq 0 ]; then echo "Ready. Run:  bash $0"; else echo "$PROBLEMS problem(s) marked [!!] above. Fix them, then run this check again."; fi
  [ "$PROBLEMS" -eq 0 ]
}
if [ "$CHECK" = "1" ]; then run_check; exit $?; fi

# --- 1b. Dependencies --------------------------------------------------------
if disk_short; then die "$DISK_MSG"; fi

step "Checking build dependencies"
if have_cobol; then
  echo "GnuCOBOL $(cobc_version) is installed, compiles and runs a test program: no packages to install."
elif [ "${SKIP_DEPS:-0}" = "1" ]; then
  die "SKIP_DEPS=1 is set, but GnuCOBOL isn't usable. $COBOL_WHY"
else
  echo "$COBOL_WHY"
  step "Installing build dependencies"
  if [ "$OS" = "Linux" ]; then install_deps_linux; else install_deps_macos; fi
  have_cobol || die "The packages installed, but GnuCOBOL still isn't usable. $COBOL_WHY"
fi

echo "Using: $(cobc --version | head -n1)"
case "$(cobc_version)" in
  3.0*|3.1*) warn "ACAS v3.3 is built and tested with GnuCOBOL 3.2; this version may fail to build. Your system's package is the newest apt offers; for 3.2 see https://gnucobol.sourceforge.io" ;;
  [4-9].*)   warn "GnuCOBOL $(cobc_version) isn't the 3.x line ACAS v3.3 is built and tested with; the build may fail." ;;
esac

# A JDK 17 and python3 for the workshop's bonus Java step. Never fatal.
if [ "$(tools_plan)" = "install" ]; then install_tools; fi

# --- 2. Copy sources to the build directory ----------------------------------
step "Preparing build directory: $BUILD_DIR"
if [ -e "$BUILD_DIR" ]; then
  if [ "$CLEAN" = "1" ] && [ -f "$BUILD_DIR/$MARKER" ]; then
    rm -rf "$BUILD_DIR"
  elif [ "$CLEAN" = "1" ]; then
    die "$BUILD_DIR wasn't created by this script (no $MARKER), so it won't be deleted. Remove it yourself or set ACAS_BUILD_DIR."
  else
    die "$BUILD_DIR already exists. Re-run with --clean to rebuild it, or set ACAS_BUILD_DIR."
  fi
fi
mkdir -p "$BUILD_DIR" 2>/dev/null || die "Can't create $BUILD_DIR (no permission?). Set ACAS_BUILD_DIR to a directory you can write to."
touch "$BUILD_DIR/$MARKER"
# Copy only what the build uses (top-level scripts and the six source dirs), so
# manuals, workshop material and anything else in the repo stay out of the build.
for d in common copybooks general irs purchase sales stock; do
  [ -d "$SRC_DIR/$d" ] || die "Source directory missing: $SRC_DIR/$d"
  cp -R "$SRC_DIR/$d" "$BUILD_DIR/"
done
# Optional: java/ exists only in a checkout where maps09 was moved to Java.
if [ -d "$SRC_DIR/java" ]; then cp -R "$SRC_DIR/java" "$BUILD_DIR/"; fi
cp "$SRC_DIR"/*.sh "$BUILD_DIR/"

step "Normalising shell scripts (LF endings, execute bit)"
# tr instead of perl or sed -i, which differ between Linux and macOS or may be missing.
find "$BUILD_DIR" -name '*.sh' -type f -print0 | while IFS= read -r -d '' f; do
  tr -d '\r' < "$f" > "$f.lf" && cat "$f.lf" > "$f" && rm -f "$f.lf"
done
find "$BUILD_DIR" -name '*.sh' -type f -exec chmod +x {} +

# --- 3. Fix the missing no-RDBMS common build script -------------------------
step "Writing corrected common/comp-common-no-rdbms.sh"
cat > "$BUILD_DIR/common/comp-common-no-rdbms.sh" << 'EOF'
#!/bin/bash
cobc -m dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz
echo "Compiled dummy-rdbmsMT entry points"

cobc -m -lz ACAS-Sysout.cbl -I ../copybooks -Wlinkage; echo "Compiled ACAS-Sysout"

cp -vf dummy-rdbmsMT.* ../stock
cp -vf dummy-rdbmsMT.* ../sales
cp -vf dummy-rdbmsMT.* ../purchase
cp -vf dummy-rdbmsMT.* ../irs
cp -vf dummy-rdbmsMT.* ../general
echo "Copied dummy-rdbmsMT.so to irs, general, purchase, sales, stock dirs."

for i in `ls maps0*.cbl`; do cobc -m -lz $i -I ../copybooks -Wlinkage; echo "Compiled " $i; done
echo "compiled all maps"

for i in `ls acas0*.cbl`; do cobc -m $i dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz; echo "Compiled " $i; done
for i in `ls acasirsub*.cbl`; do cobc -m $i dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz; echo "Compiled " $i; done
cobc -m acas-get-params.cbl -I ../copybooks -Wlinkage -lz
echo "Compiled acas-get-params"
echo "Compiled all acas*"

cobc -m fhlogger.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz
echo "Compiled fhlogger"

cobc -m xl150.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz
cobc -m sys002.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz
echo "compiled xl150 & sys002"

cobc -x ACAS.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz
echo "Compiled ACAS.cbl"

for i in `ls *UNL.cbl`; do cobc -x $i -Wlinkage -lz -I ../copybooks; done
echo "Compiled *UNL.cbl"

for i in `ls *RES.cbl`; do cobc -x $i -Wlinkage -lz -I ../copybooks; done
echo "Compiled *RES.cbl"

echo "Compiled for No RDBMS"
exit 0
EOF
chmod +x "$BUILD_DIR/common/comp-common-no-rdbms.sh"

# --- 4. Build ----------------------------------------------------------------
BUILD_LOG="$BUILD_DIR/build.log"
step "Building ACAS (no RDBMS). This takes a while; log: $BUILD_LOG"
(cd "$BUILD_DIR" && bash comp-all-no-rdbms.sh) 2>&1 | tee "$BUILD_LOG"

# The vendor scripts print "Compiled ..." whether or not cobc succeeded, so check the log.
# "_FORTIFY_SOURCE redefined" warnings are harmless and aren't matched here.
if grep -nE 'error:|cannot find|No such file|Permission denied|command not found|No space left' "$BUILD_LOG"; then
  die "The build reported the errors above. Fix them and re-run with --clean."
fi

# Only in a checkout where maps09 was moved to Java (a thin COBOL bridge plus
# java/maps09 and common/build-maps09.sh): the vendor scripts build just the
# bridge, so build the JNI shim and jar next to it. Needs a JDK 17. A normal
# checkout has neither file and skips this.
if [ -f "$BUILD_DIR/common/build-maps09.sh" ] && [ -d "$BUILD_DIR/java/maps09" ]; then
  step "Building the Java part of maps09"
  (cd "$BUILD_DIR" && bash common/build-maps09.sh "$BUILD_DIR/common") 2>&1 | tee -a "$BUILD_LOG"
  [ -f "$BUILD_DIR/common/maps09.jar" ] || die "maps09 (Java) build failed: maps09.jar was not produced. See $BUILD_LOG"
fi

if [ -f "$BUILD_DIR/common/sys002.so" ]; then EXT=so
elif [ -f "$BUILD_DIR/common/sys002.dylib" ]; then EXT=dylib
else die "Build finished but common/sys002 (.so/.dylib) was not produced. See $BUILD_LOG"; fi
missing=""
# The no-RDBMS sales script builds only the sales.$EXT module (its `cobc -x`
# line is commented out upstream), so Sales is started from the ACAS menu.
for f in common/ACAS irs/irs general/general purchase/purchase stock/stock \
         "sales/sales.$EXT" "common/sys002.$EXT" "common/dummy-rdbmsMT.$EXT"; do
  [ -f "$BUILD_DIR/$f" ] || missing="$missing $f"
done
[ -z "$missing" ] || die "Build finished but these outputs are missing:$missing"
echo "Build OK (module extension: .$EXT)"

# --- 5. Install --------------------------------------------------------------
INSTALL_LOG="$BUILD_DIR/install.log"

env_block() {
  cat << 'EOF'

# ACAS (added by setup-acas.sh)
export COB_SCREEN_ESC=YES
export COB_SCREEN_EXCEPTIONS=YES
export COB_LIBRARY_PATH="$HOME/bin"
export COB_EXIT_WAIT=on
export PATH="$HOME/bin:.:$PATH"
export ACAS_LEDGERS="$HOME/ACAS"
export ACAS_BIN="$HOME/bin"
export TMPDIR="$HOME/tmp"
EOF
}
# Is ACAS configured in this start-up file? A commented-out line doesn't count.
has_env() { grep -qE '^[[:space:]]*export ACAS_LEDGERS=' "$1" 2>/dev/null; }
# Appends the ACAS environment variables to a shell start-up file, once. Never
# fatal: a read-only file gets a warning with the lines to add by hand.
add_env_block() {
  if has_env "$1"; then return 0; fi
  if { env_block >> "$1"; } 2>/dev/null; then
    echo "Added ACAS environment variables to $1"
  else
    warn "Couldn't write to $1. Add these lines to it yourself:$(env_block)"
  fi
}

if [ "$OS" = "Linux" ]; then
  # install-ACAS.sh appends env vars to ~/.bashrc every time it runs, so use
  # it only once. Later installs use install-ACAS-preinstalled.sh.
  if has_env "$HOME/.bashrc"; then
    INSTALLER=install-ACAS-preinstalled.sh
    mkdir -p "$HOME/bin" "$HOME/ACAS/temp-backups" "$HOME/ACAS/archives" "$HOME/tmp"
  else
    INSTALLER=install-ACAS.sh
  fi
  step "Installing into ~/bin with $INSTALLER"
  (cd "$BUILD_DIR" && bash "$INSTALLER") 2>&1 | tee "$INSTALL_LOG"
  # The vendor installer carries on after a failed mv. Its one expected complaint is
  # the Sales executable, which the no-RDBMS build doesn't make; report anything else.
  odd="$(grep -E "cannot (stat|access|move)|Permission denied|No space left" "$INSTALL_LOG" | grep -v "'sales'" || true)"
  [ -z "$odd" ] || warn "The installer reported problems (see $INSTALL_LOG):
$odd"
  # install-ACAS.sh writes PATH with the install-time $PATH expanded and unquoted.
  # Under WSL that includes Windows paths with spaces, which breaks the line.
  # Rewrite through 'cat >' rather than 'sed -i', which would turn a symlinked
  # ~/.bashrc (dotfile managers) into a plain file.
  if grep -q '^export PATH=~/bin:\.:' "$HOME/.bashrc" 2>/dev/null; then
    new_temp_dir rc && sed 's|^export PATH=~/bin:\.:.*$|export PATH="$HOME/bin:.:$PATH"|' "$HOME/.bashrc" > "$NEW_TEMP/bashrc" \
      && { cat "$NEW_TEMP/bashrc" > "$HOME/.bashrc"; } 2>/dev/null \
      || warn "Couldn't fix the PATH line in ~/.bashrc. Replace the line starting 'export PATH=~/bin:.:' with:  export PATH=\"\$HOME/bin:.:\$PATH\""
  fi
  # The installer appends to ~/.bashrc without checking; if that failed (read-only
  # file), say so instead of leaving ACAS without its settings.
  has_env "$HOME/.bashrc" || warn "The ACAS settings aren't in ~/.bashrc (it may be read-only). Add these lines to it yourself:$(env_block)"
  # The installer only writes ~/.bashrc. A zsh user would never see the variables.
  case "${SHELL:-}" in
    */zsh) add_env_block "$HOME/.zshrc" ;;
    */fish) warn "You use fish: set these in ~/.config/fish/config.fish yourself (see the end of ~/.bashrc for the list)." ;;
  esac
else
  step "Installing into ~/bin (macOS)"
  {
    mkdir -p "$HOME/bin" "$HOME/tmp" \
             "$HOME/ACAS/temp-backups" "$HOME/ACAS/archives" \
             "$HOME/ACAS-practice/temp-backups" "$HOME/ACAS-practice/archives"
    cp -fv "$BUILD_DIR"/acasbkup*.sh "$BUILD_DIR/common/masterLD.sh" "$HOME/bin/"
    for d in common irs general purchase sales stock; do
      find "$BUILD_DIR/$d" -maxdepth 1 -type f -name "*.$EXT" -exec cp -fv {} "$HOME/bin/" \;
    done
    for f in common/ACAS irs/irs general/general purchase/purchase stock/stock; do
      cp -fv "$BUILD_DIR/$f" "$HOME/bin/"
    done
    if [ -f "$BUILD_DIR/common/maps09.jar" ]; then cp -fv "$BUILD_DIR/common/maps09.jar" "$HOME/bin/"; fi
    chmod u+x "$HOME"/bin/*.sh
  } 2>&1 | tee "$INSTALL_LOG"

  case "${SHELL:-}" in
    */zsh) RC="$HOME/.zshrc" ;;
    *)     RC="$HOME/.bash_profile" ;;
  esac
  add_env_block "$RC"
fi

[ -f "$HOME/bin/ACAS" ] && [ -f "$HOME/bin/sys002.$EXT" ] || die "Install didn't put ACAS into ~/bin. See $INSTALL_LOG"

# --- 6. Prove the install works ----------------------------------------------
# Run a tiny program that loads maps04 from ~/bin, the way ACAS loads its modules at
# run time. It catches a wrong library path or an unloadable module now, not at the
# first ACAS launch.
step "Testing that ACAS modules load from ~/bin"
new_temp_dir verify || die "Couldn't create a temporary directory in $TMPDIR."
VERIFY_DIR="$NEW_TEMP"
cat > "$VERIFY_DIR/verify.cbl" << 'EOS'
       >>source free
 identification division.
 program-id. verify.
 data division.
 working-storage section.
 copy "wsmaps03.cob".
 procedure division.
     move "29-02-2028" to u-date.
     move zero to u-bin.
     call "maps04" using maps03-ws.
     if u-bin = zero or u-date not = "29/02/2028"
        display "VERIFY-FAILED"
     else
        display "VERIFY-OK"
     end-if.
     goback.
EOS
VERIFY_OUT=""
if (cd "$VERIFY_DIR" && cobc -x -I "$BUILD_DIR/copybooks" verify.cbl -o verify) > "$VERIFY_DIR/compile.log" 2>&1; then
  VERIFY_OUT="$(cd "$VERIFY_DIR" && COB_LIBRARY_PATH="$HOME/bin" ./verify 2>&1 || true)"
else
  VERIFY_OUT="(the test program didn't compile) $(tail -n 4 "$VERIFY_DIR/compile.log")"
fi
rm -rf "$VERIFY_DIR"
case "$VERIFY_OUT" in
  *VERIFY-OK*) echo "OK: maps04 was loaded from ~/bin and converted a date correctly." ;;
  *) die "ACAS was installed, but a test program couldn't use its modules from ~/bin. Output: $VERIFY_OUT" ;;
esac

# --- 7. Start-up data --------------------------------------------------------
# Pre-fill a fresh ~/ACAS so the first launch skips the set-up screens. Never
# fatal: if anything is wrong, ACAS just asks for its settings as it normally does.
step "Start-up data for ~/ACAS"
SEED_RESULT=screens
case "$(seed_plan)" in
  off)     echo "ACAS_NO_SEED is set: skipped. ACAS will ask for its settings on first launch." ;;
  kept)    echo "~/ACAS/system.dat already exists: your ACAS settings and data are kept as they are."
           SEED_RESULT=kept ;;
  missing) warn "seed/ in the repository is incomplete (needs $SEED_FILES SHA256SUMS): skipped. ACAS will ask for its settings on first launch." ;;
  ready)
    seed_ok=1
    if command -v python3 >/dev/null 2>&1; then
      # Run ACAS against a copy of the files in a temporary folder: main menu, Sales
      # and every ledger must open and exit cleanly with this build. ~/ACAS isn't touched.
      echo "Testing the start-up data with this build (takes about 30 seconds)..."
      if seed_out="$(PATH="$HOME/bin:$PATH" COB_LIBRARY_PATH="$HOME/bin" ACAS_BIN="$HOME/bin" \
                     python3 "$SEED_DIR/make-seed.py" --verify "$SEED_DIR" 2>&1)"; then
        printf '%s\n' "$seed_out"
      else
        seed_ok=0
        warn "This build couldn't use the start-up data in seed/, so it wasn't installed. ACAS will ask for its settings on first launch instead (answers: RUNNING.md). What the test saw:
$(printf '%s\n' "$seed_out" | tail -n 30)"
      fi
    else
      if seed_checksums; then
        echo "python3 isn't installed, so ACAS couldn't be test-run with the start-up data; its files match seed/SHA256SUMS."
      else
        case $? in
          1) seed_ok=0
             warn "$SEED_MSG (changed or damaged), so the start-up data wasn't installed. ACAS will ask for its settings on first launch instead (answers: RUNNING.md)." ;;
          *) echo "python3 isn't installed and there's no sha256sum or shasum, so the start-up data is installed without testing it first." ;;
        esac
      fi
    fi
    if [ "$seed_ok" = 1 ]; then
      mkdir -p "$HOME/ACAS"
      for f in $SEED_FILES; do
        if [ ! -e "$HOME/ACAS/$f" ]; then
          cp "$SEED_DIR/$f" "$HOME/ACAS/$f"
          chmod 644 "$HOME/ACAS/$f"     # a checkout on /mnt/c makes every file look executable
        fi
      done
      echo "Installed $SEED_FILES into ~/ACAS: company 'ACAS Workshop', financial year 2026, default analysis codes."
      SEED_RESULT=seeded
    fi ;;
esac

# --- 8. Done -----------------------------------------------------------------
cols="$(tput cols 2>/dev/null || echo 0)"; lines="$(tput lines 2>/dev/null || echo 0)"
step "ACAS is installed"
cat << EOF
Next:
  1. Open a new terminal (or run: exec \$SHELL) so the new PATH/env vars load.
  2. Make the terminal at least 80x24 (this one is ${cols}x${lines}).
  3. cd ~/ACAS && ACAS
EOF
case "$SEED_RESULT" in
  seeded) echo "ACAS opens straight on its main menu. Settings can be changed with Z (System Setup)." ;;
  kept)   echo "ACAS opens with your existing settings and data." ;;
  *)      echo "The first launch shows the System Parameter set-up screens (answers: RUNNING.md)."
          echo "If ACAS stops right after them, start it again: that is a known upstream bug (seed/README.md)." ;;
esac
if [ "$cols" -gt 0 ] && { [ "$cols" -lt 80 ] || [ "$lines" -lt 24 ]; }; then
  warn "This terminal is ${cols}x${lines}. ACAS needs at least 80x24, or its screens will be garbled."
fi
