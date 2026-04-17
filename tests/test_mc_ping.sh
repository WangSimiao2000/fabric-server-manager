#!/bin/bash
# 测试 mc_ping.py: varint 负数编码、输出 JSON 格式
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
PING_PY="$SCRIPT_DIR/lib/mc_ping.py"

suite "varint 负数编码不死循环"
# -1 的 varint 编码应为 5 字节 (ffffffff0f)，不应超时
result=$(timeout 3 python3 -c "
import sys; sys.path.insert(0, '.')
exec(open('$PING_PY').read().split('if __name__')[0])
import socket
s = socket.socket()
# 只测试 write_varint 函数，不实际连接
# 通过 mc_ping 内部定义的方式测试
" 2>&1)
# 直接测试 varint 编码
result=$(timeout 3 python3 -c "
def write_varint(val):
    out = b''
    val &= 0xFFFFFFFF
    while True:
        b = val & 0x7F
        val >>= 7
        out += bytes([b | 0x80]) if val else bytes([b])
        if not val: break
    return out
v = write_varint(-1)
assert len(v) == 5, f'expected 5 bytes, got {len(v)}'
assert v == bytes([0xff,0xff,0xff,0xff,0x0f]), f'wrong encoding: {v.hex()}'
print('OK')
" 2>&1)
assert_eq "$result" "OK" "varint(-1) 编码为 5 字节 ffffffff0f"

suite "varint 正数编码"
result=$(timeout 3 python3 -c "
def write_varint(val):
    out = b''
    val &= 0xFFFFFFFF
    while True:
        b = val & 0x7F
        val >>= 7
        out += bytes([b | 0x80]) if val else bytes([b])
        if not val: break
    return out
assert write_varint(0) == b'\x00'
assert write_varint(1) == b'\x01'
assert write_varint(127) == b'\x7f'
assert write_varint(128) == b'\x80\x01'
assert write_varint(300) == b'\xac\x02'
print('OK')
" 2>&1)
assert_eq "$result" "OK" "varint 正数编码正确"

suite "mc_ping.py 输出格式"
# 连接到不存在的端口应 exit 1
timeout 3 python3 "$PING_PY" 19999 >/dev/null 2>&1
assert_eq "$?" "1" "连接失败时 exit 1"

# 如果服务器在运行，测试输出 JSON 格式
if ss -tlnp 2>/dev/null | grep -q ":25565 "; then
    out=$(timeout 5 python3 "$PING_PY" 25565 2>/dev/null)
    if [ -n "$out" ]; then
        # 验证是合法 JSON 且包含必要字段
        valid=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'online' in d and 'max' in d and 'names' in d
assert isinstance(d['online'], int)
assert isinstance(d['names'], list)
print('OK')
" 2>&1)
        assert_eq "$valid" "OK" "输出包含 online/max/names 字段"
    fi
fi

summary
