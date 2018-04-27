#!/usr/bin/env python3
# Copyright 2018 Open Trust Group
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

from __future__ import print_function

import argparse
import os
import subprocess
import re

TOOLCHAIN_PATH = os.environ['FUCHSIA_DIR'] + "/toolchains/aarch64/bin/"
LOGFILE_PATH = os.environ['FUCHSIA_DIR'] + "/expect.log"
EXE_UNSTRIPPED_PATH = os.environ['FUCHSIA_DIR'] + "/out/debug-arm64/exe.unstripped/"
LIB_UNSTRIPPED_PATH = os.environ['FUCHSIA_DIR'] + "/out/debug-arm64/arm64-shared/lib.unstripped/"
SYSROOT_DEBUG_PATH = os.environ['FUCHSIA_DIR'] + "/out/debug-arm64/zircon_toolchain/obj/zircon/public/sysroot/sysroot/debug/"

parser = argparse.ArgumentParser()
parser.add_argument("-f", "--logfile", default=LOGFILE_PATH, help="pexpect log file")
args = parser.parse_args()

with open(args.logfile, "r") as f:
    backtrace_re = re.compile('bt#(\d+).* \(([a-z:\/_.]*),(0x[0-9a-f]+)')
    for line in f:
        m = backtrace_re.search(line)
        if m:
            name = m.group(2)
            addr = m.group(3)

            if '.so' in name:
              file_path = LIB_UNSTRIPPED_PATH + name
              if not os.path.isfile(file_path):
                  file_path = SYSROOT_DEBUG_PATH + name
            else:
              file_path = EXE_UNSTRIPPED_PATH + name.split('/')[-1]

            job = subprocess.Popen(
                [ TOOLCHAIN_PATH + 'aarch64-linux-gnu-addr2line', '-e', file_path, addr],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)
            stdout, stderr = job.communicate()
            print ('%s %s' % (m.group(1), stdout.decode('unicode_escape').rstrip('\n')))
    
