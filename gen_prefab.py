#!/usr/bin/python

import os
import argparse
import re
from shutil import copyfile

#def main():
parser = argparse.ArgumentParser(description='Generate aar file')
parser.add_argument("-i", "--input_files", default=[], type=str, nargs='+',
                        help="The inputs files.")
parser.add_argument("-o", "--output_folder", default="",
                        help="The output folder.")

args = parser.parse_args()

module_map = {}

class Module:
    def __init__(self, name, folder):
        self.name = name
        self.folder = folder

def remove_suffix(text):
    return text.split('.')[0]

def remove_prefix(text, prefix):
    return text[text.startswith(prefix) and len(prefix):]

def create_module(key, module_name):
    module_folder = os.path.join(args.output_folder, 'prefab/modules', module_name)

    content = '''{
  "export_libraries": [],
    "android": {}
}
'''
    os.makedirs(module_folder)
    f = open(os.path.join(module_folder, "module.json"), "w+")
    f.write(content)
    f.close()

    lib_path = os.path.join(module_folder, 'libs/android.arm64-v8a')
    os.makedirs(lib_path)
    content = '''{
  "abi": "arm64-v8a",
  "api": 28,
  "ndk": 21,
  "stl": "c++_shared"
}'''
    f = open(os.path.join(lib_path, "abi.json"), "w+")
    f.write(content)
    f.close()

    include_path = os.path.join(module_folder, 'include')
    os.makedirs(include_path)

    module = Module(module_name, module_folder)
    module_map[key] = module
    return module

def get_module(key):
    return module_map[key]


target_list = [
    "libnbl_fwk_ree_shared.so",
    "libnbl_loader_ree_shared.so",
    "libnbl_secmgr_ree_shared.so",
    "libnbl_license_ree_shared.so",
    "libnbl_attest_ree_shared.so",
    "libnbl_trusty_shared.so",
    "libgoogletest_shared.so",
]

def in_target_list(file):
    for target in target_list:
        if target in file:
            return True

    return False

library_regex_list = [
    r'.*external/ree/ndk/(.*?)/(.*)',

    # some prebuilt packages are not located in ndk folder
    # let's try ree folder
    r'.*external/ree/(.*?)/(.*)',
]

header_regex_list = [
    r'.*external/ree/(.*?)/(.*)',
    r'.*external/googletest/(.*?)/(.*)',
]

def locate_file(regex_list, file):
    for regex in regex_list:
        result = re.match(regex, file)
        if result != None:
            return result.group(1), result.group(2)

    return None, None


for file in args.input_files:
    # currently only search for arm64 libraries
    if in_target_list(file) and 'arm64-v8a' in file:
        key, _ = locate_file(library_regex_list, file)
        assert key != None

        lib = file.split('/')[-1]
        module_name = remove_prefix(remove_suffix(lib), 'lib')
        m = create_module(key, module_name)
        target_path = os.path.join(m.folder, 'libs/android.arm64-v8a', lib)

    elif file.endswith('.h'):
        key, header_path = locate_file(header_regex_list, file)
        assert key != None

        m = get_module(key)
        target_path = os.path.join(m.folder, header_path)

    else:
        continue

    if not os.path.exists(os.path.dirname(target_path)):
        os.makedirs(os.path.dirname(target_path))
    copyfile(file, target_path)

