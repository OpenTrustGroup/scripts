#!/usr/bin/env python
# Copyright 2018 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import contextlib
import errno
import json
import os
import shutil
import tarfile
import tempfile


class Frontend(object):
    '''Processes the contents of an SDK tarball and runs them through various
    transformation methods.

    In order to process atoms of type "foo", a frontend needs to define a
    `install_foo_atom` method that accepts a single argument representing
    the atom's metadata in JSON format.
    '''

    def __init__(self, output='', archive='', directory=''):
        self._archive = archive
        self._directory = directory
        self.output = os.path.realpath(output)
        self._source_dir = ''

    def source(self, *args):
        '''Builds a path to a source file.
        Only available while the frontend is running.
        '''
        if not self._source_dir:
            raise Exception('Error: accessing sources while inactive')
        return os.path.join(self._source_dir, *args)

    def dest(self, *args):
        '''Builds a path in the output directory.
        This method also ensures that the directory hierarchy exists in the
        output directory.
        Behaves correctly if the first argument is already within the output
        directory.
        '''
        if (os.path.commonprefix([os.path.realpath(args[0]), self.output]) ==
            self.output):
          path = os.path.join(*args)
        else:
          path = os.path.join(self.output, *args)
        return self.make_dir(path)

    def prepare(self, arch):
        '''Called before elements are processed.'''
        pass

    def finalize(self, arch):
        '''Called after all elements have been processed.'''
        pass

    def run(self):
        '''Runs this frontend through the contents of the archive.
        Returns true if successful.
        '''
        with self._create_archive_dir() as archive_dir:
            self._source_dir = archive_dir

            # Convenience for loading metadata files below.
            def load_metadata(*args):
                with open(self.source(*args), 'r') as meta_file:
                    return json.load(meta_file)

            manifest = load_metadata('meta', 'manifest.json')
            self.prepare(manifest['arch'])

            # Process each SDK atom.
            for part in manifest['parts']:
                atom = load_metadata(part)
                type = atom['type']
                getattr(self, 'install_%s_atom' % type, self._handle_atom)(atom)

            self.finalize(manifest['arch'])

            # Reset the source directory, which may be about to disappear.
            self._source_dir = ''
        return True

    def _handle_atom(self, atom):
        '''Default atom handler.'''
        print('Ignored %s (%s)' % (atom['name'], atom['type']))

    def make_dir(self, file_path):
        '''Creates the directory hierarchy for the given file and returns the
        given path.
        '''
        target = os.path.dirname(file_path)
        try:
            os.makedirs(target)
        except OSError as exception:
            if exception.errno == errno.EEXIST and os.path.isdir(target):
                pass
            else:
                raise
        return file_path

    @contextlib.contextmanager
    def _create_archive_dir(self):
        if self._directory:
            yield self._directory
        elif self._archive:
            temp_dir = tempfile.mkdtemp(prefix='fuchsia-bazel')
            # Extract the tarball into the temporary directory.
            # This is vastly more efficient than accessing files one by one via
            # the tarfile API.
            with tarfile.open(self._archive) as archive:
                archive.extractall(temp_dir)
            try:
                yield temp_dir
            finally:
                shutil.rmtree(temp_dir, ignore_errors=True)
        else:
            raise Exception('Error: archive or directory must be set')
