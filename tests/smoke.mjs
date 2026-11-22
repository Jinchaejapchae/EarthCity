import puppeteer from 'puppeteer-core';
const mobile = process.argv[2] === 'm';
const b = await puppeteer.launch({ executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const p = await b.newPage();
const errs = [];
p.on('pageerror', e => errs.push('PAGEERR ' + e.message));
p.on('console', m => { if (m.type() === 'error' || m.type()==='warning') errs.push(m.type()+': ' + m.text()); });
if (mobile) await p.emulate({ viewport: { width: 844, height: 390, isMobile: true, hasTouch: true, deviceScaleFactor: 2 }, userAgent: 'Mozilla/5.0 (iPhone) Mobile' });
else await p.setViewport({ width: 1280, height: 720 });
await p.goto('file://' + process.cwd() + '/dist/index.html');
await new Promise(r => setTimeout(r, 2500));
await p.screenshot({ path: 'shot0.png' });
await p.evaluate(() => window.__game.startGame());
await new Promise(r => setTimeout(r, 2500));
await p.screenshot({ path: 'shot1.png' });
// walk to car & enter
const info = await p.evaluate(async () => {
  const g = window.__game; const k = g.keys;
  const sleep = t => new Promise(r => setTimeout(r, t));
  // teleport next to red car
  const car = g.cars.find(c => c.paintHex === '#e94f37' && !c.driver && Math.abs(c.z - (4*74-24))<1);
  g.player.x = car.x + 2.5; g.player.z = car.z;
  await sleep(300);
  g.input.enterQ = true; await sleep(300);
  const inCar = !!g.player.car;
  k.KeyW = true; await sleep(3000);
  const sp = Math.hypot(g.player.car?.vx||0, g.player.car?.vz||0);
  k.KeyD = true; await sleep(800); k.KeyD = false;
  await sleep(1500); k.KeyW = false;
  return { inCar, sp, fps: window.__fps, cars: g.cars.length, pos: [g.player.x, g.player.z], hp: g.player.car?.health };
});
console.log(JSON.stringify(info));
await p.screenshot({ path: 'shot2.png' });
const info2 = await p.evaluate(async () => {
  const g = window.__game; const sleep = t => new Promise(r => setTimeout(r, t));
  g.input.enterQ = true; await sleep(300);
  g.crime(25); await sleep(6000);
  return { stars: g.stars, cops: g.cars.filter(c=>c.type==='cop'&&c.mode==='chase').length, fps: window.__fps, peds: g.peds.filter(p=>p.state!=='dead').length, onfoot: !g.player.car };
});
console.log(JSON.stringify(info2));
await p.keyboard.down('Space'); await new Promise(r => setTimeout(r, 1200)); await p.keyboard.up('Space');
await p.screenshot({ path: 'shot3.png' });
console.log(errs.slice(0, 15).join('\n'));
await b.close();
