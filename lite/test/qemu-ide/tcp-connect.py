#!/usr/bin/env python3
"""stdio <-> TCP connect to HOST:PORT (socat - TCP:host:port replacement)."""
import sys, socket, select
host, port = sys.argv[1], int(sys.argv[2])
s = socket.create_connection((host, port))
s.setblocking(False)
sys.stdin = sys.stdin.buffer
sys.stdout = sys.stdout.buffer
try:
    while True:
        r, _, _ = select.select([sys.stdin, s], [], [])
        if sys.stdin in r:
            data = sys.stdin.read(65536)
            if not data:
                break
            s.sendall(data)
        if s in r:
            data = s.recv(65536)
            if not data:
                break
            sys.stdout.write(data); sys.stdout.flush()
except Exception:
    pass
