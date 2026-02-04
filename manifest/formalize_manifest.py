#!/usr/bin/env python
# Copyright 2019 GoldenRiver Technologies Co., Ltd. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
This tool is used to sort lines of boot/system manifests.
"""

import os
import sys
import tempfile

manifests = ["boot.manifest.rel", "system.manifest.rel"]


def main():
    for manifest in manifests:
        lines = []
        with open(manifest) as f1:
            for line in f1:
                lines.append(line)
        with tempfile.NamedTemporaryFile(delete=False) as f2:
            for line in sorted(lines):
                f2.write(line)
        os.rename(f2.name, manifest)


if __name__ == "__main__":
    main()
