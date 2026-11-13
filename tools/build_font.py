"""把完整的中文字体裁剪成只含本项目用到的字，供网页版打包使用。

Web 导出里没有系统字体可回退，而 Godot 内置默认字体不含 CJK 字形，
中文会全部渲染成方框。整包思源黑体 11 MB 又太重，所以从源码里扫出
实际出现过的字符做子集化 —— 通常只剩一两百 KB。

改了游戏文案之后重跑一次即可：python tools/build_font.py
"""
import os
import pathlib
import subprocess
import sys
import tempfile

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = pathlib.Path(os.environ.get(
    "FONT_SRC", ROOT / "tools" / "fonts_src" / "NotoSansSC_400Regular.ttf"))
DST_DIR = ROOT / "assets" / "fonts"
DST = DST_DIR / "NotoSansSC-Subset.ttf"

SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".cfg", ".html"}
SKIP_DIRS = {".godot", "build", "tools", ".git", "node_modules"}

# 永远保留的字符：ASCII 可打印区、全角区、常用标点与符号。
# 哪怕将来新增文案没重跑脚本，这些也不会掉字形。
ALWAYS = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "".join(chr(c) for c in range(0xFF01, 0xFF5F))
    + "、。！？；：“”‘’（）《》〈〉【】—…·～￥°×÷±√∞★☆●○◆◇■□▲▼←→↑↓"
)


def collect_chars() -> set[str]:
    chars: set[str] = set(ALWAYS)
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SCAN_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            chars.update(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
    # 换行/制表符这类控制字符会从源码里被扫进来，但它们不需要字形
    chars = {c for c in chars if ord(c) >= 0x20}
    return chars


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"找不到源字体：{SRC}\n可用环境变量 FONT_SRC 指定路径。")

    chars = collect_chars()
    cjk = sorted(c for c in chars if "\u4e00" <= c <= "\u9fff")
    print(f"扫描到 {len(chars)} 个字符，其中汉字 {len(cjk)} 个")

    DST_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt",
                                     delete=False) as fh:
        fh.write("".join(sorted(chars)))
        text_file = fh.name

    try:
        subset.main([
            str(SRC),
            f"--text-file={text_file}",
            f"--output-file={DST}",
            "--layout-features=*",
            "--name-IDs=*",
            "--name-legacy",
            "--name-languages=*",
            "--recommended-glyphs",
            "--no-hinting",
            "--desubroutinize",
        ])
    finally:
        os.unlink(text_file)

    # 再核对一遍：子集化的 cmap 必须覆盖全部要用的字符
    from fontTools.ttLib import TTFont

    font = TTFont(DST)
    cmap: set[int] = set()
    for table in font["cmap"].tables:
        cmap.update(table.cmap.keys())
    missing = [c for c in chars if ord(c) not in cmap]
    size_kb = DST.stat().st_size / 1024
    print(f"输出 {DST}  ({size_kb:.0f} KB, {len(cmap)} 个码位)")
    if missing:
        raise SystemExit("缺字：" + "".join(missing[:50]))
    print("覆盖校验通过")


if __name__ == "__main__":
    main()
