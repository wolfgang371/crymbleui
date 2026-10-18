// Compares the conformance program's output of the two flavours. usage: node diff.mjs NATIVE.out WEB.out
// Exit 0 only if every case and every metric is within its tolerance:
//   geometry   every pixel within 1 per channel        image      within 2 per channel
//   composite  within 2 per channel (blending rounds)  text       ink box within 1 px, ink amount within 15 %
//   (the amount: FreeType's hinting draws the desktop's glyphs bolder - measured 10.5 % at 14 px, 2.3 % at 16)
//   metrics    width, offsets and reference height within 1 px; line spacing (a two-line height) exact
//   contract   each flavour against what RenderBackend's contract says (drawn with fills), within 1 per channel;
//              the web flavour must hold it, a native deviation is reported (CrSFMLBackend#blit_region samples a
//              flipped band - tracked in crymble-ui's backlog; its one caller is the cache validator)
// and every case shows something on both sides (a blank or a wrongly read backend cannot pass by agreeing).
// A composite case compares colour only: the window's alpha is never shown.
// KNOWN_GAPS are measured differences, pinned to their exact values - any change in them fails too.
import { readFileSync } from 'node:fs';

const TOLERANCE = { geometry: 1, image: 2, composite: 2, contract: 1 };
const KNOWN_GAPS = [
  // FreeType's hinting draws the embedded font 2 px taller at 12 px than the browser's unhinted text does
  { size: 12, key: 'ref', native: 12, web: 10 },
  // a tab is four space advances; at 16 px the browser's add up 2 px short of the desktop's
  { size: 16, key: 'w', text: 'a\tb', native: 60, web: 58 },
];
const INK_THRESHOLD = 60; // a text pixel counts as ink when a channel differs this much from the paper

function parse(file) {
  const out = { cases: new Map(), metrics: null, end: null, errors: [] };
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (line.startsWith('CONF {')) {
      const c = JSON.parse(line.slice(5));
      c.pixels = Array.from({ length: c.w * c.h }, (_, i) => parseInt(c.px.slice(i * 8, i * 8 + 8), 16) >>> 0);
      out.cases.set(c.case, c);
    } else if (line.startsWith('CONF-METRICS ')) out.metrics = JSON.parse(line.slice(13));
    else if (line.startsWith('CONF-END ')) out.end = +line.slice(9);
    else if (line.startsWith('CONF-ERROR ')) out.errors.push(line.slice(11));
  }
  return out;
}

const channels = (p) => [p >>> 24, (p >>> 16) & 255, (p >>> 8) & 255, p & 255];
const maxChannelDiff = (a, b, rgbOnly = false) =>
  Math.max(...channels(a).slice(0, rgbOnly ? 3 : 4).map((v, i) => Math.abs(v - channels(b)[i])));

// The pixels of `c` beyond `tol` from `ref`: { bad, worst, first }
function compare(c, ref, tol, rgbOnly) {
  let bad = 0, worst = 0, first = null;
  c.pixels.forEach((p, i) => {
    const d = maxChannelDiff(p, ref.pixels[i], rgbOnly);
    worst = Math.max(worst, d);
    if (d > tol) { bad++; first ??= [i % c.w, Math.floor(i / c.w), p.toString(16), ref.pixels[i].toString(16)]; }
  });
  return { bad, worst, first };
}
const describe = (r, tol) => `${r.bad} pixels beyond ${tol} (worst ${r.worst})` +
  (r.first ? `, first at ${r.first[0]},${r.first[1]}: ${r.first[2]} vs ${r.first[3]}` : '');

function inkBox(c) {
  const paper = c.pixels[c.pixels.length - 1]; // the bottom-right corner is never inked in a text case
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1, amount = 0;
  c.pixels.forEach((p, i) => {
    const d = maxChannelDiff(p, paper);
    amount += d;
    if (d < INK_THRESHOLD) return;
    const x = i % c.w, y = Math.floor(i / c.w);
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  });
  return { box: [x0, y0, x1, y1], amount };
}

const [nativeFile, webFile] = process.argv.slice(2);
const native = parse(nativeFile), web = parse(webFile);
const failures = [];
const fail = (msg) => failures.push(msg);

for (const [side, out] of [['native', native], ['web', web]]) {
  out.errors.forEach((e) => fail(`${side}: ${e}`));
  if (out.end === null) fail(`${side}: no CONF-END (the program did not finish)`);
  else if (out.end !== out.cases.size) fail(`${side}: CONF-END ${out.end} but ${out.cases.size} cases printed`);
}
if (native.cases.size !== web.cases.size) fail(`case count differs: native ${native.cases.size}, web ${web.cases.size}`);

for (const [name, n] of native.cases) {
  if (name.endsWith(' (contract)')) continue;
  const w = web.cases.get(name);
  if (!w) { fail(`${name}: missing on the web side`); continue; }
  for (const [side, c] of [['native', n], ['web', w]]) {
    if (c.pixels.every((p) => p === c.pixels[0])) fail(`${name}: ${side} shows one flat colour (nothing drawn or read)`);
  }
  if (n.kind === 'text') {
    const a = inkBox(n), b = inkBox(w);
    const off = Math.max(...a.box.map((v, i) => Math.abs(v - b.box[i])));
    const ratio = Math.abs(a.amount - b.amount) / Math.max(a.amount, 1);
    const line = `${name}: ink box native ${a.box} web ${b.box}, ink amount differs ${(ratio * 100).toFixed(1)} %`;
    if (off > 1 || ratio > 0.15) fail(line); else console.log(`ok   ${line}`);
  } else if (n.kind === 'contract') {
    const tol = TOLERANCE.contract;
    const webResult = compare(w, web.cases.get(`${name} (contract)`), tol);
    const nativeResult = compare(n, native.cases.get(`${name} (contract)`), tol);
    const line = `${name}: web against the contract: ${describe(webResult, tol)}`;
    if (webResult.bad) fail(line); else console.log(`ok   ${line}`);
    if (nativeResult.bad) console.log(`note ${name}: native against the contract: ${describe(nativeResult, tol)}`);
  } else {
    const tol = TOLERANCE[n.kind];
    const r = compare(n, w, tol, n.kind === 'composite');
    const line = `${name} (native vs web): ${describe(r, tol)}`;
    if (r.bad) fail(line); else console.log(`ok   ${line}`);
  }
}

if (!native.metrics || !web.metrics) fail('metrics missing');
else {
  native.metrics.forEach((m, i) => {
    const o = web.metrics[i];
    const key = `metrics ${JSON.stringify(m.text)} @${m.size}`;
    const gap = (k) => KNOWN_GAPS.find((g) => g.size === m.size && g.key === k && (g.text ?? m.text) === m.text);
    const within = (k) => (gap(k) ? m[k] === gap(k).native && o[k] === gap(k).web : Math.abs(m[k] - o[k]) <= 1);
    const bad = ['w', 'left', 'top', 'ref'].filter((k) => !within(k)).concat(m.h === o.h ? [] : ['h']);
    const line = `${key}: ` + ['w', 'h', 'left', 'top', 'ref'].map((k) => `${k} ${m[k]}/${o[k]}`).join(', ');
    if (bad.length) fail(line); else console.log(`ok   ${line}`);
  });
}

failures.forEach((f) => console.log(`FAIL ${f}`));
console.log(failures.length ? `conformance: ${failures.length} failures` : `conformance: PASS (${native.cases.size} cases, ${native.metrics.length} metrics, ${KNOWN_GAPS.length} known gaps)`);
process.exit(failures.length ? 1 : 0);
