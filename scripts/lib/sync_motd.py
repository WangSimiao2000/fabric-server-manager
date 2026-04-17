"""同步 motd 配置到 server.properties 和 MiniMOTD（由 cmd_start 调用）。

用法: python3 sync_motd.py <config.json> <game_dir>
从 config.json 读取 server.motd 配置，写入:
  - server.properties 的 motd= 行
  - config/MiniMOTD/main.conf 的 line1/line2（如果存在）
"""
import json, re, sys

config_file, game_dir = sys.argv[1], sys.argv[2]
with open(config_file) as f:
    c = json.load(f)

motd = c['server'].get('motd', {})
jar = c['server']['fabric_jar']
ver = re.search(r'mc\.([0-9]+\.[0-9]+(?:\.[0-9]+)?)', jar)
ver = ver.group(1) if ver else ''

# 更新 server.properties
sp = game_dir + '/server.properties'
with open(sp) as f:
    lines = f.readlines()
with open(sp, 'w') as f:
    for l in lines:
        if l.startswith('motd='):
            f.write('motd=' + motd.get('server_list', '') + '\n')
        else:
            f.write(l)

# 更新 MiniMOTD 配置（可选）
mc = game_dir + '/config/MiniMOTD/main.conf'
try:
    with open(mc) as f:
        txt = f.read()
    if 'line1' in motd:
        txt = re.sub(r'line1="[^"]*"', 'line1="' + motd['line1'] + '"', txt)
    if 'line2' in motd:
        line2 = motd['line2'].replace('{version}', ver)
        txt = re.sub(r'line2="[^"]*"', 'line2="' + line2 + '"', txt)
    with open(mc, 'w') as f:
        f.write(txt)
except FileNotFoundError:
    pass
