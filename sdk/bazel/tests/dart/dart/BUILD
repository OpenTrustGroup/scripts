# Copyright 2018 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

load("@fuchsia_sdk//build_defs:dart_app.bzl", "dart_app")
load("@fuchsia_sdk//build_defs:package.bzl", "fuchsia_package")

dart_app(
    name = "dart",
    package_name = "tests.dart_app",
    fuchsia_package_name = "hello_dart_package",
    main = "lib/main.dart",
    srcs = glob(["lib/*.dart"]),
)

fuchsia_package(
    name = "hello_dart_package",
    deps = [
        ":dart",
    ],
)

dart_app(
    name = "dart_with_unused_dependencies",
    package_name = "tests.dart_app",
    fuchsia_package_name = "hello_unused_package",
    main = "lib/main.dart",
    srcs = glob(["lib/*.dart"]),
    deps = [
        "@vendor_meta//:meta",
    ],
)

fuchsia_package(
    name = "hello_unused_package",
    deps = [
        ":dart_with_unused_dependencies",
    ],
)
