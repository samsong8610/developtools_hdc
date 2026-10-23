#!/usr/bin/env python3
"""Host TCP listen -> stdin/stdout of a child (sudo ip netns exec ... socat-like).
Usage: netns-bridge.py LISTEN_PORT -- CMD...
Forwards each accepted connection by spawning CMD with stdin/stdout attached.
"""
import os, sys, socket, subprocess, select, threading

def pipe(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except Exception:
        pass
    try:
        b.shutdown(socket.SHUT_WR)
    except Exception:
        pass

def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--':
        print('usage: netns-bridge.py PORT -- CMD...', file=sys.stderr)
        sys.exit(2)
    port = int(sys.argv[1])
    cmd = sys.argv[3:]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', port))
    srv.listen(32)
    while True:
        conn, _ = srv.accept()
        # Child connects to device-side target; we use a nested approach:
        # CMD should be: sudo ip netns exec NS socat - TCP:127.0.0.1:DEVICE_PORT
        # If socat missing inside, CMD can be python connect too.
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
        def c2p():
            try:
                while True:
                    data = conn.recv(65536)
                    if not data:
                        break
                    p.stdin.write(data); p.stdin.flush()
            except Exception:
                pass
            try: p.stdin.close()
            except Exception: pass
        def p2c():
            try:
                while True:
                    data = p.stdout.read(65536)
                    if not data:
                        break
                    conn.sendall(data)
            except Exception:
                pass
            try: conn.shutdown(socket.SHUT_WR)
            except Exception: pass
        t1 = threading.Thread(target=c2p, daemon=True); t2 = threading.Thread(target=p2c, daemon=True)
        t1.start(); t2.start()
        t1.join(); t2.join()
        try: p.kill()
        except Exception: pass
        conn.close()

if __name__ == '__main__':
    main()
