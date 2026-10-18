// The page's side of crymble-ui's web flavour: the "crymble" import module of the wasm program
// (src/web/js.cr declares every function, its arguments and units). Canvases are ids; 0 is the page's canvas.
//
// What it reproduces of SFML, because crymble-ui's layouts and pixels were made against it:
// - filled geometry by the pixel-centre rule (a pixel is filled iff its centre lies inside) - no antialiasing,
//   which a canvas path would add; text antialiasing is the browser's (the one stated difference);
// - SFML's text model: baseline at y + characterSize; local bounds = glyph boxes, whitespace at the baseline;
// - a circle is SFML's 30-point polygon; an outline lies outside the radius;
// - scissor clipping that also limits clears;
// - layer compositing with SFML's blend arithmetic on the opaque page canvas (every mode, see `composite`), built
//   from canvas operations on a prepared copy of each layer, cached until the layer is drawn on again - nothing is
//   read back from the GPU per frame.
// tools/wasm/conformance holds each of these against the desktop, pixel for pixel.

const BLEND_NORMAL = 0, BLEND_ADDITIVE = 1, BLEND_SUBTRACTIVE = 2, BLEND_MULTIPLY = 3;
const EV = { Closed: 0, Resized: 1, FocusLost: 2, FocusGained: 3, TextEntered: 4, KeyPressed: 5, KeyReleased: 6,
  MouseWheelScrolled: 7, MouseButtonPressed: 8, MouseButtonReleased: 9, MouseMoved: 10, MouseEntered: 12, MouseLeft: 13 };
// CrymbleUI::CursorType -> CSS
const CURSORS = ['default', 'text', 'ew-resize', 'ns-resize', 'nwse-resize', 'nesw-resize', 'move'];

// DOM KeyboardEvent.code -> sfKeyCode (LibCSFML::KeyCode, src/csfml3/lib.cr)
const KEYS = (() => {
  const k = {};
  for (let i = 0; i < 26; i++) k['Key' + String.fromCharCode(65 + i)] = i;
  for (let i = 0; i < 10; i++) { k['Digit' + i] = 26 + i; k['Numpad' + i] = 75 + i; }
  ['Escape', 'ControlLeft', 'ShiftLeft', 'AltLeft', 'MetaLeft', 'ControlRight', 'ShiftRight', 'AltRight', 'MetaRight',
    'ContextMenu', 'BracketLeft', 'BracketRight', 'Semicolon', 'Comma', 'Period', 'Quote', 'Slash', 'Backslash',
    'Backquote', 'Equal', 'Minus', 'Space', 'Enter', 'Backspace', 'Tab', 'PageUp', 'PageDown', 'End', 'Home', 'Insert',
    'Delete', 'NumpadAdd', 'NumpadSubtract', 'NumpadMultiply', 'NumpadDivide', 'ArrowLeft', 'ArrowRight', 'ArrowUp',
    'ArrowDown'].forEach((n, i) => { k[n] = 36 + i; });
  for (let i = 1; i <= 15; i++) k['F' + i] = 84 + i;
  k.Pause = 100; k.NumpadEnter = k.Enter; k.OSLeft = k.MetaLeft; k.OSRight = k.MetaRight;
  return k;
})();

export { EV, KEYS }; // for tools/wasm/spec (the event round trip checks them against crymble-ui's enums)

// SFML's code follows the keyboard layout: a letter key is the letter it types (Ctrl+Z on a German layout).
function keyCode(e) {
  if (e.key.length === 1) {
    const c = e.key.toLowerCase();
    if (c >= 'a' && c <= 'z' && !e.code.startsWith('Numpad')) return c.charCodeAt(0) - 97;
  }
  return KEYS[e.code] ?? -1;
}

export function createCrymble({ canvas, fontFamily, onClipboardWrite = () => {} }) {
  let mem = null; // the wasm memory, set by attach()
  const u8 = () => new Uint8Array(mem.buffer);
  const view = () => new DataView(mem.buffer);
  const utf8 = new TextDecoder();
  const str = (p, n) => utf8.decode(u8().subarray(p, p + n));
  const css = (rgba) => `rgba(${rgba >>> 24},${(rgba >>> 16) & 255},${(rgba >>> 8) & 255},${(rgba & 255) / 255})`;

  // --- canvases ------------------------------------------------------------------------------------------------
  const canvases = new Map();
  const counts = { created: 0, freed: 0 }; // for the smoke: released backends must free their canvas
  let nextId = 1;
  // flipped: the canvas stands for an SFML RenderTexture (y-flipped), not for the window - every one but the page's
  const page = { cv: canvas, ctx: canvas.getContext('2d'), clip: null, flipped: false };
  canvases.set(0, page);
  const get = (id) => {
    const c = canvases.get(id);
    if (!c) throw new Error(`crymble: canvas ${id} does not exist (freed or never made)`);
    return c;
  };
  const scratch = new OffscreenCanvas(1, 1);
  const scratchCtx = scratch.getContext('2d', { willReadFrequently: false });

  // Enter a canvas's clip for one operation (device pixels, identity transform).
  // Every drawing onto a canvas goes through here: its version moves, so what was prepared from it is stale.
  function begin(c, op = 'source-over') {
    c.version = (c.version || 0) + 1;
    const ctx = c.ctx;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    if (c.clip) {
      const [x0, y0, x1, y1] = c.clip;
      ctx.beginPath();
      ctx.rect(x0, y0, x1 - x0, y1 - y0);
      ctx.clip();
    }
    ctx.globalCompositeOperation = op;
    return ctx;
  }

  // Fill a convex polygon as the GPU fills it, without antialiasing (a canvas path would add it): a pixel is in when
  // its centre is inside; a centre exactly on an edge by the top-left rule - on a canvas standing for an SFML
  // RenderTexture (every one but the page's) left-and-BOTTOM, the RenderTexture being y-flipped (crymble-ui's
  // PixelSnap.fill_edge / fill_edge_y_flipped say the same for rects). Vertices are snapped to the GPU's sub-pixel grid first, so float noise in a rotated corner
  // cannot decide a tie - and every tie test below is exact arithmetic on that grid. Filled as row spans (fillRect),
  // rows with the same span merged: a horizontal or vertical line is one rect.
  const SUBPIXEL = 256;
  // The polygon's pixels on canvas c as row spans: Map(y -> [x0, x1]), both ends included - only rows and columns
  // inside the canvas (a shape reaching far past it costs nothing for what cannot be painted).
  function polygonSpans(points, c) {
    const flipped = c.flipped, width = c.cv.width, height = c.cv.height;
    const pts = points.map(([x, y]) => [Math.round(x * SUBPIXEL) / SUBPIXEL, Math.round(y * SUBPIXEL) / SUBPIXEL]);
    const n = pts.length;
    let minY = Infinity, maxY = -Infinity, sx = 0, sy = 0;
    for (const [x, y] of pts) { minY = Math.min(minY, y); maxY = Math.max(maxY, y); sx += x; sy += y; }
    // each edge's inward normal (towards the centroid), and whether a centre lying on it is in: a left edge
    // (interior to its right, not horizontal) or a top edge (horizontal, interior below) - a bottom one if flipped
    const edges = pts.map(([ax, ay], i) => {
      const [bx, by] = pts[(i + 1) % n];
      let nx = ay - by, ny = bx - ax;
      if (nx * (sx / n - ax) + ny * (sy / n - ay) < 0) { nx = -nx; ny = -ny; }
      return { ax, ay, nx, ny, ties: ay === by ? (flipped ? ny < 0 : ny > 0) : nx > 0 };
    });
    const inside = (cx, cy) => edges.every((e) => { const d = e.nx * (cx - e.ax) + e.ny * (cy - e.ay); return d > 0 || (d === 0 && e.ties); });
    const spans = new Map();
    for (let y = Math.max(0, Math.floor(minY - 0.5)); y <= Math.min(height - 1, Math.ceil(maxY - 0.5)); y++) {
      const cy = y + 0.5;
      // the centres' x range from the edges' half-planes (approximate), then its ends settled by the exact test
      let lo = -Infinity, hi = Infinity, empty = false;
      for (const e of edges) {
        const k = e.ny * (cy - e.ay); // d(cx) = nx * (cx - ax) + k
        if (e.nx === 0) { if (k < 0 || (k === 0 && !e.ties)) empty = true; continue; }
        const b = e.ax - k / e.nx; // d == 0 at cx = b
        if (e.nx > 0) lo = Math.max(lo, b); else hi = Math.min(hi, b);
      }
      if (empty || lo > hi + 1) continue;
      let x0 = Math.max(0, Math.ceil(lo - 0.5) - 1), x1 = Math.min(width - 1, Math.floor(hi - 0.5) + 1);
      while (x0 <= x1 && !inside(x0 + 0.5, cy)) x0++;
      while (x1 >= x0 && !inside(x1 + 0.5, cy)) x1--;
      if (x0 <= x1) spans.set(y, [x0, x1]);
    }
    return spans;
  }

  // Fill row segments [y, x0, x1] (in increasing y), merging rows with the same segment: an axis-aligned rect is
  // one fillRect.
  function fillRows(c, rows, rgba) {
    const ctx = begin(c);
    ctx.fillStyle = css(rgba);
    let run = null;
    for (const [y, x0, x1] of rows) {
      if (run && x0 === run.x0 && x1 === run.x1 && y === run.y + run.h) { run.h++; continue; }
      if (run) ctx.fillRect(run.x0, run.y, run.x1 - run.x0 + 1, run.h);
      run = { y, x0, x1, h: 1 };
    }
    if (run) ctx.fillRect(run.x0, run.y, run.x1 - run.x0 + 1, run.h);
    ctx.restore();
  }

  function fillPolygon(c, points, rgba) {
    fillRows(c, [...polygonSpans(points, c)].map(([y, [x0, x1]]) => [y, x0, x1]), rgba);
  }

  // SFML's CircleShape: 30 points, the first at the top.
  const circlePoints = (cx, cy, r) => Array.from({ length: 30 }, (_, i) => {
    const t = (i * 2 * Math.PI) / 30 - Math.PI / 2;
    return [cx + Math.cos(t) * r, cy + Math.sin(t) * r];
  });

  // --- text ----------------------------------------------------------------------------------------------------
  const measureCtx = new OffscreenCanvas(1, 1).getContext('2d');
  let measureFont = null;
  // sf::Text's local bounds {left, top, width, height}: the union of the glyph boxes, whitespace extending it along
  // the baseline. Only the horizontal extent and the FIRST line's vertical extent are used (WebFont: the width, and
  // the "Ag" reference top/height); a multi-line string's height comes from the line spacing, not from here.
  // sf::Text advances a tab by four spaces' widths, the canvas by one: expanded first, for measuring and drawing
  const expandTabs = (s) => s.replaceAll('\t', '    ');

  function localBounds(text, size) {
    if (text === '') return [0, 0, 0, 0];
    text = expandTabs(text);
    const font = `${size}px ${fontFamily}`;
    if (font !== measureFont) measureCtx.font = measureFont = font; // a font string is parsed on every set
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    text.split('\n').forEach((line, i) => {
      const base = size; // every line's box measured at the first baseline: only the first line's height is used
      if (/\S/.test(line)) {
        const m = measureCtx.measureText(line);
        minX = Math.min(minX, -m.actualBoundingBoxLeft); maxX = Math.max(maxX, m.actualBoundingBoxRight);
        minY = Math.min(minY, base - m.actualBoundingBoxAscent); maxY = Math.max(maxY, base + m.actualBoundingBoxDescent);
      }
      if (/\s/.test(line)) {
        if (/^\s/.test(line)) minX = Math.min(minX, 0);
        if (/\s$/.test(line)) maxX = Math.max(maxX, measureCtx.measureText(line).width);
        minY = Math.min(minY, base); maxY = Math.max(maxY, base);
      }
    });
    if (minX === Infinity) return [0, 0, 0, 0];
    // FreeType's FT_GLYPH_BBOX_PIXELS, which sf::Glyph's bounds come from: the box grid-fitted outward
    minX = Math.floor(minX); minY = Math.floor(minY); maxX = Math.ceil(maxX); maxY = Math.ceil(maxY);
    return [minX, minY, maxX - minX, maxY - minY];
  }

  // --- images --------------------------------------------------------------------------------------------------
  const images = new Map(); // key -> { bitmap } | { pending: true }
  const tinted = new Map(); // key|rgba -> canvas, least recently used first
  const TINTS_KEPT = 64; // a fading tint would otherwise keep a canvas per step
  let invalidations = 0;
  function tint(key, bitmap, rgba) {
    if (rgba === 0xffffffff) return bitmap;
    const id = key + '|' + rgba;
    let cv = tinted.get(id);
    if (cv) { tinted.delete(id); tinted.set(id, cv); return cv; }
    // SFML's sprite colour multiplies every channel, alpha included - exactly, per pixel, once per (image, colour)
    cv = new OffscreenCanvas(bitmap.width, bitmap.height);
    const cx = cv.getContext('2d', { willReadFrequently: true });
    cx.drawImage(bitmap, 0, 0);
    const img = cx.getImageData(0, 0, bitmap.width, bitmap.height);
    const m = [rgba >>> 24, (rgba >>> 16) & 255, (rgba >>> 8) & 255, rgba & 255];
    for (let i = 0; i < img.data.length; i++) img.data[i] = Math.round((img.data[i] * m[i & 3]) / 255);
    cx.putImageData(img, 0, 0);
    tinted.set(id, cv);
    if (tinted.size > TINTS_KEPT) {
      const [oldest, old] = tinted.entries().next().value;
      tinted.delete(oldest);
      old.width = old.height = 0;
    }
    return cv;
  }

  // --- input ---------------------------------------------------------------------------------------------------
  const queue = [];
  let clipText = '';
  const listeners = { input: () => {} };

  // The canvas's pixels follow the box the page gives it; true if they changed.
  function fitCanvas() {
    const w = Math.max(1, Math.floor(canvas.clientWidth)), h = Math.max(1, Math.floor(canvas.clientHeight));
    if (canvas.width === w && canvas.height === h) return false;
    canvas.width = w; canvas.height = h;
    return true;
  }

  function installInput() {
    const pos = (e) => { const r = canvas.getBoundingClientRect(); return [Math.round(e.clientX - r.left), Math.round(e.clientY - r.top)]; };
    const touched = () => listeners.input();
    canvas.addEventListener('mousemove', (e) => {
      const [x, y] = pos(e);
      const last = queue[queue.length - 1];
      if (last && last[0] === EV.MouseMoved) { last[1] = x; last[2] = y; } else queue.push([EV.MouseMoved, x, y, 0, 0, 0]);
    });
    const btn = (b) => (b === 0 ? 0 : b === 2 ? 1 : b === 1 ? 2 : b);
    canvas.addEventListener('mousedown', (e) => { canvas.focus(); touched(); const [x, y] = pos(e); queue.push([EV.MouseButtonPressed, btn(e.button), x, y, 0, 0]); e.preventDefault(); });
    window.addEventListener('mouseup', (e) => { const [x, y] = pos(e); queue.push([EV.MouseButtonReleased, btn(e.button), x, y, 0, 0]); });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    canvas.addEventListener('mouseenter', () => queue.push([EV.MouseEntered, 0, 0, 0, 0, 0]));
    canvas.addEventListener('mouseleave', () => queue.push([EV.MouseLeft, 0, 0, 0, 0, 0]));
    canvas.addEventListener('focus', () => queue.push([EV.FocusGained, 0, 0, 0, 0, 0]));
    canvas.addEventListener('blur', () => queue.push([EV.FocusLost, 0, 0, 0, 0, 0]));
    canvas.addEventListener('wheel', (e) => {
      const notch = e.deltaMode === 1 ? 3 : e.deltaMode === 2 ? 0.1 : 100; // pixels per SFML wheel notch
      const [x, y] = pos(e);
      if (e.deltaY) queue.push([EV.MouseWheelScrolled, 0, x, y, -e.deltaY / notch, 0]);
      if (e.deltaX) queue.push([EV.MouseWheelScrolled, 1, x, y, -e.deltaX / notch, 0]);
      e.preventDefault();
    }, { passive: false });

    const mods = (e) => (e.altKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.shiftKey ? 4 : 0) | (e.metaKey ? 8 : 0);
    const keyEvents = (e) => {
      queue.push([EV.KeyPressed, keyCode(e), 0, 0, 0, mods(e)]);
      // TextEntered from the key's character - not while Cmd is held (Cmd+C on macOS must not type 'c'). AltGr arrives
      // as Ctrl+Alt with the character in e.key, which KeyboardDispatch already treats as text.
      if ([...e.key].length === 1 && !e.metaKey) queue.push([EV.TextEntered, e.key.codePointAt(0), 0, 0, 0, 0]);
    };
    let pendingPaste = null;
    canvas.addEventListener('keydown', (e) => {
      touched();
      if (e.key === 'F5' || e.key === 'F11' || e.key === 'F12') return; // the browser's
      const paste = ((e.ctrlKey || e.metaKey) && !e.altKey && e.key.toLowerCase() === 'v') || (e.shiftKey && e.key === 'Insert');
      if (paste) {
        // Let the browser fire 'paste' first: the app reads Clipboard#text while it handles the key.
        const copy = { key: e.key, code: e.code, altKey: e.altKey, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, metaKey: e.metaKey };
        pendingPaste = { e: copy, timer: setTimeout(() => { if (pendingPaste) { keyEvents(pendingPaste.e); pendingPaste = null; } }, 150) };
        return;
      }
      e.preventDefault();
      keyEvents(e);
    });
    document.addEventListener('paste', (e) => {
      clipText = e.clipboardData.getData('text/plain');
      e.preventDefault();
      if (pendingPaste) { clearTimeout(pendingPaste.timer); keyEvents(pendingPaste.e); pendingPaste = null; }
    });
    canvas.addEventListener('keyup', (e) => queue.push([EV.KeyReleased, keyCode(e), 0, 0, 0, mods(e)]));

    new ResizeObserver(() => { if (fitCanvas()) queue.push([EV.Resized, canvas.width, canvas.height, 0, 0, 0]); }).observe(canvas);
    canvas.addEventListener('contextrestored', () => { invalidations++; });
  }

  // A layer canvas in the form a blend mode composites it (see `composite`), kept per canvas and kind until the
  // canvas is drawn on again: a frame re-prepares only the layers that changed, the others composite in one pass.
  //   premultiplied  P over black - opaque, rgb = c*a                   (Multiply)
  //   straight       straight colour c*a at alpha a                     (Normal)
  //   squared        P * a                                              (Additive, Subtractive)
  function prepared(c, kind) {
    c.prepared ||= {};
    let p = c.prepared[kind];
    if (p && p.version === c.version && p.cv.width === c.cv.width && p.cv.height === c.cv.height) return p.cv;
    if (!p) p = c.prepared[kind] = { cv: new OffscreenCanvas(c.cv.width, c.cv.height) };
    p.cv.width = c.cv.width; p.cv.height = c.cv.height; // (also clears it)
    const x = p.cv.getContext('2d');
    const pass = (op, draw) => { x.save(); x.globalCompositeOperation = op; draw(); x.restore(); };
    const source = () => x.drawImage(c.cv, 0, 0);
    const black = () => { x.fillStyle = '#000'; x.fillRect(0, 0, p.cv.width, p.cv.height); };
    if (kind === 'squared') pass('copy', source);
    else { pass('copy', black); pass('source-over', source); }
    if (kind !== 'premultiplied') pass('destination-in', source);
    p.version = c.version;
    return p.cv;
  }

  // --- the import module ----------------------------------------------------------------------------------------
  const imports = {
    canvas_new(w, h) {
      const cv = new OffscreenCanvas(Math.max(1, w), Math.max(1, h));
      cv.addEventListener?.('contextrestored', () => { invalidations++; });
      const id = nextId++;
      counts.created++;
      canvases.set(id, { cv, ctx: cv.getContext('2d'), clip: null, flipped: true });
      return id;
    },
    canvas_free(id) {
      const c = get(id);
      c.cv.width = c.cv.height = 0;
      for (const p of Object.values(c.prepared || {})) p.cv.width = p.cv.height = 0;
      canvases.delete(id);
      counts.freed++;
    },
    canvas_size(id, wp, hp) { const c = get(id), v = view(); v.setInt32(wp, c.cv.width, true); v.setInt32(hp, c.cv.height, true); },
    clip(id, x0, y0, x1, y1) { get(id).clip = [x0, y0, x1, y1]; },
    unclip(id) { get(id).clip = null; },

    clear(id, rgba) {
      const c = get(id), ctx = begin(c, 'copy');
      ctx.fillStyle = css(rgba);
      ctx.fillRect(0, 0, c.cv.width, c.cv.height);
      ctx.restore();
    },
    fill_rect(id, x0, y0, x1, y1, rgba) {
      if (x1 <= x0 || y1 <= y0) return;
      const ctx = begin(get(id));
      ctx.fillStyle = css(rgba);
      ctx.fillRect(x0, y0, x1 - x0, y1 - y0);
      ctx.restore();
    },
    fill_polygon(id, xyp, n, rgba) {
      const v = view(), pts = [];
      for (let i = 0; i < n; i++) pts.push([v.getFloat64(xyp + 16 * i, true), v.getFloat64(xyp + 16 * i + 8, true)]);
      fillPolygon(get(id), pts, rgba);
    },
    circle(id, cx, cy, r, fill, rgba) {
      const c = get(id);
      if (fill) return fillPolygon(c, circlePoints(cx, cy, r), rgba);
      // a 1px outline outside the radius, row by row: SFML mitres it, so its outer points lie 1 / cos(pi / 30) out
      const inner = polygonSpans(circlePoints(cx, cy, r), c), rows = [];
      for (const [y, [x0, x1]] of polygonSpans(circlePoints(cx, cy, r + 1 / Math.cos(Math.PI / 30)), c)) {
        const hole = inner.get(y);
        if (!hole) { rows.push([y, x0, x1]); continue; }
        if (hole[0] > x0) rows.push([y, x0, hole[0] - 1]);
        if (hole[1] < x1) rows.push([y, hole[1] + 1, x1]);
      }
      fillRows(c, rows, rgba);
    },
    text(id, p, n, x, y, size, rgba) {
      const s = expandTabs(str(p, n));
      if (!s) return;
      const ctx = begin(get(id));
      ctx.font = `${size}px ${fontFamily}`;
      ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = css(rgba);
      ctx.fillText(s, x, y + size); // one line (WebBackend steps multi-line text by the font's line spacing)
      ctx.restore();
    },
    image(id, kp, kn, bp, bn, x, y, w, h, rgba) {
      const key = str(kp, kn);
      const entry = images.get(key);
      if (!entry) {
        images.set(key, { pending: true });
        createImageBitmap(new Blob([u8().slice(bp, bp + bn)])).then(
          (bitmap) => { images.set(key, { bitmap }); invalidations++; },
          () => images.set(key, { failed: true }));
        return 0;
      }
      if (!entry.bitmap) return 0;
      const ctx = begin(get(id));
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(tint(key, entry.bitmap, rgba), x, y, w, h);
      ctx.restore();
      return 1;
    },
    copy(dst, src, sx, sy, w, h, dx, dy) {
      if (w <= 0 || h <= 0) return;
      const d = get(dst), s = get(src);
      let from = s.cv;
      if (dst === src) { // overlapping copy within one canvas: through the scratch canvas
        if (scratch.width < w) scratch.width = w;
        if (scratch.height < h) scratch.height = h;
        scratchCtx.clearRect(0, 0, w, h);
        scratchCtx.drawImage(s.cv, sx, sy, w, h, 0, 0, w, h);
        from = scratch; sx = 0; sy = 0;
      }
      // BlendNone: the destination rect becomes the source, alpha included - clip to the rect before 'copy'
      const ctx = begin(d, 'copy');
      ctx.beginPath(); ctx.rect(dx, dy, w, h); ctx.clip();
      ctx.drawImage(from, sx, sy, w, h, dx, dy, w, h);
      ctx.restore();
    },
    // A layer texel holds P = (c*a, a): crymble-ui fills a transparent RenderTexture with alpha blending. SFML then
    // blends the texel with its blend mode as if it were straight colour, so a's factor lands on it twice; the
    // canvas stores premultiplied colour and would apply it once. Each mode is rebuilt from canvas operations,
    // GPU-side, on the opaque window:
    //   Normal       dst*(1 - a*o) + c*a*a*o      Additive  dst + c*a*a*o
    //   Subtractive  max(0, dst - c*a*a*o)       Multiply  dst * c*a  (SFML's multiply ignores alpha and o)
    // with o = SFML's (opacity * 255).to_u8 / 255.
    composite(dst, src, sx, sy, w, h, dx, dy, opacity, blend) {
      if (w <= 0 || h <= 0) return;
      const d = get(dst), s = get(src);
      const o = Math.floor(opacity * 255) / 255;
      const ctx = begin(d);
      ctx.beginPath(); ctx.rect(dx, dy, w, h); ctx.clip();
      const onto = (op, cv, alpha) => { ctx.globalCompositeOperation = op; ctx.globalAlpha = alpha; ctx.drawImage(cv, sx, sy, w, h, dx, dy, w, h); };
      if (blend === BLEND_MULTIPLY) onto('multiply', prepared(s, 'premultiplied'), 1);
      else if (blend === BLEND_NORMAL) onto('source-over', prepared(s, 'straight'), o);
      else {
        if (blend === BLEND_SUBTRACTIVE) { ctx.globalCompositeOperation = 'difference'; ctx.fillStyle = '#fff'; ctx.fillRect(dx, dy, w, h); }
        onto('lighter', prepared(s, 'squared'), o);
        if (blend === BLEND_SUBTRACTIVE) { ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'difference'; ctx.fillRect(dx, dy, w, h); }
      }
      ctx.restore();
    },
    read_pixels(id, x, y, w, h, buf) {
      const data = get(id).ctx.getImageData(x, y, w, h).data;
      u8().set(data, buf);
    },

    measure(p, n, size, out) {
      const b = localBounds(str(p, n), size), v = view();
      for (let i = 0; i < 4; i++) v.setFloat64(out + 8 * i, b[i], true);
    },

    next_event(tp, i0p, i1p, i2p, fp, mp) {
      const e = queue.shift();
      if (!e) return 0;
      const v = view();
      v.setInt32(tp, e[0], true); v.setInt32(i0p, e[1], true); v.setInt32(i1p, e[2], true);
      v.setInt32(i2p, e[3], true); v.setFloat64(fp, e[4], true); v.setInt32(mp, e[5], true);
      return 1;
    },
    set_title(p, n) { document.title = str(p, n); },
    set_cursor(c) { canvas.style.cursor = CURSORS[c] || 'default'; },
    invalidations() { const n = invalidations; invalidations = 0; return n; },

    clipboard_get(buf, cap) {
      const bytes = new TextEncoder().encode(clipText);
      if (buf && cap > 0) u8().set(bytes.subarray(0, cap), buf);
      return bytes.length;
    },
    clipboard_set(p, n) {
      clipText = str(p, n);
      onClipboardWrite(clipText);
      navigator.clipboard?.writeText(clipText).catch(() => {});
    },
  };

  return {
    imports,
    attach(memory) { mem = memory; },
    installInput,
    onInput(fn) { listeners.input = fn; },
    canvasCount: () => canvases.size - 1,
    canvasCounts: () => ({ ...counts }),
    fitCanvas,
  };
}
