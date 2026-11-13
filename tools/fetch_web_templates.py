"""从 Godot 官方 .tpz 模板包中只取 Web 导出所需文件。

整个包 1.28 GB，但 Web 模板只有几十 MB。Zip 的中央目录在文件末尾，
所以先用 HTTP Range 把目录读出来，再按偏移量单独取目标条目。
"""
import os
import re
import struct
import sys
import urllib.request
import zlib

URL = ("https://godot-releases.nbg1.your-objectstorage.com/"
       "4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz")
VERSION = "4.7.2.stable"
DEST = os.path.join(os.environ["APPDATA"], "Godot", "export_templates", VERSION)


def fetch(start: int, end: int) -> bytes:
    req = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def main() -> None:
    req = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as resp:
        total = int(resp.headers["Content-Length"])
    print(f"remote size: {total}")

    # 末尾 256 KB 一定覆盖 EOCD（可能还带 zip64 定位器）
    tail_start = max(0, total - 262144)
    tail = fetch(tail_start, total - 1)
    pos = tail.rfind(b"PK\x05\x06")
    if pos < 0:
        raise SystemExit("EOCD not found")
    cd_size, cd_offset = struct.unpack("<II", tail[pos + 12:pos + 20])
    entries_total = struct.unpack("<H", tail[pos + 10:pos + 12])[0]
    print(f"central dir: offset={cd_offset} size={cd_size} entries~{entries_total}")

    cd = fetch(cd_offset, cd_offset + cd_size - 1)

    targets = {}
    p = 0
    while p + 46 <= len(cd) and cd[p:p + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[p + 10:p + 12])
        csize, usize = struct.unpack("<II", cd[p + 20:p + 28])
        nlen, elen, clen = struct.unpack("<HHH", cd[p + 28:p + 34])
        lho, = struct.unpack("<I", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + nlen].decode("utf-8", "replace")
        if re.match(r"templates/(version\.txt|web[^/]*\.zip)$", name):
            targets[name] = (method, csize, usize, lho)
        p += 46 + nlen + elen + clen

    if not targets:
        raise SystemExit("no web templates found in archive")
    for name in sorted(targets):
        print("  found", name, targets[name][2], "bytes")

    os.makedirs(DEST, exist_ok=True)
    for name, (method, csize, usize, lho) in sorted(targets.items()):
        head = fetch(lho, lho + 29)
        nlen, elen = struct.unpack("<HH", head[26:30])
        data_start = lho + 30 + nlen + elen
        raw = fetch(data_start, data_start + csize - 1)
        if method == 0:
            data = raw
        else:
            data = zlib.decompress(raw, -15)
        if len(data) != usize:
            raise SystemExit(f"{name}: size mismatch {len(data)} != {usize}")
        out = os.path.join(DEST, os.path.basename(name))
        with open(out, "wb") as fh:
            fh.write(data)
        print(f"wrote {out} ({len(data)} bytes)")

    print("DEST:", DEST)


if __name__ == "__main__":
    main()
