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
import pexpect
import re

ATF_IMAGE_PATH = os.environ['FUCHSIA_OUT_DIR'] + "/build-atf/images"
LOGFILE_PATH = os.environ['FUCHSIA_DIR'] + "/expect.log"

parser = argparse.ArgumentParser()
parser.add_argument("-w", "--working-dir", default=ATF_IMAGE_PATH, help="Working directory")
parser.add_argument("-f", "--logfile", default=LOGFILE_PATH, help="pexpect log file")
parser.add_argument("-c", "--cmd", help="Command string to start QEMU")
parser.add_argument("-s", "--os", help="OS to be tested")
args = parser.parse_args()

file_out = open(args.logfile, "wb")
file_out.write(b"=== Expect Environment ===\n")
file_out.write(b'Working DIR: %s\n' % args.working_dir.encode())
file_out.write(b'Expect LOGFILE: %s\n' % args.logfile.encode())
file_out.write(b'Test OS: %s\n' % args.os.encode())
file_out.write(b'QEMU CMD: %s\n' % args.cmd.encode())
file_out.close()


class SubTest:
    def __init__(self, test_name):
        self.name = test_name
        self.total = 0
        self.passed = 0

    @classmethod
    def check_result(cls, subtests):
        total = passed = failed = 0

        if subtests is None:
            return False

        print('%-20s %5s %5s %5s' % ("TEST", "TOTAL", "PASS", "FAIL"))
        for key in subtests:
            obj = subtests[key]
            print('%-20s %5d %5d %5d' %
                  (obj.name, obj.total, obj.passed, obj.total - obj.passed))
            total += obj.total
            passed += obj.passed

        failed = total - passed
        print('----------------------------')
        print('Summary: %d/%d (Fail/Total)' % (failed, total))

        if total > 0 and failed == 0:
            return True
        return False


class ExpectProcess:
    def __init__(self, process_cmd, working_dir, boot_complete_str, prompt_str, cmd_list):
        self.process_cmd = process_cmd
        self.working_dir = working_dir
        self.boot_complete_str = boot_complete_str
        self.prompt_str = prompt_str
        self.cmd_list = cmd_list

    def run(self, logfile):
        result = False
        f = open(logfile, "ab")
        try:
            f.write(b'=== Expect Logs ===\n')
            p = pexpect.spawn(command=self.process_cmd, cwd=self.working_dir, logfile=f)

            p.expect_exact(self.boot_complete_str)
            p.sendline()

            for cmd in self.cmd_list:
                p.expect_exact(self.prompt_str)
                p.sendline(cmd)
            p.expect_exact(self.prompt_str)
            p.sendline()
            p.close(force=True)
            result = True
        except Exception as e:
            f.write(str(e))

        f.close()
        return result


class OsTest:
    boot_complete_str = ''
    prompt_str = ''
    test_commands = []
    os_name = ''

    @classmethod
    def parse_log(cls, logfile):
        pass

    @classmethod
    def check(cls, logfile):
        p = ExpectProcess(args.cmd, args.working_dir, cls.boot_complete_str, cls.prompt_str, cls.test_commands)
        expect_success = p.run(logfile)
        if not expect_success:
            print('Failed to run test commands, please check expect log for detail information')
            return False

        subtests = cls.parse_log(logfile)
        return SubTest.check_result(subtests)


class Gzos(OsTest):
    os_name = 'gzos'
    boot_complete_str = '$ '
    prompt_str = '$ '
    test_commands = ['k ut all']

    @classmethod
    def is_subtest_start(cls, line):
        start_re = re.compile('(\w+) : Running (\d+) test', re.IGNORECASE)
        m = start_re.search(line)
        if m:
            return m.group(1), m.group(2)
        return None, 0

    @classmethod
    def is_subtest_end(cls, line):
        end_re = re.compile('(\w+) : (Not a|A)ll tests passed \((\d+)/(\d+)\) in')
        m = end_re.search(line)
        if m:
            return m.group(1), m.group(3)
        return None, 0

    @classmethod
    def parse_log(cls, logfile):
        subtests = dict()
        has_error = False

        with open(logfile, 'r') as f:
            for line in f:
                (test_name, total) = cls.is_subtest_start(line)
                if test_name is not None:
                    if test_name in subtests:
                        print('Error: test (%s) already started' % test_name)
                        has_error = True
                        break
                    subtests[test_name] = SubTest(test_name)
                    subtests[test_name].total += int(total)
                    continue

                (test_name, passed) = cls.is_subtest_end(line)
                if test_name is not None:
                    if test_name not in subtests:
                        print('Error: test (%s) not started yet' % test_name)
                        has_error = True
                        break
                    subtests[test_name].passed += int(passed)
        f.close()

        if has_error:
            return None

        return subtests


class Trusty(OsTest):
    os_name = 'trusty'
    boot_complete_str = 'Please press Enter to activate this console.'
    prompt_str = 'root@FVP:/ '
    test_commands = ['tipc-test -t ta2ta-ipc']

    @classmethod
    def is_test_result(cls, line):
        result_re = re.compile('\d+: (\w+): (PASSED|FAILED)')
        m = result_re.search(line)
        if m:
            is_passed = False
            if m.group(2) == "PASSED":
                is_passed = True
            return m.group(1), is_passed
        return None, False

    @classmethod
    def parse_log(cls, logfile):
        subtest = SubTest('tipc-test')

        with open(logfile, 'r') as f:
            for line in f:
                (test_case, is_passed) = cls.is_test_result(line)
                if test_case is not None:
                    subtest.total += 1
                    if is_passed:
                        subtest.passed += 1
                    continue
        f.close()
        return {subtest.name : subtest}


os_cls = None
for cls in OsTest.__subclasses__():
    if cls.os_name == args.os:
        os_cls = cls
        break

if os_cls is None:
    print('OS is not support (%s)' % args.os)
    exit(-1)

if os_cls.check(args.logfile):
    print("\nTest Passed")
    exit(0)
else:
    print("\nTest Failed")
    exit(-1)

