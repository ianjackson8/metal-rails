#!/usr/bin/env python3
"""Fills the switch tables Ghidra left empty and the lifter cannot size.

Usage: python3 -I tools/complete_jumptables.py IMAGE SYMBOLS_DIR

x86recomp's lifter recovers a switch table (`jmp [reg*4 + table]`) from the
bounds check before it (`cmp reg, N` / `ja`). A switch whose index is in
range by construction has no such check: Ghidra may leave its table empty
too, and a case then jumps out of the lifted code. For each such jump in
SYMBOLS_DIR/jumptables.tsv (no targets, no conditional branch in the 32
bytes before it), the table is read from the image while its entries
point into the function containing the jump (its body per
SYMBOLS_DIR/functions.tsv), at most 256 entries. The file is rewritten in
place with those targets; lines it does not fill stay as they were.
"""
import bisect
import struct
import sys


def sections(d):
    pe = struct.unpack_from('<I', d, 0x3C)[0]
    base = struct.unpack_from('<I', d, pe + 52)[0]
    n = struct.unpack_from('<H', d, pe + 6)[0]
    opt = struct.unpack_from('<H', d, pe + 20)[0]
    out = []
    for i in range(n):
        o = pe + 24 + opt + 40 * i
        vsize, va, rsize, raw = struct.unpack_from('<IIII', d, o + 8)
        out.append((base + va, rsize, raw))
    return out


def main():
    image, symdir = sys.argv[1], sys.argv[2]
    d = open(image, 'rb').read()
    secs = sections(d)

    def off(va):
        for s, n, raw in secs:
            if s <= va < s + n:
                return raw + va - s
        return None

    def u32(va):
        o = off(va)
        return None if o is None or o + 4 > len(d) else struct.unpack_from('<I', d, o)[0]

    funcs = []
    for line in open(symdir + '/functions.tsv').read().splitlines()[1:]:
        c = line.split('\t')
        funcs.append((int(c[1], 16), int(c[2], 16)))
    funcs.sort()
    starts = [f[0] for f in funcs]

    def body(va):
        i = bisect.bisect_right(starts, va) - 1
        return funcs[i] if i >= 0 and funcs[i][0] <= va <= funcs[i][1] else None

    path = symdir + '/jumptables.tsv'
    lines = open(path).read().splitlines()
    filled = 0
    for k, line in enumerate(lines[1:], 1):
        c = line.split('\t')
        if len(c) > 1 and c[1]:
            continue
        va = int(c[0], 16)
        o = off(va)
        # jmp dword ptr [index*4 + disp32]: FF 24 <sib: scale 4, no base> disp32
        if o is None or d[o] != 0xFF or d[o + 1] != 0x24 or (d[o + 2] & 0xC7) != 0x85:
            continue
        before = d[max(o - 32, 0):o]
        # A conditional branch shortly before: a bounds check the lifter reads.
        if any(b in (0x77, 0x76) for b in before) or b'\x0f\x87' in before or b'\x0f\x86' in before:
            continue
        fn = body(va)
        if not fn:
            continue
        table = struct.unpack_from('<I', d, o + 3)[0]
        targets = []
        for i in range(256):
            t = u32(table + 4 * i)
            if t is None or not (fn[0] <= t <= fn[1]):
                break
            if t not in targets:
                targets.append(t)
        if targets:
            lines[k] = '%s\t%s' % (c[0], ','.join('%08X' % t for t in targets))
            filled += 1
    open(path, 'w').write('\n'.join(lines) + '\n')
    print('complete_jumptables: %d tables filled' % filled)


if __name__ == '__main__':
    main()
