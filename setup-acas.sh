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
#    Enter your Linux password when sudo asks for it (package install).
#
# -----------------------------------------------------------------------------
# macOS (install logic simulated on Linux; not yet run on a real Mac)
# -----------------------------------------------------------------------------
# 1. Install Homebrew (https://brew.sh) and the Xcode Command Line Tools
#    (the script starts `xcode-select --install` if they're missing).
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
#   --clean              delete a build directory this script created earlier,
#                        then rebuild
#   ACAS_BUILD_DIR=path  build directory (default: ~/cobolsrc/ACAS)
#   SKIP_DEPS=1          don't install packages
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
#   - First run opens the System Parameter set-up (manual chapter 19):
#       * Company name: asked ONCE only, and can't be changed later.
#       * Sub-systems in use: answer Y to all if unsure (also asked once).
#       * (1-13) Data File Handling: 0  (COBOL files; this is a no-RDBMS build)
#       * (2-03) Operating System: 6 = Linux (WSL), 3 = Mac
#       * (2-05) Print spool names: CUPS printer names (`lpstat -p` lists them)
# =============================================================================
[ -n "${BASH_VERSION:-}" ] || { echo "Run this script with bash:  bash $0" >&2; exit 1; }
set -eu

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ACAS_BUILD_DIR:-$HOME/cobolsrc/ACAS}"
MARKER=".acas-build-copy"
CLEAN=0

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    -h|--help) awk 'NR > 1 { if (/^#/) print; else exit }' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

OS="$(uname -s)"
case "$OS" in
  Linux|Darwin) ;;
  *) die "Unsupported OS '$OS'. On Windows, run this inside WSL (see header)." ;;
esac

[ -f "$SRC_DIR/comp-all-no-rdbms.sh" ] || die "Run this from the ACAS source tree (comp-all-no-rdbms.sh not found in $SRC_DIR)."

# --- 1. Dependencies ---------------------------------------------------------
if [ "${SKIP_DEPS:-0}" != "1" ]; then
  step "Installing build dependencies"
  if [ "$OS" = "Linux" ]; then
    command -v apt-get >/dev/null 2>&1 || die "apt-get not found (only Debian/Ubuntu are automated). Install GnuCOBOL 3.2 plus the Berkeley DB, ncurses and zlib development packages yourself, then re-run with SKIP_DEPS=1."
    if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
      command -v sudo >/dev/null 2>&1 || die "sudo not found and you aren't root. Install the packages yourself, then re-run with SKIP_DEPS=1."
      SUDO="sudo"
    fi
    $SUDO apt-get update
    if apt-cache show gnucobol3 >/dev/null 2>&1; then COBOL_PKG=gnucobol3; else COBOL_PKG=gnucobol; fi
    $SUDO apt-get install -y "$COBOL_PKG" libdb-dev libncurses-dev zlib1g-dev build-essential
  else
    xcode-select -p >/dev/null 2>&1 || { xcode-select --install || true; die "Finish installing the Xcode Command Line Tools, then re-run this script."; }
    # Homebrew isn't on PATH in some shells (Apple Silicon: /opt/homebrew, Intel: /usr/local).
    command -v brew >/dev/null 2>&1 || for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
    done
    command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it from https://brew.sh, then re-run."
    brew install gnucobol
  fi
fi

command -v cobc >/dev/null 2>&1 || die "cobc (GnuCOBOL) not on PATH."
COBC_VER="$(cobc --version | head -n1)"
echo "Using: $COBC_VER"
case "$(echo "$COBC_VER" | grep -oE '[0-9]+\.[0-9]+' | head -n1)" in
  1.*|2.*) die "GnuCOBOL 3.x is required (3.2 recommended by the ACAS manual)." ;;
  3.0|3.1) echo "WARNING: ACAS v3.3 is built and tested with GnuCOBOL 3.2; this version may fail to build." ;;
esac

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
mkdir -p "$BUILD_DIR"
touch "$BUILD_DIR/$MARKER"
# Copy only what the build uses (top-level scripts and the six source dirs), so
# manuals, workshop material and anything else in the repo stay out of the build.
for d in common copybooks general irs purchase sales stock; do
  [ -d "$SRC_DIR/$d" ] || die "Source directory missing: $SRC_DIR/$d"
  cp -R "$SRC_DIR/$d" "$BUILD_DIR/"
done
cp "$SRC_DIR"/*.sh "$BUILD_DIR/"

step "Normalising shell scripts (LF endings, execute bit)"
find "$BUILD_DIR" -name '*.sh' -type f -exec perl -pi -e 's/\r$//' {} +
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
if grep -nE 'error:|cannot find|No such file|Permission denied|command not found' "$BUILD_LOG"; then
  die "The build reported the errors above. Fix them and re-run with --clean."
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
if [ "$OS" = "Linux" ]; then
  # install-ACAS.sh appends env vars to ~/.bashrc every time it runs, so use
  # it only once. Later installs use install-ACAS-preinstalled.sh.
  if grep -q 'ACAS_LEDGERS' "$HOME/.bashrc" 2>/dev/null; then
    INSTALLER=install-ACAS-preinstalled.sh
    mkdir -p "$HOME/ACAS/temp-backups" "$HOME/ACAS/archives" "$HOME/tmp"
  else
    INSTALLER=install-ACAS.sh
  fi
  step "Installing into ~/bin with $INSTALLER"
  (cd "$BUILD_DIR" && bash "$INSTALLER") 2>&1 | tee "$INSTALL_LOG"
  # install-ACAS.sh writes PATH with the install-time $PATH expanded and unquoted.
  # Under WSL that includes Windows paths with spaces, which breaks the line.
  sed -i 's|^export PATH=~/bin:\.:.*$|export PATH="$HOME/bin:.:$PATH"|' "$HOME/.bashrc"
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
    chmod u+x "$HOME"/bin/*.sh
  } 2>&1 | tee "$INSTALL_LOG"

  case "${SHELL:-}" in
    */zsh) RC="$HOME/.zshrc" ;;
    *)     RC="$HOME/.bash_profile" ;;
  esac
  if ! grep -q 'ACAS_LEDGERS' "$RC" 2>/dev/null; then
    cat >> "$RC" << 'EOF'

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
    echo "Added ACAS environment variables to $RC"
  fi
fi

[ -f "$HOME/bin/ACAS" ] && [ -f "$HOME/bin/sys002.$EXT" ] || die "Install didn't put ACAS into ~/bin. See $INSTALL_LOG"

# --- 6. Done -----------------------------------------------------------------
cols="$(tput cols 2>/dev/null || echo 0)"; lines="$(tput lines 2>/dev/null || echo 0)"
step "ACAS is installed"
cat << EOF
Next:
  1. Open a new terminal (or run: exec \$SHELL) so the new PATH/env vars load.
  2. Make the terminal at least 80x24 (this one is ${cols}x${lines}).
  3. cd ~/ACAS && ACAS
First run starts the System Parameter set-up. See the header of this script
for the recommended answers.
EOF
