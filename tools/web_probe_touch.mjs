// 触摸冒烟 + 视觉验证：模拟手机触屏，确认虚拟摇杆与暂停按钮在 Web 下工作且无报错。
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const PORT = 9334;
const CDP_PORT = 9335;
const PAGE_URL = `http://127.0.0.1:${PORT}/index.html`;
const OUT_DIR = 'art/preview';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class CDP {
  constructor(ws) { this.ws = ws; this.seq = 0; this.pending = new Map(); this.handlers = [];
    ws.addEventListener('message', (ev) => { const m = JSON.parse(String(ev.data));
      if (m.id && this.pending.has(m.id)) { const { res, rej } = this.pending.get(m.id); this.pending.delete(m.id);
        if (m.error) rej(new Error(JSON.stringify(m.error))); else res(m.result); }
      else if (m.method) for (const h of this.handlers) h(m); }); }
  send(method, params = {}, sessionId) { const id = ++this.seq;
    return new Promise((res, rej) => { this.pending.set(id, { res, rej });
      const p = { id, method, params }; if (sessionId) p.sessionId = sessionId; this.ws.send(JSON.stringify(p)); }); }
  on(fn) { this.handlers.push(fn); }
}

async function waitDevtools(timeoutMs = 20000) {
  const d = Date.now() + timeoutMs;
  while (Date.now() < d) { try { const r = await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`); if (r.ok) return await r.json(); } catch {} await sleep(300); }
  throw new Error('devtools never came up');
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  // 启动本地静态服务器（serve_web.py 直接服务 build/web）
  const server = spawn('python', ['tools/serve_web.py', '--port', String(PORT)], { stdio: 'ignore' });
  await sleep(1500);

  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-edge-'));
  const args = ['--headless=new', `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--disable-background-timer-throttling', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--window-size=1280,760', '--hide-scrollbars', 'about:blank'];
  const browser = spawn(EDGE, args, { stdio: 'ignore' });
  const logs = [], errors = [];
  try {
    const version = await waitDevtools();
    const ws = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.addEventListener('open', res, { once: true }); ws.addEventListener('error', rej, { once: true }); });
    const cdp = new CDP(ws);
    cdp.on((m) => {
      if (m.method === 'Runtime.consoleAPICalled') { const t = (m.params.args || []).map((a) => a.value !== undefined ? a.value : a.description || '').join(' ');
        logs.push(`[${m.params.type}] ${t}`); if (m.params.type === 'error') errors.push(t); }
      else if (m.method === 'Runtime.exceptionThrown') { const d = m.params.exceptionDetails; errors.push(`EXCEPTION: ${d.text} ${d.exception?.description || ''}`); }
      else if (m.method === 'Log.entryAdded') { const e = m.params.entry; logs.push(`[log:${e.level}] ${e.text}`); if (e.level === 'error') errors.push(e.text); }
    });
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Log.enable', {}, sessionId);
    await cdp.send('Page.enable', {}, sessionId);
    // 开启触摸模拟，让 Godot 收到 InputEventScreenTouch
    await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 }, sessionId);

    await cdp.send('Page.navigate', { url: PAGE_URL }, sessionId);
    const bootDeadline = Date.now() + 90000; let booted = false;
    while (Date.now() < bootDeadline) { if (logs.some((l) => l.includes('Godot Engine v'))) { booted = true; break; } await sleep(400); }
    console.log('booted:', booted);
    if (!booted) { console.log(logs.join('\n')); errors.push('engine never booted'); }

    const shot = async (name) => { const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' }, sessionId);
      const out = path.join(OUT_DIR, name); fs.writeFileSync(out, Buffer.from(data, 'base64')); console.log('saved', out); };

    await sleep(3500);
    await shot('touch_title.png');

    // 空格开局（键盘仍可用）
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', code: 'Space', key: ' ', windowsVirtualKeyCode: 32, text: ' ' }, sessionId);
    await sleep(80);
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', code: 'Space', key: ' ', windowsVirtualKeyCode: 32 }, sessionId);
    await sleep(1200);

    // 先点一下画布中心，给 Godot 画布焦点（无头环境下合成指针输入常因缺焦点被忽略）
    await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: 640, y: 380, button: 'left', clickCount: 1 }, sessionId);
    await sleep(60);
    await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 640, y: 380, button: 'left', clickCount: 1 }, sessionId);
    await sleep(200);

    // 模拟左半屏触摸拖动：起点(220,470) -> 终点(330,470)，产生 +x 方向摇杆向量
    const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent',
      type === 'touchEnd' ? { type, touchPoints: [] } : { type, touchPoints: [{ x, y, id: 0 }] }, sessionId);
    await touch('touchStart', 220, 470);
    await sleep(120);
    await touch('touchMove', 260, 470);
    await sleep(120);
    await touch('touchMove', 330, 470);
    await sleep(900);
    await shot('touch_joystick.png');
    await touch('touchEnd');
    await sleep(400);

    // 暂停：用 ESC 键（键盘路径）确认暂停面板与静音按钮渲染
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', code: 'Escape', key: 'Escape', windowsVirtualKeyCode: 27 }, sessionId);
    await sleep(80);
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', code: 'Escape', key: 'Escape', windowsVirtualKeyCode: 27 }, sessionId);
    await sleep(700);
    await shot('touch_pause.png');

    console.log('--- errors ---');
    console.log(errors.length ? errors.join('\n') : '(none)');
    await cdp.send('Target.closeTarget', { targetId });
    ws.close();
  } finally {
    browser.kill(); server.kill(); await sleep(400);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
  }
}
main().catch((e) => { console.error('PROBE FAILED:', e); process.exit(1); });
