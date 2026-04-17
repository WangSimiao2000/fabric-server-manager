#!/usr/bin/env python3
"""MC Server List Ping — 查询在线玩家数等信息，输出 JSON"""
import socket, struct, json, sys

def mc_ping(host="127.0.0.1", port=25565, timeout=3):
    sock = socket.socket()
    sock.settimeout(timeout)
    sock.connect((host, port))
    host_bytes = host.encode("utf-8")

    def write_varint(val):
        out = b""
        val &= 0xFFFFFFFF  # 转为无符号 32 位，处理 -1 等负数
        while True:
            b = val & 0x7F
            val >>= 7
            out += bytes([b | 0x80]) if val else bytes([b])
            if not val:
                break
        return out

    def read_varint(s):
        val = shift = 0
        while True:
            b = s.recv(1)
            if not b:
                raise IOError("connection closed")
            b = b[0]
            val |= (b & 0x7F) << shift
            shift += 7
            if not (b & 0x80):
                break
        return val

    # Handshake packet (id=0x00)
    data = write_varint(0)  # packet id
    data += write_varint(-1)  # protocol version
    data += write_varint(len(host_bytes)) + host_bytes
    data += struct.pack(">H", port)
    data += write_varint(1)  # next state = status
    sock.sendall(write_varint(len(data)) + data)

    # Status request (id=0x00, empty)
    req = write_varint(0)
    sock.sendall(write_varint(len(req)) + req)

    # Read response
    _pkt_len = read_varint(sock)
    _pkt_id = read_varint(sock)
    json_len = read_varint(sock)
    buf = b""
    while len(buf) < json_len:
        chunk = sock.recv(json_len - len(buf))
        if not chunk:
            break
        buf += chunk
    sock.close()
    return json.loads(buf)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 25565
    try:
        resp = mc_ping("127.0.0.1", port)
        players = resp.get("players", {})
        print(json.dumps({
            "online": players.get("online", 0),
            "max": players.get("max", 0),
            "names": [p["name"] for p in players.get("sample", [])]
        }))
    except Exception:
        sys.exit(1)
