"""把网页成品同步到 docs/，供 GitHub Pages 发布。

GitHub Pages 只能从仓库根目录或 /docs 发布，不能直接指向 build/web。
每次导出后运行本脚本：先清掉 docs 里上一版的文件（保留 .nojekyll），
再完整复制 build/web，避免带版本戳的旧数据包越堆越多。
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "build" / "web"
DOCS = ROOT / "docs"


def main() -> int:
    if not (WEB / "index.html").exists():
        print("[docs] build/web 不存在，跳过同步")
        return 0

    DOCS.mkdir(exist_ok=True)
    for item in DOCS.iterdir():
        if item.name == ".nojekyll":
            continue
        if item.is_dir():
            shutil.rmtree(item)
        else:
            item.unlink()

    count: int = 0
    for item in WEB.iterdir():
        dest = DOCS / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)
        count += 1
    (DOCS / ".nojekyll").touch()
    print("[docs] 已同步 %d 个文件到 docs/" % count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
