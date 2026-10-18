// Boots a crymble-ui app built for the web flavour (bin/crymble-web build) in a page:
//
//   import { boot } from "./crymble-web.js";
//   boot({ canvas: document.getElementById("app"), wasmUrl: "app.wasm", onStatus: (kind, text) => ... });
//
// onStatus kinds: progress, starting, running, unsupported, closed, error, stderr, and shortcuts (the app's
// shortcuts a browser keeps for itself, comma-separated - sent again whenever the app's registrations change).
//
// The app runs in this tab only: its files live in an in-memory file system (/home/user, /tmp) and are gone when
// the tab closes. One tick of the app per animation frame; garbage is collected between ticks (src/web/entry.cr
// says why only there).
import { WASI, File, OpenFile, ConsoleStdout, PreopenDirectory, Directory } from './vendor/browser_wasi_shim/index.js';
import { createCrymble } from './crymble.js';

// The browser keeps these whatever a page does (documented browser behaviour, not measured here): an app's
// shortcuts on them cannot work in a tab.
export const BROWSER_KEYS = ['Ctrl+W', 'Ctrl+N', 'Ctrl+T', 'Ctrl+Tab', 'Ctrl+Shift+Tab', 'Ctrl+PageUp', 'Ctrl+PageDown',
  'Ctrl+Shift+N', 'Ctrl+Shift+T', 'Ctrl+Shift+W'];

// A tiny module with a try / catch_all: compiles only where WebAssembly exception handling is supported.
const EH_PROBE = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 10, 8, 1, 6, 0, 6, 64, 25, 11, 11]);

export function unsupported() {
  if (!matchMedia('(any-pointer: fine)').matches) return 'needs a desktop browser with a mouse and a keyboard.';
  if (typeof WebAssembly !== 'object' || !WebAssembly.validate(EH_PROBE)) {
    return 'needs WebAssembly exception handling: use a current Chrome, Edge, Firefox or Safari.';
  }
  return null;
}

export async function boot({ canvas, wasmUrl, onStatus = () => {}, confirmLeave = false, gcThresholdMB = 24 }) {
  const reason = unsupported();
  if (reason) { onStatus('unsupported', reason); return null; }

  // --- download with progress ------------------------------------------------------------------------------------
  const response = await fetch(wasmUrl);
  if (!response.ok) throw new Error(`${wasmUrl}: HTTP ${response.status}`);
  const total = +(response.headers.get('Content-Length') || 0);
  let loaded = 0;
  const counted = new Response(new ReadableStream({
    async start(controller) {
      const reader = response.body.getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        loaded += value.length;
        onStatus('progress', total ? `${Math.round((loaded / total) * 100)} %` : `${(loaded / 1048576).toFixed(1)} MB`);
        controller.enqueue(value);
      }
      controller.close();
    },
  }), { headers: { 'Content-Type': 'application/wasm' } });
  const module = await WebAssembly.compileStreaming(counted);

  // --- WASI: an in-memory file system and the app's stdout/stderr ------------------------------------------------
  const stderr = [];
  const wasi = new WASI([], ['HOME=/home/user', 'TMPDIR=/tmp', 'USER=user'], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((m) => console.log(m)),
    ConsoleStdout.lineBuffered((m) => { stderr.push(m); console.warn(m); onStatus('stderr', m); }),
    new PreopenDirectory('/', [['home', new Directory([['user', new Directory([])]])], ['tmp', new Directory([])]]),
  ]);
  // wasi-libc finds the preopened directories by asking fd 3, 4, ... until it hears EBADF, and may ask late - with
  // the app's own files open. The shim answers ENOTSUP for an open fd that is no preopen, which wasi-libc takes as
  // fatal (exit 71, measured: Embrace's Save as). Answer as WASI hosts do.
  const ERRNO_BADF = 8, ERRNO_NOTSUP = 58;
  const prestat = wasi.wasiImport.fd_prestat_get;
  wasi.wasiImport.fd_prestat_get = (fd, buf) => { const r = prestat(fd, buf); return r === ERRNO_NOTSUP ? ERRNO_BADF : r; };

  // The font is the one crymble-ui embedded into the module: read it out of its memory before the app starts.
  const fontFamily = 'crymble-embedded';
  const crymble = createCrymble({ canvas, fontFamily });
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport, crymble: crymble.imports });
  const x = instance.exports;
  crymble.attach(x.memory);
  wasi.initialize(instance);
  {
    const out = x.malloc(8);
    x.crymble_font(out, out + 4);
    const v = new DataView(x.memory.buffer);
    const bytes = new Uint8Array(x.memory.buffer, v.getUint32(out, true), v.getUint32(out + 4, true)).slice();
    x.free(out);
    const face = new FontFace(fontFamily, bytes);
    await face.load();
    document.fonts.add(face);
  }

  crymble.fitCanvas();
  crymble.installInput();
  let leaveArmed = false;
  if (confirmLeave) {
    crymble.onInput(() => { leaveArmed = true; });
    window.addEventListener('beforeunload', (e) => { if (leaveArmed) { e.preventDefault(); e.returnValue = ''; } });
  }

  onStatus('starting', '');
  const init = x.crymble_init();
  if (init !== 0) { onStatus('error', init === 2 ? 'the app did not start (it never called CrymbleUI.run)' : 'the app failed to start'); return null; }

  // The app's shortcuts that a browser keeps for itself (its registered ones and crymble-ui's built-ins), compared
  // as modifier sets + key. Re-read only when the app's registrations moved.
  const norm = (k) => { const p = k.split('+'); return [...p.slice(0, -1).map((m) => m.toLowerCase()).sort(), p[p.length - 1].toLowerCase()].join('+'); };
  const browserKeys = new Set(BROWSER_KEYS.map(norm));
  let shortcutsRevision = -1, unavailable = [];
  function unavailableShortcuts() {
    const rev = x.crymble_shortcuts_revision();
    if (rev !== shortcutsRevision) {
      shortcutsRevision = rev;
      const n = x.crymble_shortcuts(0, 0), buf = x.malloc(n + 1);
      x.crymble_shortcuts(buf, n);
      const text = new TextDecoder().decode(new Uint8Array(x.memory.buffer, buf, n));
      x.free(buf);
      unavailable = text.split('\n').filter((k) => k && browserKeys.has(norm(k)));
    }
    return unavailable;
  }

  // --- the frame loop --------------------------------------------------------------------------------------------
  let frames = 0;
  const idleWaiters = [];
  let idleTicks = 0;
  const threshold = Math.round(gcThresholdMB * 1048576);
  const STOPPED = 'Files saved in this tab are gone. Reload to start again.';
  let note = null;
  function frame() {
    let r;
    let shortcuts = null;
    try { // every call into the module: a trap, or a page function that threw, is reported nowhere else
      r = x.crymble_tick();
      if (r > 0) x.crymble_gc(threshold);
      if (r === 2) shortcuts = unavailableShortcuts().join(', ');
    } catch (e) {
      console.error(e);
      r = -1;
    }
    if (r === 0) { onStatus('closed', `This session ended. ${STOPPED}`); return; }
    if (r === -1) { onStatus('error', `The app stopped with an error. ${STOPPED}`); return; }
    if (r === 2) {
      frames++;
      idleTicks = 0;
      if (shortcuts !== note) onStatus('shortcuts', (note = shortcuts));
    } else idleTicks++;
    if (idleTicks >= 3) idleWaiters.splice(0).forEach((resolve) => resolve());
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  onStatus('running', '');

  // For smokes and diagnostics: frames rendered, a promise for three idle ticks in a row, the in-memory file system,
  // live canvases (and how many were made and freed), the heap, the app's shortcuts a browser keeps for itself,
  // and the app's stderr.
  const handle = {
    get frames() { return frames; },
    idle: () => new Promise((resolve) => idleWaiters.push(resolve)),
    fs: wasi.fds[3],
    canvases: () => crymble.canvasCount(),
    canvasCounts: () => crymble.canvasCounts(),
    heapMB: () => x.crymble_heap_mb(),
    gc: (bytes = 0) => x.crymble_gc(bytes),
    unavailableShortcuts,
    stderr,
  };
  window.__crymble = handle;
  return handle;
}
