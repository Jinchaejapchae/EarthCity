import puppeteer from 'puppeteer-core';
const b = await puppeteer.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const p = await b.newPage(); await p.setViewport({ width: 480, height: 270 });
p.on('pageerror', e => console.log('ERR', e.message));
await p.goto('file://' + process.cwd() + '/dist/index.html');
await new Promise(r => setTimeout(r, 1500));
const r = await p.evaluate(async () => {
  const g = window.__game; g.startGame(); const sleep = t => new Promise(r => setTimeout(r, t));
  await sleep(1500);
  const els = document.elementsFromPoint(300, 20).map(e => e.id || e.tagName);
  const car = g.cars.find(c => !c.driver && Math.abs(c.z - (4*74-24))<1);
  g.player.x = car.x + 2.5; g.player.z = car.z; await sleep(200);
  g.input.enterQ = true; await sleep(200);
  const log = [];
  g.keys.KeyW = true;
  for (let i = 0; i < 8; i++) { await sleep(500); const c = g.player.car; log.push([+c.vF.toFixed(1), +c.x.toFixed(1), +c.z.toFixed(1), c.throttle]); }
  g.keys.KeyW = false;
  return { els, log, n: g.cars.length, fps: window.__fps };
});
console.log(JSON.stringify(r));
await b.close();
