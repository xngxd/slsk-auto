#!/usr/bin/env python3
"""Generate a minimal MP3 file with ID3v2.3 tags for testing.

Usage: make_mp3.py <output.mp3> <album-artist> <album> [track-artist]

TPE2 (album artist) is always written. TPE1 (track artist) is written only
when track-artist is given — mirrors the real-world case where they differ.
"""
import struct, sys
from pathlib import Path


def _syncsafe(n):
    b = bytearray(4)
    for i in range(3, -1, -1):
        b[i] = n & 0x7F
        n >>= 7
    return bytes(b)


def _frame(frame_id, text):
    data = b'\x03' + text.encode('utf-8') + b'\x00'
    return frame_id.encode('ascii') + struct.pack('>I', len(data)) + b'\x00\x00' + data


def make_mp3(path, album_artist, album, track_artist=None):
    frames = b''
    if track_artist:
        frames += _frame('TPE1', track_artist)
    frames += _frame('TPE2', album_artist)
    frames += _frame('TALB', album)
    header = b'ID3\x03\x00\x00' + _syncsafe(len(frames))
    Path(path).write_bytes(header + frames)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <output.mp3> <album-artist> <album> [track-artist]")
        sys.exit(1)
    make_mp3(sys.argv[1], sys.argv[2], sys.argv[3],
             sys.argv[4] if len(sys.argv) > 4 else None)
