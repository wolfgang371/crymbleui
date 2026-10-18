// Shared by the browser checks: a static server for a bin/web/<target>/ folder and headless Chromium (playwright-core,
// pinned in package.json; its browser via `npx playwright-core install chromium-headless-shell`).
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { chromium } from 'playwright-core';

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.png': 'image/png', '.json': 'application/json' };

// Serve `dir` on 127.0.0.1 (a free port). Resolves to { url, close }.
export function serve(dir) {
  const server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
    const file = join(dir, path.endsWith('/') ? path + 'index.html' : path);
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': TYPES[extname(file)] || 'text/plain' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () =>
    resolve({ url: `http://127.0.0.1:${server.address().port}/`, close: () => server.close() })));
}

export async function launch() {
  return chromium.launch(process.env.CRYMBLE_CHROMIUM ? { executablePath: process.env.CRYMBLE_CHROMIUM } : {});
}

// Open the page, wait until the app runs (or the page reports why not); console lines and page errors collected.
export async function open(browser, url, { viewport = { width: 1000, height: 700 }, init } = {}) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const log = [];
  page.on('console', (m) => log.push({ type: m.type(), text: m.text() }));
  page.on('pageerror', (e) => log.push({ type: 'pageerror', text: e.message }));
  if (init) await page.addInitScript(init);
  await page.goto(url);
  await page.waitForFunction(() => document.getElementById('overlay')?.classList.contains('hidden') ||
    !/Loading|Starting/.test(document.getElementById('msg')?.textContent || ''), null, { timeout: 120000 });
  return { context, page, log };
}
