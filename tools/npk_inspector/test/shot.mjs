// 用 Chrome（找不到才用 Edge）headless + CDP 截图（图从 base64 写回工作区，绕开浏览器落盘权限问题）
// 用法: node shot.mjs --url http://localhost:8766/web/index.html --out .tmp_shot/a.png --w 1600 --h 1000
//      --wait 1200 --port 9350 --user-dir 'E:\tmp_bprof_x'
// 经验：Edge headless 曾被发现在 Windows 侧残留一堆进程；优先 Chrome。每次用唯一 profile 目录，跑完删掉。
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const BROWSERS = [
  { name: 'Chrome', exe: '/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe' },
  { name: 'Chrome', exe: '/mnt/c/Program Files/Google/Chrome/Application/chrome.exe' },
  { name: 'Edge', exe: '/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' },
];
const BROWSER = BROWSERS.find(b => fs.existsSync(b.exe));
if (!BROWSER) { console.error('[shot] 找不到 Chrome 或 Edge'); process.exit(1); }
const argv = process.argv.slice(2);
const opts = {
  url: 'http://localhost:8766/web/index.html',
  out: 'shot.png', w: 1600, h: 1000, wait: 1400,
  port: 9350 + (process.pid % 40),
  userDir: 'E:\\tmp_bprof_' + process.pid + '_' + Math.floor(Math.random()*1000),
  attach: 0, eval: '', dl: '',
};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--url') opts.url = argv[++i];
  else if (a === '--out') opts.out = argv[++i];
  else if (a === '--w') opts.w = +argv[++i];
  else if (a === '--h') opts.h = +argv[++i];
  else if (a === '--wait') opts.wait = +argv[++i];
  else if (a === '--port') opts.port = +argv[++i];
  else if (a === '--user-dir') opts.userDir = argv[++i];
  else if (a === '--attach') opts.attach = +argv[++i];
  else if (a === '--eval') opts.eval = argv[++i];
  else if (a === '--dl') opts.dl = argv[++i];
}
const log = (...a) => console.error('[shot]', ...a);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const hardTimer = setTimeout(() => { log('整体超时'); try { edge && edge.kill('SIGKILL'); } catch {} cleanupProfile(opts.userDir); process.exit(3); }, 60000);

let edge = null;

// E:\xx → /mnt/e/xx，用于删 profile 目录
function wslPath(p) {
  const m = /^([A-Za-z]):[\\/](.*)$/.exec(p);
  return m ? '/mnt/' + m[1].toLowerCase() + '/' + m[2].replace(/\\/g, '/') : p;
}
// 注意：WSL 侧对被沙箱限制的盘（如 /mnt/e）删不动，必须交回 Windows 删
const POWERSHELL = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
function ps(command) {
  try {
    const r = spawnSync(POWERSHELL, ['-NoProfile', '-Command', command], { stdio: 'ignore', timeout: 30000 });
    return r.status === 0;
  } catch { return false; }
}
let swept = false;
function cleanupProfile(dir) {
  swept = true;
  ps(`Remove-Item -LiteralPath '${dir}' -Recurse -Force -ErrorAction SilentlyContinue`);
}
// 启动时顺手清掉以前跑剩的 headless profile 目录（E:\tmp_bprof_* / tmp_edgeprof_*）
function sweepProfiles() {
  const ok = ps(`Get-ChildItem 'E:\' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'tmp_bprof_*' -or $_.Name -like 'tmp_edgeprof_*' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue`);
  if (ok) log('已清理旧 profile 目录');
}
sweepProfiles();
// 先让浏览器自己优雅退出（连带子进程），再补一刀，最后删 profile
async function shutdownBrowser() {
  if (!opts.attach && edge) {
    try {
      const v = await (await fetch(`http://127.0.0.1:${opts.port}/json/version`, { signal: AbortSignal.timeout(1500) })).json();
      const bws = new WebSocket(v.webSocketDebuggerUrl);
      await new Promise((res, rej) => { bws.onopen = res; bws.onerror = rej; setTimeout(rej, 1500); });
      bws.send(JSON.stringify({ id: 1, method: 'Browser.close' }));
      await sleep(400); bws.close();
    } catch {}
    const exited = new Promise(res => { try { edge.once('exit', res); } catch { res(); } setTimeout(res, 2000); });
    try { edge.kill('SIGKILL'); } catch {}
    await exited;
    await sleep(150);
  }
  cleanupProfile(opts.userDir);
}
async function json(url, tries = 50, timeout = 1200) {
  let last;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(timeout) });
      if (r.ok) return await r.json();
      last = new Error('HTTP ' + r.status);
    } catch (e) { last = e; }
    await sleep(200);
  }
  throw last;
}

try {
  if (!opts.attach) {
    let spawned = false;
    for (let attempt = 0; attempt < 3 && !spawned; attempt++) {
      const port = opts.port + attempt;
      edge = spawn(BROWSER.exe, [
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
        '--no-default-browser-check', '--disable-extensions',
        `--remote-debugging-port=${port}`,
        `--user-data-dir=${opts.userDir}`,
        `--window-size=${opts.w},${opts.h}`, 'about:blank',
      ], { stdio: ['ignore', 'ignore', 'pipe'] });
      let err = '';
      edge.stderr.on('data', d => { err += d.toString(); });
      try {
        const v = await json(`http://127.0.0.1:${port}/json/version`, 30);
        opts.port = port; spawned = true;
        log(BROWSER.name + ' 就绪', v.Browser);
      } catch (e) {
        log('端口', port, '未就绪:', e.cause?.code || e.name);
        try { edge.kill('SIGKILL'); } catch {}
        await sleep(400);
      }
    }
    if (!spawned) { log(BROWSER.name + ' 起不来'); cleanupProfile(opts.userDir); process.exit(1); }
  }
  // 新开一个干净的 page target
  const target = await (async () => {
    try {
      const r = await fetch(`http://127.0.0.1:${opts.port}/json/new?${encodeURIComponent('about:blank')}`, { method: 'PUT', signal: AbortSignal.timeout(3000) });
      if (r.ok) return await r.json();
    } catch {}
    const list = await json(`http://127.0.0.1:${opts.port}/json/list`);
    return list.find(t => t.type === 'page');
  })();
  if (!target) throw new Error('没有 page target');
  log('target', target.id);

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0; const pending = new Map(); const events = [];
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('WebSocket 连接失败')); });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.rej(new Error(m.error.message)) : p.res(m.result); }
    else if (m.method) events.push(m);
  };
  const send = (method, params = {}) => new Promise((res, rej) => {
    const mid = ++id; pending.set(mid, { res, rej });
    ws.send(JSON.stringify({ id: mid, method, params }));
  });

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: opts.w, height: opts.h, deviceScaleFactor: 1, mobile: false });
  log('navigate', opts.url);
  await send('Page.navigate', { url: opts.url });
  const t0 = Date.now();
  while (Date.now() - t0 < 20000) {
    if (events.some(e => e.method === 'Page.loadEventFired')) break;
    await sleep(80);
  }
  await sleep(opts.wait);
  const errors = await send('Runtime.evaluate', { expression: 'window.__uiErrors || null', returnByValue: true }).catch(() => null);
  if (errors && errors.result && errors.result.value) log('页面错误:', JSON.stringify(errors.result.value));
  if (opts.dl) {
    try { await send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: opts.dl, eventsEnabled: true }); log('下载目录', opts.dl); }
    catch (e) { log('下载目录设置失败', e.message); }
    await new Promise(r => setTimeout(r, 1200));
  }
  if (opts.eval) {
    const r2 = await send('Runtime.evaluate', { expression: opts.eval, returnByValue: true, awaitPromise: true });
    console.log('EVAL:', JSON.stringify(r2.result?.value ?? r2.result?.description ?? r2, null, 1).slice(0, 4000));
  }
  const bad = events.filter(e => e.method === 'Runtime.exceptionThrown' || (e.method === 'Runtime.consoleAPICalled' && e.params.type === 'error'));
  for (const b of bad.slice(-6)) {
    if (b.method === 'Runtime.exceptionThrown') log('JS 异常:', b.params.exceptionDetails.exception?.description || b.params.exceptionDetails.text);
    else log('console.error:', (b.params.args || []).map(a => a.value ?? a.description).join(' '));
  }
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  const buf = Buffer.from(shot.data, 'base64');
  const out = path.resolve(opts.out);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, buf);
  console.log(`✓ ${opts.out} ${buf.length} bytes ${opts.w}x${opts.h}`);
  ws.close();
  try { await fetch(`http://127.0.0.1:${opts.port}/json/close/${target.id}`); } catch {}
  clearTimeout(hardTimer);
  await shutdownBrowser();
  process.exit(0);
} catch (e) {
  log('失败:', e.message);
  clearTimeout(hardTimer);
  await shutdownBrowser();
  process.exit(2);
}
