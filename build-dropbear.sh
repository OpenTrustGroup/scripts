#!/usr/bin/env bash
# Copyright 2018 GoldenRiver Technology Co., Ltd. All rights reserved.
# Copyright 2017 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/devshell/lib/vars.sh
source "${FUCHSIA_DIR}/buildtools/vars.sh"
fx-config-read

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

readonly HOST_ARCH="$(uname -m)"
readonly HOST_OS="$(uname | tr '[:upper:]' '[:lower:]')"
readonly HOST_TRIPLE="aarch64-linux-gnu"

readonly GCC_TOOLCHAIN_PATH="$(dirname ${LINARO_AARCH64_CROSS_COMPILE})/../"
readonly DROPBEAR_CC="${LINARO_AARCH64_CROSS_COMPILE}gcc"
#readonly DROPBEAR_CFLAGS=" --target=${HOST_TRIPLE} --gcc-toolchain=${GCC_TOOLCHAIN_PATH} --sysroot=${GCC_TOOLCHAIN_PATH}/${HOST_TRIPLE}/libc"
readonly DROPBEAR_CFLAGS=""
readonly DROPBEAR_LD="${LINARO_AARCH64_CROSS_COMPILE}gcc"
readonly DROPBEAR_LDFLAGS="${DROPBEAR_CFLAGS}"
readonly DROPBEAR_HOST="${HOST_TRIPLE}"

if [[ "x${HOST_OS}" != "xlinux" ]]; then
  echo "unsupported system: ${HOST_OS}" 1>&2
  exit 1
fi

set -eo pipefail; [[ "${TRACE}" ]] && set -x

usage() {
  printf >&2 '%s: [-c] [-o outdir] [-d destdir] [-j jobs] [-s srcdir]\n' "$0"
  exit 1
}

build() {
  local srcdir="$1" outdir="$2" destdir="$3" clean="$4" jobs="$5"

  if [[ "${clean}" = "true" ]]; then
    rm -rf -- "${outdir}/build-dropbear-${HOST_TRIPLE}"
  fi

  rm -rf "${destdir}/dropbear-${HOST_TRIPLE}"

  mkdir -p -- "${outdir}/build-dropbear-${HOST_TRIPLE}"
  pushd "${outdir}/build-dropbear-${HOST_TRIPLE}"
  export CC=${DROPBEAR_CC}
  export CFLAGS=${DROPBEAR_CFLAGS}
  export LD=${DROPBEAR_LD}
  export LDFLAGS=${DROPBEAR_LDFLAGS}
  ${srcdir}/configure \
    --host=${DROPBEAR_HOST} \
    --disable-zlib \
    --disable-lastlog \
    --disable-syslog \

  make -j "${jobs}" PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
  popd
}

declare CLEAN="${CLEAN:-false}"
declare SRCDIR="${SRCDIR:-${ROOT_DIR}/third_party/dropbear}"
declare OUTDIR="${OUTDIR:-${ROOT_DIR}/out}"
declare DESTDIR="${DESTDIR:-${OUTDIR}}"
declare JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"

while getopts "cd:j:o:s:" opt; do
  case "${opt}" in
    c) CLEAN="true" ;;
    d) DESTDIR="$(cd "${OPTARG}"; pwd -P)" ;;
    j) JOBS="${OPTARG}" ;;
    o) OUTDIR="$(cd "${OPTARG}"; pwd -P)" ;;
    s) SRCDIR="$(cd "${OPTARG}"; pwd -P)" ;;
    *) usage;;
  esac
done

readonly CLEAN SRCDIR OUTDIR DESTDIR JOBS

build "${SRCDIR}" "${OUTDIR}" "${DESTDIR}" "${CLEAN}" "${JOBS}"
