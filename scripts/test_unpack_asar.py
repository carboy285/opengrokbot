import json
from pathlib import Path
import struct
import tempfile
import unittest
from unpack_asar import unpack, inspect


def archive_bytes(files, data=b'hello'):
    raw = json.dumps({'files': files}).encode()
    payload = struct.pack('<I', len(raw)) + raw
    payload += b'\0' * (-len(payload) % 4)
    header = struct.pack('<I', len(payload)) + payload
    return struct.pack('<II', 4, len(header)) + header + data


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'app.asar'

    def write(self, files, data=b'hello'):
        self.archive.write_bytes(archive_bytes(files, data))

    def test_nested_file_and_unpacked_native_file(self):
        self.write({'source': {'files': {'main.js': {'size': 5, 'offset': '0'}}}, 'native.node': {'size': 100, 'unpacked': True}})
        records = unpack(self.archive, self.root/'extracted')
        self.assertEqual((self.root/'extracted/source/main.js').read_bytes(), b'hello')
        self.assertEqual(len(records), 2)
        self.assertEqual(len(records[0]['sha256']), 64)
        self.assertFalse((self.root/'extracted/native.node').exists())

    def test_bad_paths_links_bounds_and_overlap(self):
        for files in [
            {'../escape': {'size': 5, 'offset': '0'}},
            {'/absolute': {'size': 5, 'offset': '0'}},
            {'..': {'files': {}}},
            {'x': {'link': '../escape'}},
            {'x': {'size': 50, 'offset': '0'}},
            {'x': {'size': 5, 'offset': '-1'}},
            {'x': {'size': 5, 'offset': '0'}, 'y': {'size': 2, 'offset': '1'}},
        ]:
            with self.subTest(files=files):
                self.write(files)
                with self.assertRaises(ValueError): inspect(self.archive)

    def test_existing_destination_is_never_overwritten(self):
        self.write({'main.js': {'size': 5, 'offset': '0'}})
        output = self.root/'existing'
        output.mkdir()
        with self.assertRaises(ValueError): unpack(self.archive, output)

    def test_truncated_header(self):
        self.archive.write_bytes(b'bad')
        with self.assertRaises(ValueError): inspect(self.archive)


if __name__ == '__main__': unittest.main()
