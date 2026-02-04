# Copyright 2019 GoldenRiver Technology Co., Ltd. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

declare -a SEARCH_PATH=(
  "${FUCHSIA_OUT_DIR}/build-zircon/build-venus-hee"
  "${FUCHSIA_OUT_DIR}/build-zircon/build-venus-hee-ulib"
  "${FUCHSIA_OUT_DIR}/arm64"
  "${FUCHSIA_OUT_DIR}/build-atf"
)

function find_file_with_debug_symbol {
  SEARCHED_FILES=

  for path in "${SEARCH_PATH[@]}"; do
    SEARCHED_FILES+=$(find ${path} -name $1)
  done

  if [[ ! -n ${SEARCHED_FILES} ]]; then
    echo ""
    return
  fi

  for file in ${SEARCHED_FILES}; do
    NOT_STRIPPED=$(file ${file} | awk '/not stripped/ {print "true"}')
    if [ "$NOT_STRIPPED" == "true" ]; then
      echo $file
      return
    fi
  done
}
