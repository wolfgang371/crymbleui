// Runs a wasm32-wasi program under Node's WASI. usage: node run.mjs command PROGRAM.wasm | node run.mjs soak SOAK.wasm
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { WASI } from 'node:wasi';

const [mode, file] = process.argv.slice(2);
const tmp = mkdtempSync(join(tmpdir(), 'crymble-wasm-spec-'));
const wasi = new WASI({ version: 'preview1', args: [file], env: { TMPDIR: '/tmp' }, preopens: { '/tmp': tmp } });
const module = await WebAssembly.compile(readFileSync(file));
// Any other import (the web flavour's "crymble" module) is a stub: a spec that reaches the page fails loudly.
const imports = { wasi_snapshot_preview1: wasi.wasiImport };
for (const i of WebAssembly.Module.imports(module)) {
  if (i.module !== 'wasi_snapshot_preview1') (imports[i.module] ??= {})[i.name] = () => { throw new Error(`no page in a spec: ${i.module}.${i.name}`); };
}
const instance = await WebAssembly.instantiate(module, imports);

if (mode === 'command') {
  process.exitCode = wasi.start(instance);
} else {
  wasi.initialize(instance);
  const x = instance.exports;
  x.soak_init();
  const heap = [];
  let bad = 0;
  for (let t = 0; t < 2000; t++) {
    x.soak_tick(t);
    x.soak_gc();
    if ((t + 1) % 200 === 0) {
      heap.push(x.soak_heap_kb());
      bad = bad || x.soak_check(t);
    }
  }
  const finalized = x.soak_finalized();
  const growth = Math.max(...heap.slice(1)) - Math.min(...heap.slice(1));
  console.log(`soak: heap KB per 200 ticks ${heap.join(' ')}; finalizers run ${finalized}; rows check ${bad || 'ok'}`);
  const ok = bad === 0 && finalized > 0 && growth <= 2048;
  console.log(ok ? 'soak: PASS' : 'soak: FAIL');
  process.exitCode = ok ? 0 : 1;
}
