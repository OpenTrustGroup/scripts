#!/bin/bash
# Copyright 2018 Open Trust Group
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -e

function usage {
  cat <<END
usage: $0 <out_manifest_file>

Generate gzos stable manifest from current development environment.
END
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

dev_root=`jiri -show-root`

jiri snapshot /tmp/gzos_stable.tmp
sed 's/remotebranch="gzos_dev" revision="[0-9a-z]\+"/remotebranch="gzos"/' /tmp/gzos_stable.tmp > ${1}

echo "Manifest generated."
echo "Please compare and replace the content of ${dev_root}/manifest/gzos_stable with ${1} if needed."
echo "If gzos_stable was changed, please submit the changes to gerrit for review."
