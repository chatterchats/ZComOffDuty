"""Usage: python3 -I tools/minidump.py <UECC-.../UEMinidump.dmp>

Minimal minidump reader: crashing module+offset and a heuristic stack scan (return addresses on the stack)."""
import struct, sys
data = open(sys.argv[1], 'rb').read()
sig, ver, nstreams, dir_rva = struct.unpack_from('<4sIII', data, 0)
streams = {}
for i in range(nstreams):
    t, size, rva = struct.unpack_from('<III', data, dir_rva + i * 12)
    streams.setdefault(t, (size, rva))
def utf16(rva):
    n = struct.unpack_from('<I', data, rva)[0]
    return data[rva + 4: rva + 4 + n].decode('utf-16le', 'replace')
mods = []
size, rva = streams[4]
n = struct.unpack_from('<I', data, rva)[0]
for i in range(n):
    base, sz, _, _, name_rva = struct.unpack_from('<QIIII', data, rva + 4 + i * 108)
    mods.append((base, sz, utf16(name_rva).split('\\')[-1]))
def where(addr):
    for base, sz, name in mods:
        if base <= addr < base + sz:
            return '%s+0x%x' % (name, addr - base)
    return None
size, rva = streams[6]
tid, = struct.unpack_from('<I', data, rva)
code, flags, rec, addr = struct.unpack_from('<IIQQ', data, rva + 8)
ctx_size, ctx_rva = struct.unpack_from('<II', data, rva + 8 + 152)
print('exception 0x%08x at %s (thread %d)' % (code, where(addr) or hex(addr), tid))
rsp, = struct.unpack_from('<Q', data, ctx_rva + 0x98); rip, = struct.unpack_from('<Q', data, ctx_rva + 0xF8)
print('rip %s  rsp 0x%x' % (where(rip) or hex(rip), rsp))
# thread list -> stack memory of the crashing thread
size, trva = streams[3]
nt = struct.unpack_from('<I', data, trva)[0]
for i in range(nt):
    t_id, susp, pcls, prio, teb, st_start, st_size, st_rva, c_size, c_rva = struct.unpack_from('<IIIIQQIIII', data, trva + 4 + i * 48)
    if t_id == tid:
        mem = data[st_rva: st_rva + st_size]
        off = max(0, rsp - st_start)
        seen = 0
        for j in range(off, min(len(mem), off + 0x4000), 8):
            v, = struct.unpack_from('<Q', mem, j)
            w = where(v)
            if w and not w.startswith(('ntdll', 'kernel')):
                print('  stack+0x%04x  %s' % (j - off, w)); seen += 1
                if seen >= 30: break
