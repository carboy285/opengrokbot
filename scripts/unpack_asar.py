#!/usr/bin/env python3
"""Extract a packaged Electron ASAR for local inspection, without executing it.

No dependencies. Rejects symlinks, traversal, overlaps, oversized headers and
unpacked entries. Unpacked/native files remain in the original .app bundle.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import struct

MAX_HEADER = 64 * 1024 * 1024
MAX_EXTRACT = 2 * 1024 * 1024 * 1024


def inspect(archive: Path):
    archive_size = archive.stat().st_size
    with archive.open('rb') as stream:
        prefix = stream.read(16)
        if len(prefix) != 16:
            raise ValueError('Truncated ASAR header')
        pickle_size, header_size, payload_size, json_size = struct.unpack('<IIII', prefix)
        if pickle_size != 4 or not 8 <= header_size <= MAX_HEADER:
            raise ValueError('Unsupported ASAR header')
        if payload_size + 4 != header_size or json_size > payload_size - 4 or 8 + header_size > archive_size:
            raise ValueError('Invalid ASAR header lengths')
        stream.seek(16)
        header = json.loads(stream.read(json_size))
    data_start = 8 + header_size
    records = []

    def walk(node, parent=PurePosixPath()):
        files = node.get('files')
        if not isinstance(files, dict):
            raise ValueError('Invalid directory entry')
        for name, entry in files.items():
            if not name or name in ('.', '..') or '/' in name or '\\' in name or '\x00' in name:
                raise ValueError('Unsafe archive path')
            path = parent / name
            if not isinstance(entry, dict) or 'link' in entry:
                raise ValueError('Unsupported entry or symbolic link')
            if 'files' in entry:
                walk(entry, path)
            else:
                size = entry.get('size')
                if type(size) is not int or size < 0:
                    raise ValueError('Invalid file size')
                if entry.get('unpacked') is True:
                    records.append({'path': str(path), 'size': size, 'unpacked': True})
                    continue
                raw_offset = entry.get('offset')
                if not isinstance(raw_offset, str) or not raw_offset.isdecimal():
                    raise ValueError('Invalid offset')
                offset = int(raw_offset)
                if offset + size > archive_size - data_start:
                    raise ValueError('File extends beyond archive')
                records.append({'path': str(path), 'size': size, 'offset': offset, 'unpacked': False})
    walk(header)
    total = sum(r['size'] for r in records if not r['unpacked'])
    if total > MAX_EXTRACT:
        raise ValueError('Extraction exceeds 2 GiB limit')
    end = 0
    for record in sorted((r for r in records if not r['unpacked'] and r['size']), key=lambda r: r['offset']):
        if record['offset'] < end:
            raise ValueError('Overlapping file ranges')
        end = record['offset'] + record['size']
    return data_start, records


def unpack(archive: Path, destination: Path):
    start, records = inspect(archive)
    # Exclusive creation prevents overwriting an app or following a preexisting symlink.
    if destination.exists() or destination.is_symlink():
        raise ValueError('Destination must not exist')
    destination.mkdir(parents=True, mode=0o700)
    root = destination.resolve()
    with archive.open('rb') as stream:
        for record in records:
            if record['unpacked']:
                continue
            target = root / record['path']
            if not target.resolve().is_relative_to(root):
                raise ValueError('Path escapes destination')
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            stream.seek(start + record['offset'])
            remaining = record['size']
            digest = hashlib.sha256()
            with target.open('xb') as output:
                while remaining:
                    block = stream.read(min(1024 * 1024, remaining))
                    if not block:
                        raise ValueError('Archive truncated during extraction')
                    digest.update(block)
                    output.write(block)
                    remaining -= len(block)
            target.chmod(0o600)
            record['sha256'] = digest.hexdigest()
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        records = unpack(args.archive, args.destination)
        manifest = args.destination.parent / (args.destination.name + '-index.json')
        with manifest.open('x') as output:
            json.dump(records, output, indent=2)
        manifest.chmod(0o600)
        print(f'Extracted {sum(not r["unpacked"] for r in records)} files. Index: {manifest}')
    except (ValueError, OSError, json.JSONDecodeError, RecursionError) as error:
        parser.exit(1, f'Inspection failed: {error}\n')


if __name__ == '__main__':
    main()
