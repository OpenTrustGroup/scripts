
# Copyright 2018 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
# DO NOT MANUALLY EDIT!
# Generated by //scripts/sdk/bazel/create_bazel_layout.py.

package(default_visibility = ["//visibility:public"])
licenses(["unencumbered"])

cc_library(
  name = "${data.name}",
  srcs = [
    % for source in sorted(data.srcs):
    "${source}",
    % endfor
  ],
  hdrs = [
    % for header in sorted(data.hdrs):
    "${header}",
    % endfor
  ],
  deps = [
    % for dep in sorted(data.deps):
    "${dep}",
    % endfor
  ],
  includes = [
    % for include in sorted(data.includes):
    "${include}",
    % endfor
  ],
)