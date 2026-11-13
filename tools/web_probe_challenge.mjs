// 挑战模式专用探针：标题页 → 按 C 打开选关 → 截图 → 回车进入第 1 关 → 走位 → 截图。
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const PORT = Number(process.env.CDP_PORT || 9334);
const PAGE_URL = process.env.PAGE_URL || 'http://127.0.0.1:8123/index.html';
const OUT_DIR = process.env.OUT_DIR || 'art/preview';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class CDP {
  constructor(ws) {
    this.ws = ws; this.seq = 0; this.pending = new Map(); this.handlers = [];
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.id && this.pending.has(msg.id)) {
        const { res, rej } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) rej(new Error(JSON.stringify(msg.error))); else res(msg.result);
      } else if (msg.method) { for (const h of this.handlers) h(msg); }
    });
  }
  send(method, params = {}, sessionId = undefined) {
    const id = ++this.seq;
    return new Promise((res, rej) => {
      this.pending.set(id, { res, rej });
      const payload = { id, method, params };
      if (sessionId) payload.sessionId = sessionId;
      this.ws.send(JSON.stringify(payload));
    });
  }
  on(fn) { this.handlers.push(fn); }
}

async function waitForDevtools(timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try { const r = await fetch(`http://127.0.0.1:${PORT}/json/version`); if (r.ok) return await r.json(); } catch {}
    await sleep(300);
  }
  throw new Error('devtools never came up');
}

async function main() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-edge-'));
  const args = [
    '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-extensions',
    '--disable-background-timer-throttling', '--enable-unsafe-swiftshader',
    '--use-angle=swiftshader', '--window-size=1280,760', '--hide-scrollbars', 'about:blank',
  ];
  const browser = spawn(EDGE, args, { stdio: 'ignore' });
  const logs = [], errors = [];
  try {
    const version = await waitForDevtools();
    const ws = new WebSocket(version.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.addEventListener('open', res, { once: true }); ws.addEventListener('error', rej, { once: true }); });
    const cdp = new CDP(ws);
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    cdp.on((msg) => {
      if (msg.method === 'Runtime.consoleAPICalled') {
        const text = (msg.params.args || []).map((a) => (a.value !== undefined ? a.value : a.description || '')).join(' ');
        logs.push(`[${msg.params.type}] ${text}`);
        if (msg.params.type === 'error') errors.push(text);
      } else if (msg.method === 'Runtime.exceptionThrown') {
        const d = msg.params.exceptionDetails; errors.push(`EXCEPTION: ${d.text} ${d.exception?.description || ''}`);
      } else if (msg.method === 'Log.entryAdded') {
        const e = msg.params.entry; logs.push(`[log:${e.level}] ${e.text}`); if (e.level === 'error') errors.push(e.text);
      }
    });
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Log.enable', {}, sessionId);
    await cdp.send('Page.enable', {}, sessionId);
    await cdp.send('Page.navigate', { url: PAGE_URL }, sessionId);

    const bootDeadline = Date.now() + 90000;
    let booted = false;
    while (Date.now() < bootDeadline) {
      if (logs.some((l) => l.includes('Godot Engine v'))) { booted = true; break; }
      await sleep(400);
    }
    console.log('booted:', booted);
    if (!booted) { console.log(logs.join('\n')); errors.push('engine never booted'); }

    const shot = async (name) => {
      const { data } = await cdp.send('Page.captureScreenshot', { format: 'png' }, sessionId);
      fs.writeFileSync(path.join(OUT_DIR, name), Buffer.from(data, 'base64'));
      console.log('saved', name);
    };
    const key = async (code, vk, ch, text) => {
      const t = text === undefined ? ch : text;
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', code, key: ch, text: t, windowsVirtualKeyCode: vk }, sessionId);
      await sleep(70);
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', code, key: ch, text: '', windowsVirtualKeyCode: vk }, sessionId);
      await sleep(120);
    };

    await sleep(4000);
    await shot('web_title.png');

    // 打开挑战选关
    await key('KeyC', 67, 'c');
    await sleep(1500);
    await shot('web_select.png');

    // 进入默认选中的第 1 关
    await key('Enter', 13, 'Enter', '\r');
    await sleep(2000);
    await key('KeyW', 87, 'w');
    await sleep(2000);
    await key('KeyD', 68, 'd');
    await sleep(3000);
    await shot('web_challenge_play.png');

    // 再跑一段，看 HUD 上的剩余时间与关卡名
    await key('KeyA', 65, 'a');
    await sleep(5000);
    await shot('web_challenge_play2.png');

    console.log('--- console (last 30) ---');
    console.log(logs.slice(-30).join('\n'));
    console.log('--- errors ---');
    console.log(errors.length ? errors.join('\n') : '(none)');
    await cdp.send('Target.closeTarget', { targetId });
    ws.close();
  } finally {
    browser.kill();
    await sleep(400);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch {}
  }
}
main().catch((err) => { console.error('PROBE FAILED:', err); process.exit(1); });
