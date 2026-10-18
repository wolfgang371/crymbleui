// The web flavour's smoke: crymble-ui's own examples, built unchanged by bin/crymble-web, driven in headless
// Chromium. Positions are hard-coded per example (a smoke, not a layout test); each check names what it holds and
// waits on the app going idle (__crymble.idle()) rather than on time. Any stderr line from an app, a page error or
// a failed check fails the run.
// usage: node smoke.mjs BIN_WEB_DIR   (bin/web, holding tutorial-22, tutorial-07, tutorial-24 and showcase_demo)
import { serve, launch, open } from './browser.mjs';

const root = process.argv[2];
const browser = await launch();
const failures = [];
let checks = 0;
function check(name, ok, detail = '') {
  checks++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` - ${detail}` : ''}`);
  if (!ok) failures.push(name);
}

// One example's page: { page, at(x, y) = page coordinates of canvas point, pixels(x, y, w, h), idle(), done() }
async function app(target, options = {}) {
  const server = await serve(`${root}/${target}`);
  const { context, page, log } = await open(browser, server.url, options);
  const ready = await page.evaluate(() => !!window.__crymble);
  const box = ready ? await page.locator('#app').boundingBox() : { x: 0, y: 0 };
  const a = {
    page, log,
    at: (x, y) => [box.x + x, box.y + y],
    click: async (x, y) => { await page.mouse.click(box.x + x, box.y + y); await a.idle(); },
    idle: () => page.evaluate(() => window.__crymble.idle()),
    // a canvas region's pixels as one string - for "did it change" and "is it the same again"
    region: (x, y, w, h) => page.evaluate(([x, y, w, h]) =>
      Array.from(document.getElementById('app').getContext('2d').getImageData(x, y, w, h).data).join(','), [x, y, w, h]),
    // how many pixels of the region are far from the colour at its top-left corner
    ink: (x, y, w, h) => page.evaluate(([x, y, w, h]) => {
      const d = document.getElementById('app').getContext('2d').getImageData(x, y, w, h).data;
      let n = 0;
      for (let i = 0; i < d.length; i += 4) if (Math.abs(d[i] - d[0]) + Math.abs(d[i + 1] - d[1]) + Math.abs(d[i + 2] - d[2]) > 120) n++;
      return n;
    }, [x, y, w, h]),
    key: (init) => page.evaluate((init) => {
      // a key the way a browser delivers it; the result says whether crymble-ui claimed it (preventDefault)
      let prevented = null;
      const seen = (e) => { prevented = e.defaultPrevented; };
      window.addEventListener('keydown', seen); // bubble phase, after the canvas's own listener
      document.getElementById('app').dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init }));
      document.getElementById('app').dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, ...init }));
      window.removeEventListener('keydown', seen);
      return prevented;
    }, init),
    done: async () => {
      const stderr = ready ? await page.evaluate(() => window.__crymble.stderr) : [];
      const errors = log.filter((l) => l.type === 'pageerror').map((l) => l.text);
      check(`${target}: no stderr, no page error`, stderr.length === 0 && errors.length === 0, [...stderr, ...errors].join(' | '));
      await context.close();
      server.close();
    },
  };
  return a;
}

// --- tutorial-22: VirtualMatrix - clicks, the wheel, blit-shift scrolling, and garbage collection ----------------
{
  const a = await app('tutorial-22');
  const header = [184, 90, 760, 60]; // the sticky column headers
  const body = [184, 170, 760, 300];
  await a.page.mouse.move(...a.at(500, 350)); // first: the hover moves with the mouse
  await a.idle();
  const [h0, b0] = [await a.region(...header), await a.region(...body)];
  await a.page.mouse.wheel(0, 300);
  await a.idle();
  check('tutorial-22: the wheel scrolls the body, the sticky headers stay',
    (await a.region(...body)) !== b0 && (await a.region(...header)) === h0);
  await a.page.mouse.wheel(0, -300);
  await a.idle();
  check('tutorial-22: scrolling back shows the same body again (blit-shift)', (await a.region(...body)) === b0);

  // (after the scroll checks: a clicked cell takes the matrix cursor, which changes the body)
  const toggle = [222, 47, 18, 18]; // the "Toggled by grid button" checkbox
  const before = await a.ink(...toggle);
  await a.click(543, 381); // the "Click" button in cell (9,3)
  check('tutorial-22: a click lands (the button toggles the checkbox)', (await a.ink(...toggle)) > before,
    `checkbox ink ${before} -> ${await a.ink(...toggle)}`);


  // 20 scroll cycles, collecting after each: the heap and the live canvases flat over cycles 2..20, and released
  // backends freeing their canvases (created and freed both move)
  const samples = [];
  let frameMs = [];
  for (let cycle = 1; cycle <= 20; cycle++) {
    const counts0 = await a.page.evaluate(() => window.__crymble.canvasCounts());
    for (const dy of [400, 400, -400, -400]) {
      const t0 = Date.now();
      await a.page.mouse.wheel(0, dy);
      await a.idle();
      frameMs.push(Date.now() - t0);
    }
    await a.page.evaluate(() => window.__crymble.gc(0));
    const s = await a.page.evaluate(() => ({ heap: window.__crymble.heapMB(), canvases: window.__crymble.canvases(), counts: window.__crymble.canvasCounts() }));
    s.made = s.counts.created - counts0.created;
    s.freed = s.counts.freed - counts0.freed;
    samples.push(s);
  }
  const later = samples.slice(1);
  const spread = (k) => Math.max(...later.map((s) => s[k])) - Math.min(...later.map((s) => s[k]));
  check('tutorial-22: heap flat over 20 scroll cycles', spread('heap') <= 2, `heap MB ${samples.map((s) => s.heap).join(' ')}`);
  check('tutorial-22: live canvases flat over 20 scroll cycles', spread('canvases') === 0,
    `live ${samples.map((s) => s.canvases).join(' ')}; per cycle made ${samples[1].made}, freed ${samples[1].freed}`);
  check('tutorial-22: scrolling makes and frees canvases', later.every((s) => s.made > 0 && s.freed > 0));
  frameMs.sort((x, y) => x - y);
  console.log(`info tutorial-22: wheel step to idle, median ${frameMs[frameMs.length >> 1]} ms, worst ${frameMs[frameMs.length - 1]} ms`);
  await a.done();
}

// --- tutorial-07: TextInput - typing, a Ctrl shortcut, AltGr, paste, copy, browser keys, the leave guard, resize ---
{
  const a = await app('tutorial-07', { viewport: { width: 1000, height: 700 } });
  await a.page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const leave = () => a.page.evaluate(() => { const e = new Event('beforeunload', { cancelable: true }); window.dispatchEvent(e); return e.defaultPrevented; });
  check('tutorial-07: leaving is not guarded before any input', (await leave()) === false);

  const value = [80, 92, 400, 16]; // the "Value: ..." line, right of its label
  await a.click(300, 67); // the first input
  await a.page.keyboard.type('Hallo');
  await a.idle();
  const typed = await a.ink(...value);
  check('tutorial-07: typing reaches the input (the value line shows it)', typed > 20, `ink ${typed}`);
  check('tutorial-07: leaving is guarded after input', (await leave()) === true);

  await a.key({ key: '@', code: 'KeyQ', ctrlKey: true, altKey: true }); // AltGr+Q on a German layout
  await a.idle();
  const withAt = await a.ink(...value);
  check('tutorial-07: AltGr types its character', withAt > typed, `ink ${typed} -> ${withAt}`);

  await a.page.keyboard.press('Control+a');
  await a.page.keyboard.press('Control+c');
  await a.idle();
  const copied = await a.page.evaluate(() => navigator.clipboard.readText());
  check('tutorial-07: Ctrl+C puts the text on the system clipboard', copied === 'Hallo@', JSON.stringify(copied));

  // a paste of text put on the system clipboard from outside the app: the browser's paste event carries it
  await a.page.keyboard.press('End');
  await a.page.evaluate(() => navigator.clipboard.writeText('XYZXYZXYZ'));
  await a.page.keyboard.press('Control+v');
  await a.idle();
  const pasted = await a.ink(...value);
  await a.page.keyboard.press('Control+a');
  await a.page.keyboard.press('Control+c');
  await a.idle();
  const afterPaste = await a.page.evaluate(() => navigator.clipboard.readText());
  check('tutorial-07: an external paste arrives', afterPaste === 'Hallo@XYZXYZXYZ', JSON.stringify(afterPaste));
  await a.page.keyboard.press('End');

  check('tutorial-07: Alt+Left is claimed (no history navigation)', (await a.key({ key: 'ArrowLeft', code: 'ArrowLeft', altKey: true })) === true);
  check('tutorial-07: F5 is left to the browser', (await a.key({ key: 'F5', code: 'F5' })) === false);

  const edge = [960, 55, 6, 30]; // the input's right border at the wide viewport
  const wide = await a.ink(...edge);
  await a.page.setViewportSize({ width: 700, height: 700 });
  const followed = await a.page.waitForFunction(() => document.getElementById('app').width <= 700, null, { timeout: 5000 })
    .then(() => true, () => false);
  await a.idle();
  const narrowEdge = await a.ink(656, 55, 6, 30);
  check('tutorial-07: a resized viewport resizes the canvas and the layout follows', followed && wide > 0 && narrowEdge > 0 &&
    (await a.ink(...edge)) === 0, `border ink wide ${wide}, narrow ${narrowEdge}`);
  await a.page.keyboard.type('!');
  await a.idle();
  check('tutorial-07: input still works after the resize', (await a.ink(...value)) > pasted);
  await a.done();
}

// --- tutorial-24: images arrive after their asynchronous decode ---------------------------------------------------
{
  const a = await app('tutorial-24');
  await a.page.waitForTimeout(300);
  await a.idle();
  check('tutorial-24: the image is drawn after its decode (late images re-render)', (await a.ink(30, 110, 100, 90)) > 2000,
    `ink ${await a.ink(30, 110, 100, 90)}`);
  await a.done();
}

// --- showcase_demo: starts, names the browser-kept shortcuts, links its source ------------------------------------
{
  const a = await app('showcase_demo');
  check('showcase_demo: renders', (await a.ink(0, 0, 900, 600)) > 5000);
  const note = await a.page.textContent('#keylist');
  check('showcase_demo: the page names the shortcuts the browser keeps', note.includes('Ctrl+Tab'), note);
  const source = await a.page.getAttribute('header a[href]:not([href="NOTICES"])', 'href');
  check('showcase_demo: the page links the source', !!source && source.startsWith('https://'), source);
  await a.done();
}

// --- browsers it cannot run in: a message, and the module is never downloaded ------------------------------------
for (const [name, init, expect] of [
  ['an engine without wasm exception handling', () => { WebAssembly.validate = () => false; }, 'exception handling'],
  ['a touch-only device', () => { const m = window.matchMedia.bind(window); window.matchMedia = (q) => (q === '(any-pointer: fine)' ? { matches: false } : m(q)); }, 'mouse and a keyboard'],
]) {
  const server = await serve(`${root}/tutorial-07`);
  const context = await browser.newContext();
  const page = await context.newPage();
  let fetched = false;
  page.on('request', (r) => { if (r.url().endsWith('.wasm')) fetched = true; });
  await page.addInitScript(init);
  await page.goto(server.url);
  await page.waitForFunction(() => !/Loading/.test(document.getElementById('msg').textContent));
  const msg = await page.textContent('#msg');
  check(`unsupported: ${name} gets a message, no download`, msg.includes(expect) && !fetched, msg);
  await context.close();
  server.close();
}

await browser.close();
console.log(failures.length ? `smoke: ${failures.length} of ${checks} checks failed` : `smoke: PASS (${checks} checks)`);
process.exit(failures.length ? 1 : 0);
