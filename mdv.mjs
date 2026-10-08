#!/usr/bin/env node
// mdv — a clean local markdown viewer with a CLI handle. Zero deps, Node 18+.
//
//   mdv <file.md>       ensure the server is up, print the file's viewer URL
//   mdv <file.md> -b    same, and open it in the default browser
//   mdv serve           run the server in the foreground
//   mdv status          is the server up?
//   mdv stop            stop the running server
//
// Server binds 127.0.0.1 only and serves files under ~ or /tmp.

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SELF = fileURLToPath(import.meta.url);
const HERE = path.dirname(SELF);
const PORT = Number(process.env.MDV_PORT || 4747);
const HOST = '127.0.0.1';
const BASE = `http://localhost:${PORT}`;
const HOME = os.homedir();
const ROOTS = [HOME, '/tmp', '/private/tmp'];
const RECENT = path.join(HERE, '.recent.json');
const MAX_RECENT = 40;
const TEXT_EXT = new Set(['.md', '.markdown', '.mdx', '.txt']);
const MIME = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.webp': 'image/webp',
};
const USAGE = `usage: mdv <file.md> [-b]   |   mdv serve | status | stop`;

// ---------- helpers ----------
const json = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
};
const text = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
  res.end(body);
};
const real = p => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
const pretty = p => (p === HOME || p.startsWith(HOME + path.sep)) ? '~' + p.slice(HOME.length) : p;

function safePath(p) {
  if (!p) return null;
  const abs = path.resolve(p);
  const r = real(abs);
  const ok = ROOTS.some(root => { const rr = real(root); return r === rr || r.startsWith(rr + path.sep); });
  return ok ? abs : null;
}

function readRecent() {
  try { return JSON.parse(fs.readFileSync(RECENT, 'utf8')); } catch { return []; }
}
function pushRecent(p) {
  const list = readRecent().filter(e => e.path !== p);
  list.unshift({ path: p, openedAt: Date.now() });
  fs.writeFileSync(RECENT, JSON.stringify(list.slice(0, MAX_RECENT), null, 2));
}
function listRecent() {
  return readRecent()
    .filter(e => fs.existsSync(e.path))
    .map(e => ({ ...e, name: path.basename(e.path), dir: pretty(path.dirname(e.path)) }));
}

// ---------- server ----------
function serve() {
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, BASE);
    const p = url.searchParams.get('path');
    try {
      switch (url.pathname) {
        case '/': {
          res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
          return res.end(await fsp.readFile(path.join(HERE, 'index.html')));
        }
        case '/api/ping': return json(res, 200, { ok: true, pid: process.pid, port: PORT });
        case '/api/shutdown': { json(res, 200, { ok: true }); return setTimeout(() => process.exit(0), 50); }
        case '/api/recent': return json(res, 200, listRecent());
        case '/api/stat': {
          const f = safePath(p); if (!f) return text(res, 400, 'bad path');
          const st = await fsp.stat(f);
          return json(res, 200, { mtime: st.mtimeMs, size: st.size });
        }
        case '/api/file': {
          const f = safePath(p); if (!f) return text(res, 400, 'Path must be under ~ or /tmp.');
          if (!TEXT_EXT.has(path.extname(f).toLowerCase())) return text(res, 415, 'Not a markdown or text file.');
          const st = await fsp.stat(f);
          const content = await fsp.readFile(f, 'utf8');
          pushRecent(f);
          return json(res, 200, {
            path: f, name: path.basename(f), dir: path.dirname(f),
            prettyDir: pretty(path.dirname(f)), mtime: st.mtimeMs, size: st.size, content,
          });
        }
        case '/api/raw': {
          const f = safePath(p); if (!f) return text(res, 400, 'bad path');
          const mime = MIME[path.extname(f).toLowerCase()]; if (!mime) return text(res, 415, 'unsupported');
          await fsp.access(f);
          res.writeHead(200, { 'content-type': mime, 'cache-control': 'no-store' });
          return fs.createReadStream(f).pipe(res);
        }
        default: return text(res, 404, 'not found');
      }
    } catch (e) {
      if (e.code === 'ENOENT') return text(res, 404, 'File not found: ' + p);
      return text(res, 500, String(e.message || e));
    }
  });
  server.listen(PORT, HOST, () => console.error(`mdv serving on ${BASE} (pid ${process.pid})`));
  server.on('error', e => { console.error('mdv:', e.message); process.exit(1); });
}

// ---------- cli ----------
async function ping(ms = 400) {
  try {
    const r = await fetch(`${BASE}/api/ping`, { signal: AbortSignal.timeout(ms) });
    return r.ok ? await r.json() : null;
  } catch { return null; }
}

async function ensureServer() {
  if (await ping()) return 'already running';
  const child = spawn(process.execPath, [SELF, 'serve'], { detached: true, stdio: 'ignore', cwd: HERE });
  child.unref();
  for (let i = 0; i < 40; i++) {
    await new Promise(r => setTimeout(r, 100));
    if (await ping()) return 'started';
  }
  throw new Error(`server did not come up on ${BASE}`);
}

async function main() {
  const args = process.argv.slice(2);
  const cmd = args[0];
  if (!cmd || cmd === '-h' || cmd === '--help') return console.log(USAGE);
  if (cmd === 'serve') return serve();
  if (cmd === 'status') { const s = await ping(); return console.log(s ? `running (pid ${s.pid}) ${BASE}` : 'not running'); }
  if (cmd === 'stop') {
    if (!(await ping())) return console.log('not running');
    await fetch(`${BASE}/api/shutdown`).catch(() => {});
    return console.log('stopped');
  }
  const file = args.find(a => !a.startsWith('-'));
  if (!file) return console.log(USAGE);
  const abs = path.resolve(file);
  if (!fs.existsSync(abs)) { console.error(`mdv: no such file: ${abs}`); process.exit(1); }
  if (!safePath(abs)) { console.error('mdv: file must live under ~ or /tmp'); process.exit(1); }
  const state = await ensureServer();
  const url = `${BASE}/?f=${encodeURIComponent(abs)}`;
  console.error(`mdv: server ${state}`);
  console.log(url);
  if (args.includes('-b') || args.includes('--browser')) spawn('open', [url], { stdio: 'ignore', detached: true }).unref();
}

main().catch(e => { console.error('mdv:', e.message); process.exit(1); });
