# Copyright 2017 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

if [[ -n "${ZSH_VERSION}" ]]; then
  devshell_lib_dir=${${(%):-%x}:a:h}
else
  devshell_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

export FUCHSIA_DIR="$(dirname $(dirname $(dirname "${devshell_lib_dir}")))"
export FUCHSIA_OUT_DIR="${FUCHSIA_OUT_DIR:-${FUCHSIA_DIR}/out}"
export FUCHSIA_CONFIG="${FUCHSIA_CONFIG:-${FUCHSIA_DIR}/.config}"
export TOOLCHAIN_CONFIG="${FUCHSIA_DIR}/.toolchain_config"
unset devshell_lib_dir

export ZIRCON_TOOLS_DIR="${FUCHSIA_OUT_DIR}/build-zircon/tools"

HOST_ARCH="$(uname -m)"
HOST_OS="$(uname | tr '[:upper:]' '[:lower:]')"
HOST_TRIPLE="${HOST_ARCH}-${HOST_OS}"

export THIRD_PARTY_QEMU="${FUCHSIA_DIR}/scripts/prebuilt/qemu-${HOST_TRIPLE}"

if [[ "${FUCHSIA_DEVSHELL_VERBOSITY}" -eq 1 ]]; then
  set -x
fi

function fx-config-read-if-present {
  if [[ ! -f "${FUCHSIA_CONFIG}" ]]; then
    return 1
  fi

  source "${FUCHSIA_CONFIG}"

  if [[ -f "${TOOLCHAIN_CONFIG}" ]]; then
    source ${TOOLCHAIN_CONFIG}
  fi

  # Paths are relative to FUCHSIA_DIR unless they're absolute paths.
  if [[ "${FUCHSIA_BUILD_DIR:0:1}" == "/" ]]; then
    export FUCHSIA_BUILD_DIR="${FUCHSIA_BUILD_DIR}"
  else
    export FUCHSIA_BUILD_DIR="${FUCHSIA_DIR}/${FUCHSIA_BUILD_DIR}"
  fi

  export FUCHSIA_VARIANT="${FUCHSIA_VARIANT}"
  export FUCHSIA_ARCH="${FUCHSIA_ARCH}"

  export ZIRCON_BUILDROOT="${ZIRCON_BUILDROOT:-${FUCHSIA_OUT_DIR}/build-zircon}"
  export ZIRCON_BUILD_DIR="${ZIRCON_BUILD_DIR:-${ZIRCON_BUILDROOT}/build-${ZIRCON_PROJECT}}"
  return 0
}

function fx-config-read {
  if ! fx-config-read-if-present ; then
    echo >& 2 "error: Cannot read config from ${FUCHSIA_CONFIG}. Did you run \"fx set\"?"
    exit 1
  fi
}

# if $1 is "-d" or "--device" return
#   - the netaddr if $2 looks like foo-bar-baz-flarg
#     OR
#   - $2 if it doesn't
# else return ""
function get-device-addr {
  device=""
  if [[ "$1" == "-d" || "$1" == "--device" ]]; then
    shift
    if [[ "$1" == *"-"* ]]; then
      device="$(fx-command-run netaddr $1 --fuchsia)"
    else
      device="$1"
    fi
    shift
  fi
  echo $device
}

function fx-command-run {
  local -r command_name="$1"
  local -r command_path="${FUCHSIA_DIR}/scripts/devshell/${command_name}"

  if [[ ! -f "${command_path}" ]]; then
    echo >& 2 "error: Unknown command ${command_name}"
    exit 1
  fi

  shift
  "${command_path}" "$@"
}

function fx-print-command-help {
  local -r command_path="$1"
  if grep '^## ' "$command_path" > /dev/null; then
    sed -n -e 's/^## //p' -e 's/^##$//p' < "$command_path"
  else
    local -r command_name=$(basename "$command_path")
    echo "No help found. Try \`fx $command_name -h\`"
  fi
}

function fx-command-help {
  fx-print-command-help "$0"
}

# This function massages arguments to an fx subcommand so that a single
# argument `--switch=value` becomes two arguments `--switch` `value`.
# This lets each subcommand's main function use simpler argument parsing
# while still supporting the preferred `--switch=value` syntax.  It also
# handles the `--help` argument by redirecting to what `fx help command`
# would do.  Because of the complexities of shell quoting and function
# semantics, the only way for this function to yield its results
# reasonably is via a global variable.  FX_ARGV is an array of the
# results.  The standard boilerplate for using this looks like:
#   function main {
#     fx-standard-switches "$@"
#     set -- "${FX_ARGV[@]}"
#     ...
#     }
function fx-standard-switches {
  # In bash 4, this can be `declare -a -g FX_ARGV=()` to be explicit
  # about setting a global array.  But bash 3 (shipped on macOS) does
  # not support the `-g` flag to `declare`.
  FX_ARGV=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" = "--help" ]]; then
      fx-print-command-help "$0"
      # Exit rather than return, so we bail out of the whole command early.
      exit 0
    elif [[ "$1" == --*=* ]]; then
      # Turn --switch=value into --switch value.
      FX_ARGV+=("${1%%=*}" "${1#*=}")
    else
      FX_ARGV+=("$1")
    fi
    shift
  done
}
