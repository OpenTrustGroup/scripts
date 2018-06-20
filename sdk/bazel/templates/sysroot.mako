# Copyright 2018 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

exports_files(
    glob(["**"]),
)

# For packaging purposes.
cc_library(
    name = "dist",
    srcs = [
        "dist/libc.so",
    ],
    visibility = [
        "//visibility:public",
    ],
)