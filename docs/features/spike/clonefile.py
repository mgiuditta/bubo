#!/usr/bin/env python3
# Una sola chiamata clonefile(2) su un'intera cartella (APFS, copy-on-write).
import ctypes, sys
libc = ctypes.CDLL("/usr/lib/libSystem.dylib", use_errno=True)
if libc.clonefile(sys.argv[1].encode(), sys.argv[2].encode(), 0) != 0:
    e = ctypes.get_errno(); sys.exit(f"clonefile: errno {e}")
