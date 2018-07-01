# Copyright 2018 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Contains information about a Dart library's dependency structure.
DartLibraryInfo = provider(
    fields = {
        "package_map": "depset of packages described by struct(name, root)",
    }
)


def _create_info(packages, deps):
    transitive_info = [dep[DartLibraryInfo].package_map for dep in deps]
    result = DartLibraryInfo(
        package_map = depset(packages, transitive = transitive_info),
    )

    # Verify duplicates.
    packages = {}
    for package in result.package_map.to_list():
        name = package.name
        path = package.root.path
        if name in packages:
            if path == packages[name]:
                continue
            fail("Found same package %s with two different roots: %s and %s"
                 % (name, packages[name], path))
        packages[name] = path

    return result


def aggregate_packages(deps):
    '''Aggregates the package mapping provided by the given dependencies.'''
    return _create_info([], deps)


def produce_package_info(package_name, source_root, deps):
    """Aggregates the package mappings provided by the given dependencies, and
       adds an extra mapping from the given name to the given root.
       """
    this_package = struct(name = package_name, root = source_root)
    return _create_info([this_package], deps)


def relative_path(to_path, from_dir=None):
    """Returns the relative path from a directory to a path via the repo root.
       """
    if to_path.startswith("/") or from_dir.startswith("/"):
        fail("Absolute paths are not supported.")
    if not from_dir:
        return to_path
    return "../" * len(from_dir.split("/")) + to_path


def generate_dot_packages_action(context, packages_file, package_info):
    """Creates an action that generates a .packages file based on the packages
       listed in the given info object.
       """
    # Paths need to be relative to the current directory which is under the
    # output directory.
    current_directory = context.bin_dir.path + "/" + context.label.package
    packages = {p.name: relative_path(p.root.path, from_dir=current_directory)
                for p in package_info.package_map.to_list()}

    contents = ""
    for name, path in sorted(packages.items()):
        contents += name + ":" + path + "\n"

    context.actions.write(
        output = packages_file,
        content = contents,
    )
