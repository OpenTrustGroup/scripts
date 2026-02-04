#!/usr/bin/env bash
# Copyright 2016 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

JOBS=`getconf _NPROCESSORS_ONLN` || {
  Cannot get number of processors
  exit 1
}

set -eo pipefail; [[ "${TRACE}" ]] && set -x

echo "$(basename ${BASH_SOURCE[0]}) $@"

usage() {
  echo "$0 <options> <extra-make-arguments>"
  echo ""
  echo "Options:"
  echo "  -c: Clean before building"
  echo "  -v: Level 1 verbosity"
  echo "  -V: Level 2 verbosity"
  echo "  -A: Build with ASan"
  echo "  -r: Build Release version."
  echo "  -a: make assert and DEBUG_ASSERT valid in release mode."
  echo "  -H: Build host tools with ASan"
  echo "  -t <target>: Architecture (GN style) to build, instead of all"
  echo "  -o <outdir>: Directory in which to put the build-zircon directory."
  echo ""
  echo "Additional arguments may be passed to make using standard FOO=bar syntax."
  echo "E.g., build-zircon.sh USE_CLANG=true"
}

declare RELEASE="false"
declare ENABLE_ASSERT="false"
declare ASAN="false"
declare CLEAN="false"
declare HOST_ASAN="false"
declare OUTDIR="${ROOT_DIR}/out"
declare VERBOSE="0"
declare -a ARCHLIST=(arm64 x64)

while getopts "raAcHht:p:o:vV" opt; do
  case "${opt}" in
    r) RELEASE="true" ;;
    a) ENABLE_ASSERT="true" ;;
    A) ASAN="true" ;;
    c) CLEAN="true" ;;
    H) HOST_ASAN="true" ;;
    h) usage ; exit 0 ;;
    o) OUTDIR="${OPTARG}" ;;
    t) ARCHLIST=("${OPTARG}") ;;
    v) VERBOSE="1" ;;
    V) VERBOSE="2" ;;
    *) usage 1>&2 ; exit 1 ;;
  esac
done
shift $(($OPTIND - 1))

readonly ASAN CLEAN HOST_ASAN PROJECTS OUTDIR VERBOSE RELEASE
readonly ZIRCON_BUILDROOT="${OUTDIR}/build-zircon"
readonly -a ARCHLIST

if [[ "${CLEAN}" = "true" ]]; then
  rm -rf -- "${ZIRCON_BUILDROOT}"
fi

# These variables are picked up by make from the environment.
case "${VERBOSE}" in
  1) QUIET=0 ; V=0 ;;
  2) QUIET=0 ; V=1 ;;
  *) QUIET=1 ; V=0 ;;
esac
export QUIET V

# On release, ASAN is disable.
if [ "${RELEASE}" = "true" ]; then
  readonly ASAN_ZIRCON=false
  readonly ASAN_ULIB=true
else
  if [[ "${ASAN}" = "true" ]]; then
    readonly ASAN_ZIRCON=true
    readonly ASAN_ULIB=false
  else
    readonly ASAN_ZIRCON=false
    readonly ASAN_ULIB=true
  fi
fi

make_zircon_common() {
  # GRT: Add below options.
  # The values(true/false) of all flags in shell should be transfered to 1/0.
  # DEBUG=0 will disable DEBUG_ASSERT
  # NBL_IS_RELEASE=true will disable some module in rules.mk and source code.
  # ENABLE_ASSERT=true will force to enable DEBUG_ASSERT() and assert()
  if [ "${RELEASE}" = "true" ]; then
    RLS_OPT="export NBL_IS_RELEASE=1 DEBUG=0 "
    if [ "${ENABLE_ASSERT}" = "true" ]; then
      RLS_OPT="${RLS_OPT} ENABLE_ASSERT=1 "
    else
      RLS_OPT="${RLS_OPT} NDEBUG=1 "
    fi
  else
    RLS_OPT=""
  fi

  (test $QUIET -ne 0 || set -x
   ${RLS_OPT}
   exec make --no-print-directory -C "${ROOT_DIR}/zircon" \
             -j ${JOBS} DEBUG_BUILDROOT=../../zircon "$@")
}

if [ "${RELEASE}" = "true" ]; then
  BUILDDIR=${OUTDIR}/build-zircon-release
  BUILDROOT=${ZIRCON_BUILDROOT}-release
else
  BUILDDIR=${OUTDIR}/build-zircon
  BUILDROOT=${ZIRCON_BUILDROOT}
fi

# Build host tools.
make_zircon_common \
  BUILDDIR=${BUILDDIR} HOST_USE_ASAN="${HOST_ASAN}" tools "$@"

make_zircon_target() {
  make_zircon_common \
    BUILDROOT=${BUILDROOT} TOOLS=${BUILDDIR}/tools "$@"
}

# build the zircon kernel.
for ARCH in "${ARCHLIST[@]}"; do
    # Build full bootloader, kernel, userland, and sysroot.
    make_zircon_target PROJECT="${ARCH}" \
        BUILDDIR_SUFFIX= USE_ASAN="${ASAN_ZIRCON}" "$@"

    # Build alternate shared libraries (ASan).
    make_zircon_target PROJECT="${ARCH}" \
        BUILDDIR_SUFFIX=-ulib USE_ASAN="${ASAN_ULIB}" \
        ENABLE_ULIB_ONLY=true ENABLE_BUILD_SYSROOT=false "$@"
done
