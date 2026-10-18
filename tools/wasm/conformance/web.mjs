// The conformance program's web half: serves bin/web/conformance/, runs it in headless Chromium and prints the
// program's CONF lines (its stdout, which the page forwards to the console) - the same lines the native build prints.
// usage: node web.mjs BIN_WEB_CONFORMANCE_DIR
import { serve, launch, open } from '../browser.mjs';

const server = await serve(process.argv[2]);
const browser = await launch();
let code = 1;
try {
  const { page, log } = await open(browser, server.url);
  await page.waitForFunction(() => window.__crymble, null, { timeout: 30000 });
  const deadline = Date.now() + 60000;
  while (!log.some((l) => l.text.startsWith('CONF-END')) && Date.now() < deadline) await page.waitForTimeout(100);
  for (const l of log) {
    if (l.text.startsWith('CONF')) console.log(l.text);
    // (Chromium's "Canvas2D: Multiple readback operations ..." hint is about the read-back this program exists for)
    else if ((l.type === 'pageerror' || l.type === 'warning' || l.type === 'error') && !l.text.startsWith('Canvas2D:')) {
      console.error(`[${l.type}] ${l.text}`);
    }
  }
  code = log.some((l) => l.text.startsWith('CONF-END')) ? 0 : 1;
  if (code) console.error('web.mjs: the program never printed CONF-END');
} finally {
  await browser.close();
  server.close();
}
process.exit(code);
