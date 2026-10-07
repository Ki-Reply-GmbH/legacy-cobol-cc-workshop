#!/bin/bash
#
# Build the Java port of maps09 (mod-11 customer check digit).
#
# Usage:  bash common/build-maps09.sh OUTDIR
#
# Produces in OUTDIR:
#   maps09.so      thin GnuCOBOL bridge, entry point "maps09" (callers unchanged)
#   maps09jni.so   C/JNI shim the bridge CALLs; starts the JVM on first use
#   maps09.jar     acas.Maps09, the check-digit logic (java/maps09/src)
#
# All three must sit together in a COB_LIBRARY_PATH directory (e.g. ~/bin).
# Needs: cobc (GnuCOBOL 3.2), gcc, JDK 17 (javac, jar, JNI headers).
# JAVA_HOME is used if set, otherwise derived from javac on PATH.
# libjvm is found through an rpath, so no LD_LIBRARY_PATH is needed at runtime.
#
# 05/10/26 - 1.00 Created for the maps09 COBOL -> Java migration.

set -euo pipefail

die() { echo "build-maps09: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: bash common/build-maps09.sh OUTDIR"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"

if [ -z "${JAVA_HOME:-}" ]; then
    command -v javac >/dev/null || die "javac not found and JAVA_HOME not set (install openjdk-17-jdk-headless)"
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi
[ -x "$JAVA_HOME/bin/javac" ] || die "no javac under JAVA_HOME=$JAVA_HOME"
[ -f "$JAVA_HOME/include/jni.h" ] || die "no JNI headers under $JAVA_HOME/include (need a JDK, not a JRE)"
command -v cobc >/dev/null || die "cobc not found"
command -v gcc  >/dev/null || die "gcc not found"

case "$(uname -s)" in
    Darwin) EXT=dylib; JNI_OS=darwin; SHARED="-dynamiclib" ;;
    *)      EXT=so;    JNI_OS=linux;  SHARED="-shared" ;;
esac
LIBJVM_DIR="$JAVA_HOME/lib/server"
[ -d "$LIBJVM_DIR" ] || die "no $LIBJVM_DIR (libjvm)"

SRC="$REPO/java/maps09"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Compiling acas.Maps09 -> $OUT/maps09.jar"
"$JAVA_HOME/bin/javac" --release 17 -d "$WORK/classes" $(find "$SRC/src" -name '*.java')
"$JAVA_HOME/bin/jar" --create --file "$OUT/maps09.jar" -C "$WORK/classes" .

echo "Compiling JNI shim -> $OUT/maps09jni.$EXT"
gcc $SHARED -fPIC -O2 -Wall -o "$OUT/maps09jni.$EXT" "$SRC/native/maps09jni.c" \
    -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/$JNI_OS" \
    -L"$LIBJVM_DIR" -ljvm -ldl -Wl,-rpath,"$LIBJVM_DIR"

echo "Compiling COBOL bridge -> $OUT/maps09.$EXT"
(cd "$REPO/common" && cobc -m -lz maps09.cbl -I ../copybooks -Wlinkage -o "$OUT/maps09.$EXT")

echo "maps09 built in $OUT"
