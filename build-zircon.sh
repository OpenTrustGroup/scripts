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

usage() {
  echo "$0 <options>"
  echo "Options:"
  echo "  -c: Clean before building"
  echo "  -v: Level 1 verbosity"
  echo "  -V: Level 2 verbosity"
  echo "  -A: Build with ASan"
  echo "  -H: Build host tools with ASan"
  echo "  -t <target>: Architecture (GN style) to build, instead of all"
  echo "  -o <outdir>: Directory in which to put the build-zircon directory."
  echo ""
  echo "Note: Passing extra arguments to make is not supported."
}

declare ASAN="${ASAN:-false}"
declare CLEAN="${CLEAN:-false}"
declare HOST_ASAN="${HOST_ASAN:-false}"
declare OUTDIR="${OUTDIR:-${ROOT_DIR}/out}"
declare VERBOSE="${VERBOSE:-0}"
declare -a ARCHLIST=(arm64 x64)

while getopts "AcHht:p:u:o:vV" opt; do
  case "${opt}" in
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

readonly ASAN CLEAN HOST_ASAN PROJECTS OUTDIR VERBOSE
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

if [[ "${ASAN}" = "true" ]]; then
  readonly ASAN_ZIRCON=true
  readonly ASAN_ULIB=false
else
  readonly ASAN_ZIRCON=false
  readonly ASAN_ULIB=true
fi

make_zircon_common() {
  (test $QUIET -ne 0 || set -x
   exec make --no-print-directory -C "${ROOT_DIR}/zircon" \
             -j ${JOBS} DEBUG_BUILDROOT=../../zircon "$@")
}

# Build host tools.
make_zircon_common \
  BUILDDIR=${OUTDIR}/build-zircon HOST_USE_ASAN="${HOST_ASAN}" tools

make_zircon_target() {
  make_zircon_common \
    BUILDROOT=${ZIRCON_BUILDROOT} TOOLS=${OUTDIR}/build-zircon/tools "$@"
}

for ARCH in "${ARCHLIST[@]}"; do
    # Build full bootloader, kernel, userland, and sysroot.
    make_zircon_target PROJECT="${ARCH}" \
        BUILDDIR_SUFFIX= USE_ASAN="${ASAN_ZIRCON}"

    # Build alternate shared libraries (ASan).
    make_zircon_target PROJECT="${ARCH}" \
        BUILDDIR_SUFFIX=-ulib USE_ASAN="${ASAN_ULIB}" \
        ENABLE_ULIB_ONLY=true ENABLE_BUILD_SYSROOT=false
done
