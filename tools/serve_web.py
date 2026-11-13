"""本地静态服务器，用来在浏览器里跑 Web 导出包。

直接用 python -m http.server 会有两个坑：
1) .wasm 的 MIME 不是 application/wasm，浏览器会退回非流式的实例化方式，加载变慢；
2) 缺少跨源隔离头，万一以后开了线程支持就会直接起不来。
"""
import argparse
import functools
import http.server
import mimetypes
import os
import socketserver
import threading
import webbrowser

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/octet-stream", ".pck")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        pass  # 安静一点，别把控制台刷满


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/web")
    ap.add_argument("--port", type=int, default=8123)
    ap.add_argument("--open", action="store_true", help="启动后自动打开浏览器")
    args = ap.parse_args()

    root = os.path.abspath(args.dir)
    if not os.path.isfile(os.path.join(root, "index.html")):
        raise SystemExit(f"{root} 里没有 index.html，先执行导出")
    handler = functools.partial(Handler, directory=root)
    socketserver.TCPServer.allow_reuse_address = True

    try:
        httpd = socketserver.TCPServer(("127.0.0.1", args.port), handler)
    except OSError:
        raise SystemExit(f"端口 {args.port} 已被占用。"
                         f"可能是上一次的服务还在跑，换个端口：--port {args.port + 1}")

    url = f"http://127.0.0.1:{args.port}/index.html"
    print(f"serving {root}")
    print(f"open in browser: {url}")
    print("Ctrl+C 或直接关闭本窗口即可停止。")
    if args.open:
        # 先绑好端口再开浏览器，避免浏览器抢在服务就绪前加载导致白屏
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()

    with httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
