"""导出后给网页游戏包打版本戳。

同一个人反复覆盖发布同一个链接时，浏览器会记住上一次的 index.pck。
文件名一成不变，玩家刷新后仍可能跑旧代码（例如旧版只有一个技能）。
这里把数据包另存为 index.<内容摘要>.pck，并通过引擎官方的 mainPack 配置
指向它：代码一变，文件名就变，浏览器必然重新下载，不用手动强制刷新。
"""
import hashlib
import re
import shutil
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1] / "build" / "web"
PCK = WEB / "index.pck"
HTML = WEB / "index.html"


def main() -> int:
    if not PCK.exists() or not HTML.exists():
        print("[stamp] build/web 不完整，跳过")
        return 0

    digest: str = hashlib.sha256(PCK.read_bytes()).hexdigest()[:10]
    stamped: Path = WEB / ("index.%s.pck" % digest)
    if not stamped.exists():
        shutil.copy2(PCK, stamped)
    # 只留当前这一份带戳的包，避免旧版本越堆越多、每次发布都一起上传。
    for old in WEB.glob("index.*.pck"):
        if old != stamped:
            old.unlink()

    html: str = HTML.read_text(encoding="utf-8")
    # 让脚本可以重复运行：先撤掉上一次打过的标记。
    html = re.sub(r'"mainPack":"[^"]*",', "", html)
    html = re.sub(r'"fileSizes":\{"index\.[0-9a-f]+\.pck"',
                  '"fileSizes":{"index.pck"', html)
    needle: str = '"fileSizes":{"index.pck"'
    if needle not in html:
        print("[stamp] index.html 结构变了，未打戳")
        return 1
    html = html.replace(needle,
                        '"mainPack":"%s","fileSizes":{"%s"' % (stamped.name, stamped.name),
                        1)
    HTML.write_text(html, encoding="utf-8")
    print("[stamp] %s  (%d bytes)" % (stamped.name, PCK.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
