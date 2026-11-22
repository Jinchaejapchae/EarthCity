import * as THREE from 'three';
import { CAR_TEX, CAR_MODELS } from './carModels.js';
import { mergeGeometries, toCreasedNormals } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { N8AOPass } from 'n8ao';
import { EXRLoader } from 'three/examples/jsm/loaders/EXRLoader.js';
import sunsetEXR from '@pmndrs/assets/hdri/sunset.exr';
import { Sky } from 'three/examples/jsm/objects/Sky.js';

// ================= constants =================
const N = 8, R = 14, B = 60, P = B + R, SW = 5, CITY = N * P, LANE = 3.5;
let MINB = -R / 2 - 9, MAXB = CITY + R / 2 + 9;
const DX = [1, 0, -1, 0], DZ = [0, 1, 0, -1];
const TH = [1, 8, 20, 40, 70];
const COPS_FOR = [0, 1, 2, 3, 5, 7];
const $ = id => document.getElementById(id);
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const wrapA = a => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
const lerpA = (a, b, t) => a + wrapA(b - a) * t;
const pick = arr => arr[Math.random() * arr.length | 0];
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const srand = mulberry32(20261122);
const rr = (a, b) => a + (b - a) * srand();
const isTouch = matchMedia('(pointer:coarse)').matches || 'ontouchstart' in window;
document.body.classList.toggle('touch', isTouch);

// ================= renderer =================
let renderer;
try {
  renderer = new THREE.WebGLRenderer({ antialias: !isTouch, powerPreference: 'high-performance' });
} catch (e) {
  $('start').innerHTML = '<div class="card"><h1>WebGL 오류</h1><p>이 기기/브라우저에서 3D를 실행할 수 없어요.</p></div>';
  throw e;
}
// 품질 단계: low / mid / high (localStorage ulsan_q)
const QN = { low: '낮음', mid: '중', high: '높음' };
const QS = { low: { pr: 1, sh: 1024, peds: 90, post: false }, mid: { pr: 1.5, sh: 1024, peds: 150, post: true }, high: { pr: 2, sh: 2048, peds: 220, post: true, ao: true } };
let quality = 'mid';
try { const s = localStorage.getItem('ulsan_q'); quality = QS[s] ? s : (isTouch ? 'mid' : 'high'); } catch (e) { quality = isTouch ? 'mid' : 'high'; }
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
// ---- 위치(마지막으로 확인한 값, 없으면 울산) + 실제 지도(OSM) 캐시
let LAT = 35.54, LON = 129.31, LOC_NAME = '울산', LOC_REAL = false;
try { const l = JSON.parse(localStorage.getItem('ulsan_loc') || 'null'); if (l && isFinite(l.lat) && isFinite(l.lon)) { LAT = l.lat; LON = l.lon; LOC_NAME = l.name || ''; LOC_REAL = true; } } catch (e) { }
let OSM_WANT = false; try { OSM_WANT = localStorage.getItem('ulsan_map') === 'osm'; } catch (e) { }
const OSM = (() => { // 캐시된 주변 지도 데이터 (현재 위치 400m 이내일 때만 사용)
  if (!OSM_WANT) return null;
  try { const d = JSON.parse(localStorage.getItem('ulsan_osm') || 'null'); if (d && d.roads && d.blds && Math.abs(d.lat - LAT) < 0.004 && Math.abs(d.lon - LON) < 0.004) return d; } catch (e) { }
  return null;
})();
const SIDEY = OSM ? 0.03 : 0.25, CX = OSM ? 0 : CITY / 2, CZ = CX;
// 후처리: (high: N8AO / mid: RenderPass) -> Bloom -> Output. low는 composer 없음
let composer = null;
function buildPost() {
  if (composer) { composer.passes.forEach(p => p.dispose?.()); composer.dispose(); composer = null; }
  const q = QS[quality]; if (!q.post) return;
  const w = innerWidth, h = innerHeight, pr = renderer.getPixelRatio();
  const rt = new THREE.WebGLRenderTarget(w * pr, h * pr, { type: THREE.HalfFloatType, samples: q.ao ? 0 : 4 });
  composer = new EffectComposer(renderer, rt);
  composer.setPixelRatio(pr); composer.setSize(w, h);
  if (q.ao) {
    const ao = new N8AOPass(scene, camera, w, h);
    ao.configuration.gammaCorrection = false;
    ao.configuration.aoRadius = 4; ao.configuration.distanceFalloff = 1.5; ao.configuration.intensity = 3; ao.configuration.color = new THREE.Color(0x1a1030);
    composer.addPass(ao);
  } else composer.addPass(new RenderPass(scene, camera));
  composer.addPass(new UnrealBloomPass(new THREE.Vector2(w, h), 0.45, 0.6, 0.92));
  composer.addPass(new OutputPass());
}
function applyQuality() {
  const q = QS[quality];
  renderer.setPixelRatio(Math.min(devicePixelRatio, q.pr));
  renderer.setSize(innerWidth, innerHeight);
  if (typeof sun !== 'undefined') {
    const s = sun.shadow;
    if (s.mapSize.x !== q.sh) { s.mapSize.set(q.sh, q.sh); if (s.map) { s.map.dispose(); s.map = null; } }
  }
  buildPost();
  if (typeof setPedCount === 'function') setPedCount(q.peds);
  const b = $('qbtn'); if (b) b.textContent = '화질: ' + QN[quality];
}
$('game').appendChild(renderer.domElement);
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(62, innerWidth / innerHeight, 0.5, 900);
addEventListener('resize', () => { renderer.setSize(innerWidth, innerHeight); composer?.setSize(innerWidth, innerHeight); camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); });

function makeCanvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function tex(c, rep = true) { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; if (rep) t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy()); return t; }

scene.fog = new THREE.Fog(0xeb9a7e, 110, 360); // 지평선 색에 맞춤
const hemi = new THREE.HemisphereLight(0xffd6c0, 0x5a4a78, 0.35); scene.add(hemi);
const sun = new THREE.DirectionalLight(0xffb27a, 2.7);
sun.castShadow = true;
sun.shadow.mapSize.set(QS[quality].sh, QS[quality].sh);
Object.assign(sun.shadow.camera, { left: -70, right: 70, top: 70, bottom: -70, near: 1, far: 320 });
sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.5;
scene.add(sun, sun.target);

// 하늘 (Sky.js): 해 고도 12도. 태양광 방향도 같은 벡터를 씀
const SUN_EL = 12 * Math.PI / 180, SUN_AZ = Math.atan2(-38, -60);
const sunDir = new THREE.Vector3(Math.cos(SUN_EL) * Math.cos(SUN_AZ), Math.sin(SUN_EL), Math.cos(SUN_EL) * Math.sin(SUN_AZ));
const sky = new Sky(); sky.scale.setScalar(420); sky.renderOrder = -1; scene.add(sky);
{ const u = sky.material.uniforms; u.turbidity.value = 10; u.rayleigh.value = 3.2; u.mieCoefficient.value = 0.012; u.mieDirectionalG.value = 0.86; u.sunPosition.value.copy(sunDir); }
sun.shadow.camera.left = sun.shadow.camera.bottom = -95; sun.shadow.camera.right = sun.shadow.camera.top = 95; sun.shadow.camera.far = 420;

// ================= materials =================
const matCache = new Map();
const lam = c => { let m = matCache.get(c); if (!m) { m = new THREE.MeshStandardMaterial({ color: c, roughness: 0.85, metalness: 0 }); matCache.set(c, m); } return m; };
const paintCache = new Map();
const paint = c => { let m = paintCache.get(c); if (!m) { m = quality === 'low' ? new THREE.MeshStandardMaterial({ color: c, roughness: 0.3, metalness: 0.4 }) : new THREE.MeshPhysicalMaterial({ color: c, roughness: 0.42, metalness: 0.45, clearcoat: 1, clearcoatRoughness: 0.05 }); paintCache.set(c, m); } return m; };

// 환경광/반사: sunset HDRI -> PMREM -> scene.environment
new EXRLoader().load(sunsetEXR, t => {
  t.mapping = THREE.EquirectangularReflectionMapping;
  const pm = new THREE.PMREMGenerator(renderer);
  scene.environment = pm.fromEquirectangular(t).texture;
  scene.environmentIntensity = 0.45;
  t.dispose(); pm.dispose();
});

// ---- 건물 PBR 텍스처 (절차적): 0 주거(창) / 1 오피스(리본창) / 2 유리 타워 / 3 벽돌. 타일 = 가로 8m x 세로 7m(2개 층)
const texL = c => { const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy()); return t; };
function heightToNormal(hc, S, str, Hh = S) {
  const d = hc.getContext('2d').getImageData(0, 0, S, Hh).data, c = makeCanvas(S, Hh), x = c.getContext('2d'), o = x.createImageData(S, Hh), H = (a, b) => d[(((b + Hh) % Hh) * S + ((a + S) % S)) * 4] / 255;
  for (let j = 0; j < Hh; j++) for (let i = 0; i < S; i++) {
    const dx = (H(i + 1, j) - H(i - 1, j)) * str, dy = (H(i, j + 1) - H(i, j - 1)) * str, il = 1 / Math.hypot(dx, dy, 1), p = (j * S + i) * 4;
    o.data[p] = (-dx * il * 0.5 + 0.5) * 255; o.data[p + 1] = (dy * il * 0.5 + 0.5) * 255; o.data[p + 2] = (il * 0.5 + 0.5) * 255; o.data[p + 3] = 255;
  }
  x.putImageData(o, 0, 0); return c;
}
// ---- 지면 PBR 텍스처 (도로/교차로/보도블록/잔디/주차장): color + roughness(G) + 높이맵->normal
function vnoise(n) { const g = Array.from({ length: n * n }, Math.random), s = t => t * t * (3 - 2 * t), G = (x, y) => g[((y % n + n) % n) * n + ((x % n + n) % n)]; return (u, v) => { u *= n; v *= n; const i = Math.floor(u), j = Math.floor(v), a = s(u - i), b = s(v - j); return (G(i, j) * (1 - a) + G(i + 1, j) * a) * (1 - b) + (G(i, j + 1) * (1 - a) + G(i + 1, j + 1) * a) * b; }; }
function groundTex(L, base, draw, nstr) {
  const S = quality === 'low' ? 256 : 512, cv = [0, 1, 2].map(() => makeCanvas(S, S)), cx = cv.map(c => c.getContext('2d')), id = cx.map(x => x.createImageData(S, S));
  for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) {
    const r = base(i / S, j / S, i, j, S), p = (j * S + i) * 4;
    id[0].data[p] = r[0]; id[0].data[p + 1] = r[1]; id[0].data[p + 2] = r[2]; id[0].data[p + 3] = 255;
    const h = r[3] * 255; id[1].data[p] = id[1].data[p + 1] = id[1].data[p + 2] = h; id[1].data[p + 3] = 255;
    id[2].data[p] = 255; id[2].data[p + 1] = r[4] * 255; id[2].data[p + 2] = 0; id[2].data[p + 3] = 255;
  }
  cx.forEach((x, k) => { x.putImageData(id[k], 0, 0); x.setTransform(S / L, 0, 0, S / L, 0, 0); });
  if (draw) draw(cx[0], cx[1], cx[2]);
  return { map: tex(cv[0]), roughnessMap: texL(cv[2]), normalMap: texL(heightToNormal(cv[1], S, nstr)) };
}
const asphaltBase = (g0, lo = vnoise(6), mid = vnoise(24)) => (u, v) => {
  const r = Math.random(), g = g0 + lo(u, v) * 14 + mid(u, v) * 9 + (r - 0.5) * 16, stone = r > 0.975;
  return stone ? [g + 40, g + 38, g + 36, 0.72, 0.65] : [g, g, g + 6, 0.5 + (r - 0.5) * 0.35, 0.86 + (r - 0.5) * 0.12];
};
// 닳은 칠: 사각형을 칠한 뒤 무작위로 아스팔트를 다시 찍어 지움
function paintMark(C, H, M, x, y, w, h, col, wear) {
  C.fillStyle = col; C.fillRect(x, y, w, h); H.fillStyle = '#868686'; H.fillRect(x, y, w, h); M.fillStyle = 'rgb(255,150,0)'; M.fillRect(x, y, w, h);
  const n = w * h * wear;
  for (let i = 0; i < n; i++) {
    const a = x + Math.random() * w, b = y + Math.random() * h, s = 0.5 + Math.random() * 0.9;
    C.fillStyle = 'rgba(66,66,74,.9)'; C.fillRect(a, b, s, s); H.fillStyle = '#808080'; H.fillRect(a, b, s, s); M.fillStyle = 'rgb(255,225,0)'; M.fillRect(a, b, s, s);
  }
}
function crack(C, H, M, L, x, y, a, n) {
  const pts = [[x, y]];
  for (let s = 0; s < n; s++) {
    a += (Math.random() - 0.5) * 0.9; x += Math.cos(a) * 2.2; y += Math.sin(a) * 2.2;
    if (x < 3 || y < 3 || x > L - 3 || y > L - 3) break; pts.push([x, y]);
    if (Math.random() < 0.06) crack(C, H, M, L, x, y, a + (Math.random() < 0.5 ? 1 : -1) * 0.8, n >> 1);
  }
  for (const [ctx, col, w] of [[C, 'rgba(14,14,18,.85)', 0.9], [H, '#1c1c1c', 1.2], [M, 'rgb(255,255,0)', 1.2]]) { ctx.strokeStyle = col; ctx.lineWidth = w; ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.stroke(); }
}
function wearDraw(C, H, M, L, nCrack, nPatch) {
  for (let i = 0; i < nCrack; i++) crack(C, H, M, L, 6 + Math.random() * (L - 12), 6 + Math.random() * (L - 12), Math.random() * 6.28, 14 + (Math.random() * 30 | 0));
  for (let i = 0; i < nPatch; i++) { const w = 10 + Math.random() * 22, h = 6 + Math.random() * 14, x = Math.random() * (L - w), y = Math.random() * (L - h); C.fillStyle = 'rgba(0,0,0,.16)'; C.fillRect(x, y, w, h); M.fillStyle = 'rgb(255,215,0)'; M.fillRect(x, y, w, h); H.fillStyle = 'rgba(120,120,120,.35)'; H.fillRect(x, y, w, h); }
}
const roadTex = (() => {
  const t = groundTex(128, asphaltBase(60), (C, H, M) => {
    for (const cy of [34, 94]) for (const o of [-8, 8]) { C.fillStyle = 'rgba(0,0,0,.2)'; C.fillRect(0, cy + o - 3, 128, 6); M.fillStyle = 'rgb(255,190,0)'; M.fillRect(0, cy + o - 3, 128, 6); }
    wearDraw(C, H, M, 128, 3, 3);
    paintMark(C, H, M, 0, 60, 128, 2, '#e8b83f', 0.5); paintMark(C, H, M, 0, 66, 128, 2, '#e8b83f', 0.5);
    paintMark(C, H, M, 0, 7, 128, 2, '#dcdcdc', 0.5); paintMark(C, H, M, 0, 119, 128, 2, '#dcdcdc', 0.5);
    for (let k = 0; k < 128; k += 32) { paintMark(C, H, M, k, 33, 14, 1.5, '#dcdcdc', 0.5); paintMark(C, H, M, k + 16, 94, 14, 1.5, '#dcdcdc', 0.5); }
  }, 2.2);
  t.map.repeat.set((CITY + R) / R, 1); t.roughnessMap.repeat.copy(t.map.repeat); t.normalMap.repeat.copy(t.map.repeat); return t;
})();
const crossTex = groundTex(128, asphaltBase(64), (C, H, M) => {
  wearDraw(C, H, M, 128, 1, 1);
  for (let k = 26; k <= 98; k += 9) { paintMark(C, H, M, k, 3, 5, 18, '#e2e2e2', 0.35); paintMark(C, H, M, k, 107, 5, 18, '#e2e2e2', 0.35); paintMark(C, H, M, 3, k, 18, 5, '#e2e2e2', 0.35); paintMark(C, H, M, 107, k, 18, 5, '#e2e2e2', 0.35); }
}, 2.2);
// 보도블록: 4m 타일 = 1m 슬래브 4x4
const walkTex = (() => {
  const lo = vnoise(4), mid = vnoise(32), sl = Array.from({ length: 16 }, () => (Math.random() - 0.5) * 22);
  return groundTex(128, (u, v, i, j, S) => {
    const q = S / 4, gi = i % q, gj = j % q, gr = Math.min(gi, gj, q - 1 - gi, q - 1 - gj) < S / 170, r = Math.random(), sv = sl[((j / q) | 0) * 4 + ((i / q) | 0)];
    const g = 184 + sv + lo(u, v) * 10 + mid(u, v) * 8 + (r - 0.5) * 12 - (gr ? 55 : 0);
    return [g, g - 5, g - 14, gr ? 0.1 : 0.55 + (r - 0.5) * 0.18, gr ? 1 : 0.88 + (r - 0.5) * 0.1];
  }, (C, H, M) => { wearDraw(C, H, M, 128, 0, 0); for (let i = 0; i < 3; i++) crack(C, H, M, 128, 6 + Math.random() * 116, 6 + Math.random() * 116, Math.random() * 6.28, 8); }, 2.5);
})();
// 잔디: 6m 타일
const grassTex = (() => {
  const lo = vnoise(5), mid = vnoise(40);
  return groundTex(128, (u, v) => {
    const r = Math.random(), n = lo(u, v), m = mid(u, v), t = n * 0.6 + m * 0.4 + (r - 0.5) * 0.35;
    return [78 + t * 55 - 15, 128 + t * 60 - 20, 62 + t * 25 - 8, 0.4 + r * 0.45, 0.93];
  }, null, 3);
})();
// 주차장 아스팔트: 10m 타일
const lotTex = groundTex(128, asphaltBase(78), (C, H, M) => wearDraw(C, H, M, 128, 3, 2), 2);
function boxUV(g, m) { // 박스 면별 UV 를 미터 기준으로 (m = 타일 한 장의 미터)
  const { width: w, height: h, depth: d } = g.parameters, uv = g.attributes.uv, dim = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) { const i = f * 4 + k; uv.setXY(i, uv.getX(i) * dim[f][0] / m, uv.getY(i) * dim[f][1] / m); }
  return g;
}
const gmat = t => new THREE.MeshStandardMaterial({ color: 0xffffff, metalness: 0, roughness: 1, ...t, normalScale: new THREE.Vector2(0.9, 0.9) });
const jointMat = gmat(groundTex(128, asphaltBase(58), (C, H, M) => wearDraw(C, H, M, 128, 1, 0), 2.2)), roadMat = gmat(roadTex), crossMat = gmat(crossTex), walkMat = gmat(walkTex), grassMat = gmat(grassTex), lotMat = gmat(lotTex);
// ---- 물: 타일되는 파도 normal map(정수 주파수 사인 합) 을 흘려보냄 + 낮은 roughness 로 환경 반사
const waterMat = (() => {
  const S = quality === 'low' ? 128 : 256, c = makeCanvas(S, S), x = c.getContext('2d'), id = x.createImageData(S, S), W = [];
  for (let i = 0; i < 9; i++) W.push([1 + (Math.random() * 6 | 0), 1 + (Math.random() * 6 | 0), Math.random() * 6.283, 0.5 + Math.random() * 0.5, Math.random() < 0.5 ? 1 : -1]);
  for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) {
    let h = 0; for (const [fx, fy, ph, a, sg] of W) h += a * Math.sin(6.2832 * (fx * i / S + sg * fy * j / S) + ph) / Math.hypot(fx, fy);
    const v = (0.5 + h * 0.22) * 255, p = (j * S + i) * 4; id.data[p] = id.data[p + 1] = id.data[p + 2] = v; id.data[p + 3] = 255;
  }
  x.putImageData(id, 0, 0);
  const n = texL(heightToNormal(c, S, 6)); n.repeat.set(110, 110);
  return new THREE.MeshStandardMaterial({ color: '#2d7da3', roughness: 0.05, metalness: 0.15, normalMap: n, normalScale: new THREE.Vector2(0.55, 0.55) });
})();
const lit = (p) => Math.random() < p ? `hsl(${32 + Math.random() * 18},95%,${58 + Math.random() * 16}%)` : null;
function bldTex(v) {
  const S = quality === 'low' ? 256 : 512, k = S / 256;
  const cv = [0, 1, 2, 3].map(() => makeCanvas(S, S)), [C, E, H, M] = cv.map(c => { const x = c.getContext('2d'); x.setTransform(k, 0, 0, k, 0, 0); return x; });
  E.fillStyle = '#000'; E.fillRect(0, 0, 256, 256);
  const g = n => { n = Math.round(n * 255); return `rgb(${n},${n},${n})`; };
  const f = (x, y, w, h, o) => {
    if (o.c) { C.fillStyle = o.c; C.fillRect(x, y, w, h); }
    if (o.e) { E.fillStyle = o.e; E.fillRect(x, y, w, h); }
    if (o.h !== undefined) { H.fillStyle = g(o.h); H.fillRect(x, y, w, h); }
    if (o.r !== undefined) { M.fillStyle = `rgb(255,${Math.round(o.r * 255)},${Math.round((o.m || 0) * 255)})`; M.fillRect(x, y, w, h); }
  };
  const speckle = (n, lo, hi) => { for (let i = 0; i < n; i++) { const a = Math.random() * 256, b = Math.random() * 256, s = Math.random(); C.fillStyle = `rgba(0,0,0,${0.04 + s * 0.05})`; C.fillRect(a, b, 1.2, 1.2); H.fillStyle = g(lo + (hi - lo) * s); H.fillRect(a, b, 1.2, 1.2); } };
  const glass = (x, y, w, h, col, p) => {
    const e = lit(p); f(x, y, w, h, { c: col, e: e || '#000', h: 0.2, r: 0.07, m: 0.6 });
    const gr = C.createLinearGradient(0, y, 0, y + h); gr.addColorStop(0, 'rgba(160,185,210,.5)'); gr.addColorStop(0.55, 'rgba(90,110,135,.12)'); gr.addColorStop(1, 'rgba(10,15,25,.18)'); C.fillStyle = gr; C.fillRect(x, y, w, h);
    if (Math.random() < 0.4) { const bh = h * (0.2 + Math.random() * 0.55), cc = ['#cfc4b0', '#b9b2a6', '#d9cdbd', '#a8b2bd'][Math.random() * 4 | 0]; f(x, y, w, bh, { c: cc, e: e ? 'rgb(120,88,48)' : '#000', h: 0.3, r: 0.9, m: 0 }); }
  };
  if (v === 0) {
    f(0, 0, 256, 256, { c: '#f6f2ec', h: 0.5, r: 0.8, m: 0 }); speckle(2500, 0.44, 0.56);
    for (let r = 0; r < 2; r++) {
      f(0, r * 128 + 118, 256, 8, { c: '#e9e4dc', h: 0.6, r: 0.8, m: 0 });
      for (let i = 0; i < 4; i++) {
        const wx = 16 + i * 60, wy = 24 + r * 128;
        f(wx - 3, wy - 3, 40, 84, { c: '#fbfbfb', h: 0.65, r: 0.6, m: 0 });
        glass(wx, wy, 34, 78, '#3a4a63', 0.3);
        f(wx + 16, wy, 2, 78, { c: '#e8e8e8', h: 0.62, r: 0.6, m: 0 });
        f(wx, wy, 34, 3, { c: 'rgba(255,255,255,.25)' });
        f(wx - 5, wy + 81, 44, 4, { c: '#e0dcd6', h: 0.8, r: 0.8, m: 0 });
      }
    }
  } else if (v === 1) {
    f(0, 0, 256, 256, { c: '#e3e6ea', h: 0.5, r: 0.45, m: 0.35 }); speckle(1200, 0.47, 0.53);
    for (let r = 0; r < 2; r++) {
      const y0 = r * 128 + 26;
      f(0, y0 - 4, 256, 4, { c: '#f2f2f2', h: 0.72, r: 0.4, m: 0.6 });
      for (let i = 0; i < 8; i++) glass(i * 32, y0, 32, 72, '#34465e', 0.28);
      for (let i = 0; i <= 8; i++) f(i * 32 - 1.5, y0, 3, 72, { c: '#cfd4da', h: 0.62, r: 0.35, m: 0.85 });
      f(0, y0 + 72, 256, 4, { c: '#f2f2f2', h: 0.7, r: 0.4, m: 0.6 });
    }
  } else if (v === 2) {
    f(0, 0, 256, 256, { c: '#9aa6b0', h: 0.6, r: 0.35, m: 0.9 });
    const cols = ['#2f4a63', '#35546e', '#2a3f55', '#3d5c73', '#26384c'];
    for (let j = 0; j < 4; j++) for (let i = 0; i < 8; i++) f(i * 32 + 2, j * 64 + 2, 28, 60, { c: cols[Math.random() * 5 | 0], e: lit(0.2) || '#000', h: 0.3, r: 0.04, m: 0.85 });
    for (let j = 0; j < 4; j++) f(0, j * 64 - 1, 256, 3, { c: '#b9c1c9', h: 0.7, r: 0.35, m: 0.9 });
  } else {
    f(0, 0, 256, 256, { c: '#e6e1d8', h: 0.2, r: 0.95, m: 0 });
    for (let j = 0; j < 32; j++) for (let i = 0; i < 16; i++) {
      const x = i * 16 + (j % 2) * 8, y = j * 8, t = 205 + Math.random() * 50, rr2 = 0.82 + Math.random() * 0.12, hh = 0.55 + Math.random() * 0.12;
      for (const xx of [x, x - 256]) f(xx + 1, y + 1, 14, 6, { c: `rgb(${t | 0},${(t - 6) | 0},${(t - 12) | 0})`, h: hh, r: rr2, m: 0 });
    }
    for (let r = 0; r < 2; r++) for (let i = 0; i < 4; i++) {
      const wx = 18 + i * 60, wy = 30 + r * 128;
      f(wx - 5, wy - 8, 44, 8, { c: '#e2dccf', h: 0.8, r: 0.8, m: 0 });
      f(wx - 3, wy - 3, 40, 78, { c: '#f3f3f3', h: 0.65, r: 0.6, m: 0 });
      glass(wx, wy, 34, 72, '#3a4a63', 0.3);
      f(wx + 16, wy, 2, 72, { c: '#e8e8e8', h: 0.62, r: 0.6, m: 0 });
      f(wx - 6, wy + 75, 46, 5, { c: '#e2dccf', h: 0.85, r: 0.8, m: 0 });
    }
  }
  for (let i = 0; i < 34; i++) { const x = Math.random() * 256, w = 2 + Math.random() * 7, y = Math.random() * 190, hh = 30 + Math.random() * 90, gr = C.createLinearGradient(0, y, 0, y + hh); gr.addColorStop(0, 'rgba(30,25,20,0)'); gr.addColorStop(1, 'rgba(30,25,20,.11)'); C.fillStyle = gr; C.fillRect(x, y, w, hh); }
  const tc = tex(cv[0]), te = tex(cv[1]), tm = texL(cv[3]), tn = texL(heightToNormal(cv[2], S, 3));
  return { map: tc, emissiveMap: te, roughnessMap: tm, metalnessMap: tm, normalMap: tn };
}
const WIN = [bldTex(0), bldTex(1), bldTex(2), bldTex(3)];
const BLD_COLS = [
  ['#efdcc4', '#e3987a', '#9fc0d6', '#c8b3dd', '#f2e0a2', '#a9d0a3', '#e2d8d0', '#88aec2', '#f3b5a6', '#d7c6a4'],
  ['#d7dde2', '#c9d3dc', '#e3e0d8', '#b9c4cc', '#e8d9c5'],
  ['#9fc0d6', '#88aec2', '#b6c8d4', '#7f9fb0', '#a5b8a8'],
  ['#c47a5a', '#b5654a', '#a85a45', '#c98b66', '#9c6a52']
];
const CAR_COL = ['#e94f37', '#f6c445', '#3c91e6', '#5fbf77', '#f2f2f2', '#2b2b33', '#ff8fab', '#8e6cef', '#ff9f1c', '#2ec4b6', '#7d1d2c', '#9aa5b1'];
const wreckMat = lam('#2a2421');
const glassMat = new THREE.MeshStandardMaterial({ color: '#2a3a50', roughness: 0.06, metalness: 0.55, transparent: true, opacity: 0.7, depthWrite: false });
const glassFar = new THREE.MeshStandardMaterial({ color: '#1d2736', roughness: 0.1, metalness: 0.6 });
const darkMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.22, metalness: 0.45 });
const wheelMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.55, metalness: 0.4, side: THREE.DoubleSide });
const headMat = new THREE.MeshStandardMaterial({ color: '#fff7e0', emissive: '#fff1c8', emissiveIntensity: 2.4, roughness: 0.3 });
const tailOff = new THREE.MeshStandardMaterial({ color: '#4a0808', emissive: '#ff1a10', emissiveIntensity: 0.9, roughness: 0.3 });
const tailOn = new THREE.MeshStandardMaterial({ color: '#4a0808', emissive: '#ff1a10', emissiveIntensity: 4.5, roughness: 0.3 });
// 경찰차 투톤: 차체 로컬 높이(y) 기준으로 아래쪽을 검정으로
const copBodyMat = paint('#f4f4f6').clone();
copBodyMat.onBeforeCompile = sh => {
  sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying float vOY;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvOY = position.y;');
  sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vOY;').replace('#include <color_fragment>', '#include <color_fragment>\ndiffuseColor.rgb = mix(vec3(0.012, 0.013, 0.016), diffuseColor.rgb, smoothstep(0.57, 0.6, vOY));');
};
const fireMat = new THREE.MeshBasicMaterial({ color: 0xff7a1a, transparent: true, opacity: 0.9 });

// ================= world =================
const colliders = Array.from({ length: N * N }, () => []);
const blocks = [];
const buckets = new Map();
const addGeo = (key, mat, g, shadow = true) => { let b = buckets.get(key); if (!b) { b = { mat, geos: [], shadow }; buckets.set(key, b); } b.geos.push(g); };
function bldGeo(w, h, d) {
  const g = new THREE.BoxGeometry(w, h, d), uv = g.attributes.uv;
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
    const i = f * 4 + k;
    if (f === 2 || f === 3) uv.setXY(i, 0.01, 0.01);
    else uv.setXY(i, uv.getX(i) * (f < 2 ? d : w) / 8, uv.getY(i) * h / 7);
  }
  return g;
}
// ---- 1층 상가(storefront) 텍스처: 가로 8m x 세로 4.5m 한 장. 간판 색 4종
const SIGN = ['#b53a2e', '#2d5a9e', '#2f8a57', '#d9a62a'];
function storeTex(si) {
  const S = quality === 'low' ? 256 : 512, k = S / 256, Hh = Math.round(S * 0.5625);
  const cv = [0, 1, 2, 3].map(() => makeCanvas(S, Hh)), [C, E, H, M] = cv.map(c => { const x = c.getContext('2d'); x.setTransform(k, 0, 0, k, 0, 0); return x; });
  const g = n => { n = Math.round(n * 255); return `rgb(${n},${n},${n})`; };
  const f = (x, y, w, h, o) => {
    if (o.c) { C.fillStyle = o.c; C.fillRect(x, y, w, h); }
    if (o.e) { E.fillStyle = o.e; E.fillRect(x, y, w, h); }
    if (o.h !== undefined) { H.fillStyle = g(o.h); H.fillRect(x, y, w, h); }
    if (o.r !== undefined) { M.fillStyle = `rgb(255,${Math.round(o.r * 255)},${Math.round((o.m || 0) * 255)})`; M.fillRect(x, y, w, h); }
  };
  E.fillStyle = '#000'; E.fillRect(0, 0, 256, 144);
  f(0, 0, 256, 144, { c: '#d2cabd', h: 0.5, r: 0.85, m: 0 });
  for (let i = 0; i < 1800; i++) { const a = Math.random() * 256, b = Math.random() * 144; C.fillStyle = 'rgba(0,0,0,.06)'; C.fillRect(a, b, 1.2, 1.2); }
  f(0, 8, 256, 28, { c: SIGN[si], e: 'rgb(48,40,32)', h: 0.62, r: 0.5, m: 0 });
  for (let i = 0, x = 22; i < 4; i++) { const w = 18 + Math.random() * 34; f(x, 17, w, 10, { c: 'rgba(255,255,255,.88)', e: 'rgb(90,86,80)', h: 0.7 }); x += w + 12; }
  for (let i = 0; i < 16; i++) f(i * 16, 38, 16, 9, { c: i % 2 ? '#f2eee6' : SIGN[si], h: 0.72, r: 0.8, m: 0 });
  f(0, 134, 256, 10, { c: '#5f5a54', h: 0.72, r: 0.9, m: 0 });
  const shop = (x, w) => {
    f(x - 3, 51, w + 6, 82, { c: '#3a3d42', h: 0.66, r: 0.4, m: 0.8 });
    f(x, 54, w, 76, { c: '#26323f', h: 0.2, r: 0.06, m: 0.6 });
    const gr = E.createLinearGradient(0, 54, 0, 130); gr.addColorStop(0, 'rgb(150,112,64)'); gr.addColorStop(1, 'rgb(215,160,82)'); E.fillStyle = gr; E.fillRect(x, 54, w, 76);
    for (let r = 0; r < 3; r++) { f(x, 78 + r * 22, w, 2, { c: '#2a2a2e', e: 'rgb(60,45,28)', h: 0.55 }); for (let i = 0; i < w / 14 - 0.5; i++) { const col = `hsl(${Math.random() * 360 | 0},55%,${45 + Math.random() * 25 | 0}%)`; f(x + 5 + i * 14, 66 + r * 22, 9, 10, { c: col, e: col, h: 0.45 }); } }
    const gl = C.createLinearGradient(0, 54, 0, 130); gl.addColorStop(0, 'rgba(165,190,215,.4)'); gl.addColorStop(1, 'rgba(165,190,215,0)'); C.fillStyle = gl; C.fillRect(x, 54, w, 76);
    f(x + w / 2 - 1, 54, 2, 76, { c: '#3a3d42', h: 0.64, r: 0.4, m: 0.8 });
  };
  shop(8, 98); shop(150, 98);
  f(114, 51, 28, 84, { c: '#3a3d42', h: 0.66, r: 0.4, m: 0.8 });
  f(118, 55, 20, 80, { c: '#26323f', e: 'rgb(200,150,80)', h: 0.2, r: 0.06, m: 0.6 }); f(133, 92, 2, 12, { c: '#d7dbe0', h: 0.8, r: 0.3, m: 1 });
  return { map: tex(cv[0]), emissiveMap: tex(cv[1]), roughnessMap: texL(cv[3]), metalnessMap: texL(cv[3]), normalMap: texL(heightToNormal(cv[2], S, 3, Hh)) };
}
const STORE = [0, 1, 2, 3].map(storeTex);
const PODH = 4.5, LEDGE_Y = 4.9;
function podGeo(w, d) {
  const g = new THREE.BoxGeometry(w, PODH, d), uv = g.attributes.uv;
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) { const i = f * 4 + k; if (f === 2 || f === 3) uv.setXY(i, 0.01, 0.01); else uv.setXY(i, uv.getX(i) * (f < 2 ? d : w) / 8, uv.getY(i)); }
  return g;
}
// 발코니: 주거/벽돌 건물의 창 열에 맞춰 한 타일(8m)에 1곳, 격층으로
function addBalconies(v, x0, z0, w, d, uh) {
  const wx = (v === 0 ? 16 : 18) + 17, nfl = Math.min(7, Math.floor((uh - 1) / 3.5)), sm = lam('#d6d0c5'), rm = lam('#bdb7ab');
  for (let face = 0; face < 4; face++) {
    if (srand() < 0.35) continue;
    const len = face < 2 ? w : d, um = (wx + (1 + (srand() * 2 | 0)) * 60) / 256 * 8, ox = face === 0 || face === 1 ? 0 : (face === 2 ? 1 : -1), oz = face === 0 ? 1 : face === 1 ? -1 : 0, alongX = ox === 0, BW = 1.7, DP = 1.1;
    for (let t = 0; um + t * 8 < len - 1.5; t++) {
      const u = um + t * 8;
      let px, pz; if (face === 0) { px = x0 + u; pz = z0 + d; } else if (face === 1) { px = x0 + w - u; pz = z0; } else if (face === 2) { px = x0 + w; pz = z0 + d - u; } else { px = x0; pz = z0 + u; }
      for (let n = 0; n < nfl; n++) {
        if ((n + t + face) % 2) continue;
        const y = 5.05 + n * 3.5 + 0.45, cx = px + ox * DP / 2, cz = pz + oz * DP / 2, B3 = (a, b, c, x, yy, z, m, k) => addGeo(k, m, new THREE.BoxGeometry(alongX ? a : b, c, alongX ? b : a).translate(x, yy, z));
        B3(BW, DP, 0.14, cx, y, cz, sm, 'balcSlab');
        B3(BW, 0.04, 0.95, px + ox * (DP - 0.02), y + 0.54, pz + oz * (DP - 0.02), rm, 'balcRail');
        for (const sd of [-1, 1]) addGeo('balcRail', rm, new THREE.BoxGeometry(alongX ? 0.04 : DP, 0.95, alongX ? DP : 0.04).translate(cx + (alongX ? sd * (BW / 2 - 0.02) : 0), y + 0.54, cz + (alongX ? 0 : sd * (BW / 2 - 0.02))));
      }
    }
  }
}
const emisMats = [], eMat = o => { const m = new THREE.MeshStandardMaterial(o); emisMats.push(m); return m; };
const beaconMat = new THREE.MeshStandardMaterial({ color: '#400', emissive: '#ff2418', emissiveIntensity: 3.5 });
function addBuilding(bi, bj, x0, z0, w, d, h, c) {
  h = Math.max(10.5, Math.round(h / 3.5) * 3.5);
  const q = srand(), v = h > 38 ? (q < 0.55 ? 2 : 1) : h > 21 ? (q < 0.35 ? 1 : q < 0.7 ? 0 : 3) : (q < 0.5 ? 0 : 3);
  const ci = srand() * BLD_COLS[v].length | 0, key = 'b' + v + ci, cx = x0 + w / 2, cz = z0 + d / 2;
  const mat = buckets.get(key)?.mat || eMat({ color: BLD_COLS[v][ci], ...WIN[v], emissive: 0xffffff, emissiveIntensity: 0.85, roughness: 1, metalness: 1, normalScale: new THREE.Vector2(0.8, 0.8) });
  const si = srand() * 4 | 0, pk = 'p' + si, pmat = buckets.get(pk)?.mat || eMat({ color: 0xffffff, ...STORE[si], emissive: 0xffffff, emissiveIntensity: 0.85, roughness: 1, metalness: 1, normalScale: new THREE.Vector2(0.7, 0.7) });
  addGeo(pk, pmat, podGeo(w, d).translate(cx, 0.25 + PODH / 2, cz));
  addGeo('ledge', lam('#bdb6aa'), new THREE.BoxGeometry(w + 0.5, 0.3, d + 0.5).translate(cx, LEDGE_Y, cz));
  const uh = h - 4.8;
  addGeo(key, mat, bldGeo(w, uh, d).translate(cx, 5.05 + uh / 2, cz));
  if (v === 0 || v === 3) addBalconies(v, x0, z0, w, d, uh);
  addGeo('roof', lam('#5d5866'), new THREE.BoxGeometry(w * 0.96, 0.5, d * 0.96).translate(cx, h + 0.5, cz));
  { // 옥상 난간(parapet)
    const T = 0.4, PH = 1.1, y = h + 0.25 + PH / 2, pm = lam('#8d8892');
    addGeo('parapet', pm, new THREE.BoxGeometry(w, PH, T).translate(cx, y, z0 + T / 2));
    addGeo('parapet', pm, new THREE.BoxGeometry(w, PH, T).translate(cx, y, z0 + d - T / 2));
    addGeo('parapet', pm, new THREE.BoxGeometry(T, PH, d - 2 * T).translate(x0 + T / 2, y, cz));
    addGeo('parapet', pm, new THREE.BoxGeometry(T, PH, d - 2 * T).translate(x0 + w - T / 2, y, cz));
  }
  const ry = h + 0.75, pg = lam('#9aa1a8');
  if (h > 38 && w > 16 && d > 16 && srand() < 0.6) { // 계단식 상층부(setback)
    const th = 3.5 * (2 + (srand() * 3 | 0)), tw = w * rr(0.5, 0.66), td = d * rr(0.5, 0.66), tx = cx + rr(-1, 1) * (w - tw) * 0.25, tz = cz + rr(-1, 1) * (d - td) * 0.25;
    addGeo(key, mat, bldGeo(tw, th, td).translate(tx, ry + th / 2, tz));
    addGeo('roof', lam('#5d5866'), new THREE.BoxGeometry(tw * 1.02, 0.4, td * 1.02).translate(tx, ry + th + 0.2, tz));
    if (srand() < 0.7) { addGeo('roofprop', pg, new THREE.CylinderGeometry(0.06, 0.1, 7, 5).translate(tx, ry + th + 3.9, tz)); addGeo('beacon', beaconMat, new THREE.SphereGeometry(0.22, 6, 4).translate(tx, ry + th + 7.5, tz), false); }
  } else {
    for (let i = srand() * 3 + 1 | 0; i > 0; i--) { const s = rr(1.3, 2.2); addGeo('roofprop', pg, new THREE.BoxGeometry(s, rr(0.8, 1.3), s * 0.8).translate(x0 + rr(2.5, w - 2.5), ry + 0.5, z0 + rr(2.5, d - 2.5))); }
    if (h > 17 && srand() < 0.35) { // 물탱크
      const tx = x0 + rr(3, w - 3), tz = z0 + rr(3, d - 3), tm = lam('#7b6a58');
      addGeo('roofprop', tm, new THREE.CylinderGeometry(1.1, 1.1, 2.2, 10).translate(tx, ry + 1.9, tz)); addGeo('roofprop', tm, new THREE.ConeGeometry(1.2, 0.7, 10).translate(tx, ry + 3.35, tz));
      for (const [lx, lz] of [[-0.8, -0.8], [0.8, -0.8], [-0.8, 0.8], [0.8, 0.8]]) addGeo('roofprop', pg, new THREE.BoxGeometry(0.12, 0.8, 0.12).translate(tx + lx, ry + 0.4, tz + lz));
    }
    if (srand() < 0.5) { const s = rr(2, 3.5); addGeo('roof', lam('#5d5866'), new THREE.BoxGeometry(s, rr(1.4, 2.6), s).translate(x0 + rr(s, w - s), h + 1.4, z0 + rr(s, d - s))); }
  }
  colliders[bi + bj * N].push([x0, x0 + w, z0, z0 + d]);
}
// ---- 나무/야자수: flatShading + vertex color 클러스터 (재질 공유, 전부 merge)
const WU = { uTime: { value: 0 }, uWind: { value: 0.3 } };
function swayHook(mat, amp) {
  mat.onBeforeCompile = sh => {
    sh.uniforms.uTime = WU.uTime; sh.uniforms.uWind = WU.uWind;
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform float uTime, uWind;').replace('#include <begin_vertex>', `#include <begin_vertex>
      float sw = clamp(transformed.y - 1.5, 0.0, 9.0) * ${amp};
      transformed.x += sin(uTime * 1.6 + transformed.z * 0.4 + transformed.x * 0.3) * uWind * sw; transformed.z += cos(uTime * 1.3 + transformed.x * 0.4) * uWind * sw * 0.7;`);
  };
  return mat;
}
const foliageMat = swayHook(new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.92, metalness: 0 }), '0.035');
const frondMat = swayHook(new THREE.MeshStandardMaterial({ vertexColors: true, flatShading: true, roughness: 0.8, metalness: 0, side: THREE.DoubleSide }), '0.06');
const hv = (x, y, z) => { const s = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453; return s - Math.floor(s); };
const GREENS = ['#4f8a3f', '#5a9444', '#44803a', '#6a9a3c', '#3f7a45', '#7aa040'];
const tint = (g, getHex) => { const p = g.attributes.position, a = new Float32Array(p.count * 3), c = new THREE.Color(); for (let i = 0; i < p.count; i++) { c.set(getHex(p.getX(i), p.getY(i), p.getZ(i), i)); a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; } g.setAttribute('color', new THREE.BufferAttribute(a, 3)); return g; };
function blob(r, x, y, z, col, sy = 0.85) { // 울퉁불퉁한 잎 덩어리
  const g = new THREE.IcosahedronGeometry(r, 1), p = g.attributes.position;
  for (let i = 0; i < p.count; i++) { const k = 1 + (hv(p.getX(i), p.getY(i), p.getZ(i)) - 0.5) * 0.4; p.setXYZ(i, p.getX(i) * k, p.getY(i) * k * sy, p.getZ(i) * k); }
  const base = new THREE.Color(col);
  tint(g, (px, py) => '#' + base.clone().multiplyScalar(0.72 + 0.5 * (py / r * 0.5 + 0.5)).getHexString());
  return g.translate(x, y, z);
}
function coneG(r, h, x, y, z, col) {
  const g = new THREE.ConeGeometry(r, h, 7).toNonIndexed(), base = new THREE.Color(col);
  tint(g, (px, py) => '#' + base.clone().multiplyScalar(0.7 + 0.45 * (py / h + 0.5)).getHexString());
  return g.translate(x, y, z);
}
function frondG(len, w, yaw, pitch, x, y, z) { // 처지는 야자 잎 한 장
  const g = new THREE.PlaneGeometry(w, len, 2, 8).toNonIndexed(), p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const t = (p.getY(i) + len / 2) / len, xx = p.getX(i) * (t < 0.12 ? t / 0.12 : 1) * (1 - 0.88 * t * t);
    p.setXYZ(i, xx, len * (0.3 * t - 0.62 * t * t) - Math.abs(xx) * 0.5 * (1 - t * 0.5), t * len);
  }
  const c0 = new THREE.Color('#2c6a2c'), c1 = new THREE.Color('#6aa84e'), cc = new THREE.Color(), jit = 0.85 + Math.random() * 0.3;
  tint(g, (px, py, pz) => { cc.copy(c0).lerp(c1, Math.min(1, pz / len * 1.1)).multiplyScalar(jit); return '#' + cc.getHexString(); });
  g.rotateX(-pitch); g.rotateY(yaw); return g.translate(x, y, z);
}
function addTree(bi, bj, x, z, palm = false) {
  if (palm) {
    const th = rr(6, 8), la = srand() * 6.28, lean = rr(0.4, 1.4), n = 8, lx = Math.cos(la) * lean, lz = Math.sin(la) * lean;
    for (let i = 0; i < n; i++) {
      const t0 = i / n, t1 = (i + 1) / n, tm = (t0 + t1) / 2;
      addGeo('ptrunk', lam('#8a6d4a'), new THREE.CylinderGeometry(0.2 - 0.05 * t1, 0.22 - 0.05 * t0 + (i % 2 ? 0.03 : 0), th / n * 1.12, 7).translate(x + lx * tm * tm, 0.25 + th * tm, z + lz * tm * tm));
    }
    const cx = x + lx, cz = z + lz, cy = th + 0.25, nf = 10;
    for (let k = 0; k < nf; k++) addGeo('frond', frondMat, frondG(rr(3.0, 4.0), rr(0.7, 1.0), k / nf * 6.283 + rr(-0.2, 0.2), rr(-0.15, 0.5), cx, cy, cz));
    for (let k = 0; k < 3; k++) addGeo('foliage', foliageMat, blob(0.14, cx + rr(-0.2, 0.2), cy - 0.15, cz + rr(-0.2, 0.2), '#6b4a2a', 1));
  } else {
    const th = rr(2.6, 3.6), col = GREENS[srand() * GREENS.length | 0];
    addGeo('trunk', lam('#6b4f33'), new THREE.CylinderGeometry(0.2, 0.34, th, 7).translate(x, th / 2 + 0.25, z));
    if (srand() < 0.25) { // 침엽수
      const r = rr(1.3, 1.7), c = '#2f6b3c';
      for (let k = 0; k < 3; k++) addGeo('foliage', foliageMat, coneG(r * (1 - k * 0.25), 2.2, x, th + 0.6 + k * 1.2, z, c));
    } else {
      const r = rr(1.5, 2.1), cy = th + 0.9, nb = 5 + (srand() * 3 | 0);
      addGeo('foliage', foliageMat, blob(r, x, cy, z, col));
      for (let k = 0; k < nb; k++) { const a = k / nb * 6.283 + rr(-0.4, 0.4), d = r * rr(0.55, 0.85); addGeo('foliage', foliageMat, blob(r * rr(0.5, 0.75), x + Math.cos(a) * d, cy + rr(-0.5, 0.9), z + Math.sin(a) * d, GREENS[srand() * GREENS.length | 0])); }
    }
  }
  if (bi >= 0) colliders[bi + bj * N].push([x - 0.45, x + 0.45, z - 0.45, z + 0.45]);
}
// ---- 가로등: 블록당 8개(변마다 2개), 전부 merge. 실제 조명 없이 발광 전구(블룸) + 바닥 가짜 빛 웅덩이
const lampBulbMat = new THREE.MeshStandardMaterial({ color: '#2a2018', emissive: '#ffc374', emissiveIntensity: 4, roughness: 0.5 });
const poolMat = (() => {
  const c = makeCanvas(128, 128), x = c.getContext('2d'), g = x.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.35, 'rgba(255,255,255,.5)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 128, 128);
  return new THREE.MeshBasicMaterial({ map: tex(c, false), color: '#ffb866', transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false });
})();
function addLamps(x0, z0) {
  const pm = lam('#2b2d33'), HH = 6.5, ARM = 1.4;
  for (let sd = 0; sd < 4; sd++) for (const t of [0.25, 0.75]) {
    const a = t * B, px = sd === 0 ? x0 + a : sd === 1 ? x0 + B : sd === 2 ? x0 + B - a : x0, pz = sd === 0 ? z0 : sd === 1 ? z0 + a : sd === 2 ? z0 + B : z0 + B - a,
      nx = sd === 1 ? -1 : sd === 3 ? 1 : 0, nz = sd === 0 ? 1 : sd === 2 ? -1 : 0, bx = px + nx * 0.8, bz = pz + nz * 0.8, y0 = 0.25;
    addGeo('lampPole', pm, new THREE.CylinderGeometry(0.07, 0.11, HH, 6).translate(bx, y0 + HH / 2, bz));
    const ex = bx - nx * ARM / 2, ez = bz - nz * ARM / 2;
    addGeo('lampPole', pm, new THREE.BoxGeometry(nx ? ARM : 0.12, 0.12, nz ? ARM : 0.12).translate(ex, y0 + HH, ez));
    const lx = bx - nx * ARM, lz = bz - nz * ARM;
    addGeo('lampBulb', lampBulbMat, new THREE.BoxGeometry(0.5, 0.18, 0.5).translate(lx, y0 + HH - 0.12, lz), false);
    addGeo('lampPool', poolMat, new THREE.PlaneGeometry(11, 11).rotateX(-Math.PI / 2).translate(bx + nx * 2.2, y0 + 0.03, bz + nz * 2.2), false);
  }
}
// ================= 실제 지도(OSM): 내 주변 도로/건물/공원/물을 Overpass 에서 받아 게임 월드로 =================
let OSMG = null, OSMW = null; const OSMC = 40, osmShapes = new Map();
const osmKey = (cx, cz) => (cx + 600) * 2048 + (cz + 600);
async function osmFetch(lat, lon) {
  const rad = 450, A = `(around:${rad},${lat},${lon})`;
  const q = `[out:json][timeout:30];(way["highway"]["highway"!~"footway|path|steps|cycleway|pedestrian|track|corridor|proposed|construction|bus_guideway|elevator|platform|raceway|bridleway"]["service"!~"parking_aisle|driveway|drive-through|emergency_access"]${A};way["building"]${A};way["leisure"~"park|garden|playground|pitch|common"]${A};way["landuse"~"grass|forest|recreation_ground|village_green|meadow"]${A};way["natural"~"water|wood|grassland|scrub"]${A};way["waterway"="riverbank"]${A};);out body;>;out skel qt;`;
  let j = null, last = null;
  for (const ep of ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter', 'https://maps.mail.ru/osm/tools/overpass/api/interpreter']) {
    try { const ac = new AbortController(), to = setTimeout(() => ac.abort(), 28000); const r = await fetch(ep, { method: 'POST', body: 'data=' + encodeURIComponent(q), headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, signal: ac.signal }); clearTimeout(to); if (!r.ok) throw new Error('HTTP ' + r.status); j = await r.json(); break; } catch (e) { last = e; }
  }
  if (!j) throw last || new Error('overpass');
  const kx = 111320 * Math.cos(lat * Math.PI / 180), kz = 110540, nodes = new Map(), r1 = v => Math.round(v * 10) / 10;
  for (const e of j.elements) if (e.type === 'node') nodes.set(e.id, [r1((e.lon - lon) * kx), r1((e.lat - lat) * kz)]);
  const D = { lat, lon, roads: [], blds: [], parks: [], water: [], t: Date.now() }, LIM = 520;
  const WID = { motorway: 16, trunk: 16, primary: 14, secondary: 12, tertiary: 10, residential: 8, unclassified: 8, living_street: 7, service: 6 };
  for (const e of j.elements) {
    if (e.type !== 'way' || !e.nodes) continue;
    const pts = e.nodes.map(id => nodes.get(id)).filter(Boolean), tg = e.tags || {};
    if (pts.length < 2) continue;
    if (tg.highway) {
      let run = []; const w = WID[tg.highway] || 8, flush = () => { if (run.length > 1) D.roads.push({ w, p: run.flat() }); run = []; };
      for (const p of pts) { if (Math.abs(p[0]) < LIM + 40 && Math.abs(p[1]) < LIM + 40) run.push(p); else flush(); } flush();
    } else if (pts.length >= 4 && e.nodes[0] === e.nodes[e.nodes.length - 1]) {
      const c = pts.reduce((a, p) => [a[0] + p[0] / pts.length, a[1] + p[1] / pts.length], [0, 0]); if (Math.abs(c[0]) > LIM || Math.abs(c[1]) > LIM) continue;
      const poly = pts.slice(0, -1).flat();
      if (tg.building) { let h = parseFloat(tg.height) || 0; if (!h && tg['building:levels']) h = parseFloat(tg['building:levels']) * 3.4 + 0.6; D.blds.push({ p: poly, h: Math.round(h * 10) / 10, t: tg.building }); }
      else if (tg.natural === 'water' || tg.waterway === 'riverbank') D.water.push({ p: poly });
      else D.parks.push({ p: poly });
    }
  }
  return D;
}
const polyArea = p => { let a = 0; for (let i = 0, n = p.length; i < n; i += 2) { const j = (i + 2) % n; a += p[i] * p[j + 1] - p[j] * p[i + 1]; } return a / 2; };
function inPoly(x, z, p) { let c = false; for (let i = 0, n = p.length, j = n - 2; i < n; j = i, i += 2) if ((p[i + 1] > z) !== (p[j + 1] > z) && x < (p[j] - p[i]) * (z - p[i + 1]) / (p[j + 1] - p[i + 1]) + p[i]) c = !c; return c; }
function osmAddShape(p) { // 충돌용 다각형 (flat [x,z,...])
  let mnx = 1e9, mxx = -1e9, mnz = 1e9, mxz = -1e9; for (let i = 0; i < p.length; i += 2) { mnx = Math.min(mnx, p[i]); mxx = Math.max(mxx, p[i]); mnz = Math.min(mnz, p[i + 1]); mxz = Math.max(mxz, p[i + 1]); }
  const s = { p, mnx, mxx, mnz, mxz };
  for (let cx = Math.floor(mnx / OSMC); cx <= Math.floor(mxx / OSMC); cx++) for (let cz = Math.floor(mnz / OSMC); cz <= Math.floor(mxz / OSMC); cz++) { const k = osmKey(cx, cz); let l = osmShapes.get(k); if (!l) osmShapes.set(k, l = []); l.push(s); }
}
const osmCircle = (x, z, r) => osmAddShape([x - r, z - r, x + r, z - r, x + r, z + r, x - r, z + r]);
function pushOutOsm(cx, cz, r) {
  let sx = 0, sz = 0, hit = false;
  const c0 = Math.floor((cx - r) / OSMC), c1 = Math.floor((cx + r) / OSMC), d0 = Math.floor((cz - r) / OSMC), d1 = Math.floor((cz + r) / OSMC), seen = new Set();
  for (let a = c0; a <= c1; a++) for (let b = d0; b <= d1; b++) {
    const l = osmShapes.get(osmKey(a, b)); if (!l) continue;
    for (const s of l) {
      if (seen.has(s) || cx < s.mnx - r || cx > s.mxx + r || cz < s.mnz - r || cz > s.mxz + r) continue; seen.add(s);
      const p = s.p; let bd = 1e18, bx = 0, bz = 0;
      for (let i = 0, n = p.length; i < n; i += 2) {
        const j = (i + 2) % n, ex = p[j] - p[i], ez = p[j + 1] - p[i + 1], l2 = ex * ex + ez * ez || 1, t = clamp(((cx - p[i]) * ex + (cz - p[i + 1]) * ez) / l2, 0, 1), qx = p[i] + ex * t, qz = p[i + 1] + ez * t, d2 = (cx - qx) ** 2 + (cz - qz) ** 2;
        if (d2 < bd) { bd = d2; bx = qx; bz = qz; }
      }
      const inside = inPoly(cx, cz, p), d = Math.sqrt(bd);
      if (!inside && d >= r) continue;
      hit = true; const dx = bx - cx, dz = bz - cz, dl = Math.hypot(dx, dz) || 1;
      if (inside) { sx += dx / dl * (d + r); sz += dz / dl * (d + r); } else { sx -= dx / dl * (r - d); sz -= dz / dl * (r - d); }
    }
  }
  return hit ? { x: sx, z: sz } : null;
}
// ---- 도로 그래프
function osmGraph(roads) {
  const nodes = [], nmap = new Map(), edges = [], adj = [], cells = new Map();
  const nid = (x, z) => { const k = x + '|' + z; let i = nmap.get(k); if (i === undefined) { i = nodes.length; nmap.set(k, i); nodes.push({ x, z }); adj.push([]); } return i; };
  for (const r of roads) for (let i = 0; i + 3 < r.p.length; i += 2) {
    const a = nid(r.p[i], r.p[i + 1]), b = nid(r.p[i + 2], r.p[i + 3]); if (a === b) continue;
    const dx = r.p[i + 2] - r.p[i], dz = r.p[i + 3] - r.p[i + 1], len = Math.hypot(dx, dz); if (len < 0.5) continue;
    const e = { a, b, len, dx: dx / len, dz: dz / len, w: r.w }, ei = edges.length; edges.push(e); adj[a].push(ei); adj[b].push(ei);
    for (let t = 0; t <= len + 10; t += 10) { const tt = Math.min(t, len), cx = Math.floor((r.p[i] + e.dx * tt) / OSMC), cz = Math.floor((r.p[i + 1] + e.dz * tt) / OSMC); for (let ox = -1; ox <= 1; ox++) for (let oz = -1; oz <= 1; oz++) { const k = osmKey(cx + ox, cz + oz); let l = cells.get(k); if (!l) cells.set(k, l = []); if (l[l.length - 1] !== ei && !l.includes(ei)) l.push(ei); } }
  }
  return { nodes, edges, adj, cells };
}
function osmNearest(x, z, maxD = 80) { // 가장 가까운 도로 구간 {e, t(시작 노드부터 거리), d}
  const G = OSMG; if (!G) return null; let best = null;
  const cx = Math.floor(x / OSMC), cz = Math.floor(z / OSMC);
  for (let rad = 0; rad <= 3 && !best; rad++) for (let ox = -rad; ox <= rad; ox++) for (let oz = -rad; oz <= rad; oz++) {
    const l = G.cells.get(osmKey(cx + ox, cz + oz)); if (!l) continue;
    for (const ei of l) { const e = G.edges[ei], a = G.nodes[e.a], t = clamp((x - a.x) * e.dx + (z - a.z) * e.dz, 0, e.len), d = Math.hypot(a.x + e.dx * t - x, a.z + e.dz * t - z); if (d < maxD && (!best || d < best.d)) best = { e: ei, t, d }; }
  }
  return best;
}
function osmSnap(c) {
  const n = osmNearest(c.x, c.z, 120); if (!n) return; const e = OSMG.edges[n.e];
  if (e.dx * Math.sin(c.h) + e.dz * Math.cos(c.h) >= 0) { c.rp = e.a; c.rn = e.b; } else { c.rp = e.b; c.rn = e.a; }
}
function osmAdvance(c, chase) {
  const G = OSMG, n = c.rn, opts = [];
  for (const ei of G.adj[n]) { const e = G.edges[ei], to = e.a === n ? e.b : e.a; if (to !== c.rp) opts.push(to); }
  if (!opts.length) opts.push(c.rp);
  const cur = G.nodes[n], pv = G.nodes[c.rp], idx = Math.hypot(cur.x - pv.x, cur.z - pv.z) || 1, ix = (cur.x - pv.x) / idx, iz = (cur.z - pv.z) / idx;
  let pickN = opts[0];
  if (chase) { let bd = 1e9; for (const o of opts) { const q = G.nodes[o], d = Math.hypot(q.x - player.x, q.z - player.z); if (d < bd) { bd = d; pickN = o; } } }
  else if (opts.length > 1 && Math.random() < 0.55) { let bt = -2; for (const o of opts) { const q = G.nodes[o], l = Math.hypot(q.x - cur.x, q.z - cur.z) || 1, dt = ((q.x - cur.x) * ix + (q.z - cur.z) * iz) / l; if (dt > bt) { bt = dt; pickN = o; } } }
  else pickN = opts[Math.random() * opts.length | 0];
  c.rp = n; c.rn = pickN;
}
function osmRoadSpot(cx, cz, minD, maxD, mode) { // 도로 위('lane') / 길가 주차('curb') / 인도('walk') 무작위 지점
  const G = OSMG;
  for (let k = 0; k < 80; k++) {
    const e = G.edges[Math.random() * G.edges.length | 0]; if (e.len < 14) continue;
    const t = 6 + Math.random() * (e.len - 12), a = G.nodes[e.a], dirS = Math.random() < 0.5 ? 1 : -1, dx = e.dx * dirS, dz = e.dz * dirS, hw = e.w / 2;
    const off = mode === 'lane' ? 2.3 : mode === 'curb' ? (Math.random() < 0.5 ? 1 : -1) * (hw - 1.4) : (Math.random() < 0.5 ? 1 : -1) * (hw + 1.2);
    const x = a.x + e.dx * t - dz * off, z = a.z + e.dz * t + dx * off, d = Math.hypot(x - cx, z - cz);
    if (d >= minD && d <= maxD) return { x, z, e, dirS, d, dx, dz };
  }
  return null;
}
// ---- 월드 생성
function osmWalls(pts, y0, y1, uT, vT, key, mat) { // pts: [[x,z],...]  (닫힌 다각형, 첫점 반복 없음)
  const n = pts.length, pos = [], nor = [], uv = [], ccw = polyArea(pts.flat()) > 0; let cum = 0;
  for (let i = 0; i < n; i++) {
    const a = pts[i], b = pts[(i + 1) % n], ex = b[0] - a[0], ez = b[1] - a[1], len = Math.hypot(ex, ez); if (len < 0.05) continue;
    const nx = ccw ? ez / len : -ez / len, nz = ccw ? -ex / len : ex / len, u0 = cum / uT, u1 = (cum + len) / uT, v0 = 0, v1 = (y1 - y0) / vT; cum += len;
    const A = [a[0], y0, a[1]], Bv = [b[0], y0, b[1]], C = [b[0], y1, b[1]], Dv = [a[0], y1, a[1]];
    const tri = (p, q, r, up, uq, ur) => { // 바깥쪽 법선과 같은 방향 되게 감김 조정
      const e1 = [q[0] - p[0], q[1] - p[1], q[2] - p[2]], e2 = [r[0] - p[0], r[1] - p[1], r[2] - p[2]], cx = e1[1] * e2[2] - e1[2] * e2[1], cz = e1[0] * e2[1] - e1[1] * e2[0];
      if (cx * nx + cz * nz >= 0) { pos.push(...p, ...q, ...r); uv.push(...up, ...uq, ...ur); } else { pos.push(...p, ...r, ...q); uv.push(...up, ...ur, ...uq); }
      for (let k = 0; k < 3; k++) nor.push(nx, 0, nz);
    };
    tri(A, Bv, C, [u0, v0], [u1, v0], [u1, v1]); tri(A, C, Dv, [u0, v0], [u1, v1], [u0, v1]);
  }
  if (!pos.length) return; const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); addGeo(key, mat, g);
}
function osmFlat(p, y, uvS, key, mat, shadow = true) { // 다각형 윗면 (flat [x,z,...])
  const n = p.length / 2, cont = []; for (let i = 0; i < n; i++) cont.push(new THREE.Vector2(p[i * 2], p[i * 2 + 1]));
  let tris; try { tris = THREE.ShapeUtils.triangulateShape(cont, []); } catch (e) { return; } if (!tris.length) return;
  const pos = [], uv = [];
  for (const t of tris) { let [a, b, c] = t; const A = cont[a], Bv = cont[b], C = cont[c]; if ((Bv.y - A.y) * (C.x - A.x) - (Bv.x - A.x) * (C.y - A.y) < 0) { const tmp = b; b = c; c = tmp; } for (const i of [a, b, c]) { pos.push(cont[i].x, y, cont[i].y); uv.push(cont[i].x / uvS, cont[i].y / uvS); } }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); const nr = []; for (let i = 0; i < pos.length / 3; i++) nr.push(0, 1, 0); g.setAttribute('normal', new THREE.Float32BufferAttribute(nr, 3)); addGeo(key, mat, g, shadow);
}
function lampAt(bx, bz, nx, nz, y0) { // (nx,nz) = 도로 바깥쪽 방향. 팔은 도로 쪽으로
  const pm = lam('#2b2d33'), HH = 6.5, ARM = 1.4, ax = -nx, az = -nz;
  addGeo('lampPole', pm, new THREE.CylinderGeometry(0.07, 0.11, HH, 6).translate(bx, y0 + HH / 2, bz));
  const ang = Math.atan2(ax, az); addGeo('lampPole', pm, new THREE.BoxGeometry(0.12, 0.12, ARM).rotateY(ang).translate(bx + ax * ARM / 2, y0 + HH, bz + az * ARM / 2));
  addGeo('lampBulb', lampBulbMat, new THREE.BoxGeometry(0.5, 0.18, 0.5).translate(bx + ax * ARM, y0 + HH - 0.12, bz + az * ARM), false);
  addGeo('lampPool', poolMat, new THREE.PlaneGeometry(11, 11).rotateX(-Math.PI / 2).translate(bx + ax * 1.8, y0 + 0.03, bz + az * 1.8), false);
}
function buildOsmWorld(D) {
  MINB = -500; MAXB = 500; OSMG = osmGraph(D.roads);
  for (const t of [roadTex]) { t.map.repeat.set(1, 1); t.roughnessMap.repeat.set(1, 1); t.normalMap.repeat.set(1, 1); }
  // 땅
  { const g = new THREE.PlaneGeometry(3000, 3000).rotateX(-Math.PI / 2); const uv = g.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 750, uv.getY(i) * 750); addGeo('osmground', walkMat, g, false); }
  // 공원 / 물
  for (const p of D.parks) osmFlat(p.p, 0.02, 6, 'osmpark', grassMat, false);
  for (const p of D.water) osmFlat(p.p, 0.02, 4000, 'osmwater', waterMat, false);
  // 도로(리본) + 교차점 원판
  { const pos = [], uv = [];
    for (const r of D.roads) { let cum = 0; const hw = r.w / 2;
      for (let i = 0; i + 3 < r.p.length; i += 2) {
        const ax = r.p[i], az = r.p[i + 1], bx = r.p[i + 2], bz = r.p[i + 3], dx = bx - ax, dz = bz - az, len = Math.hypot(dx, dz); if (len < 0.3) continue;
        const nx = -dz / len * hw, nz = dx / len * hw, u0 = cum / 14, u1 = (cum + len) / 14; cum += len;
        const y = r.w >= 12 ? 0.034 : 0.03, L0 = [ax + nx, y, az + nz], R0 = [ax - nx, y, az - nz], L1 = [bx + nx, y, bz + nz], R1 = [bx - nx, y, bz - nz];
        const tri = (p, q, s, up, uq, us) => { if ((q[2] - p[2]) * (s[0] - p[0]) - (q[0] - p[0]) * (s[2] - p[2]) < 0) { pos.push(...p, ...s, ...q); uv.push(...up, ...us, ...uq); } else { pos.push(...p, ...q, ...s); uv.push(...up, ...uq, ...us); } };
        tri(L0, L1, R0, [u0, 0], [u1, 0], [u0, 1]); tri(R0, L1, R1, [u0, 1], [u1, 0], [u1, 1]);
      } }
    if (pos.length) { const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2)); const nr = []; for (let i = 0; i < pos.length / 3; i++) nr.push(0, 1, 0); g.setAttribute('normal', new THREE.Float32BufferAttribute(nr, 3)); addGeo('road', roadMat, g, false); }
    const rw = new Float32Array(OSMG.nodes.length); for (const e of OSMG.edges) { rw[e.a] = Math.max(rw[e.a], e.w); rw[e.b] = Math.max(rw[e.b], e.w); }
    OSMG.nodes.forEach((nd, i) => { if (OSMG.adj[i].length < 2) return; const g = new THREE.CircleGeometry(rw[i] / 2 + 0.05, 14).rotateX(-Math.PI / 2).translate(nd.x, 0.037, nd.z), u = g.attributes.uv; for (let k = 0; k < u.count; k++) u.setXY(k, g.attributes.position.getX(k) / 10, g.attributes.position.getZ(k) / 10); addGeo('osmjoint', jointMat, g, false); });
  }
  // 건물
  for (const b of D.blds) {
    const p = b.p, pts = []; for (let i = 0; i < p.length; i += 2) pts.push([p[i], p[i + 1]]);
    const area = Math.abs(polyArea(p)); if (area < 10 || pts.length < 3) continue;
    let h = b.h; if (!h) h = area < 120 ? rr(5, 9) : area < 600 ? rr(9, 22) : rr(12, 34); h = Math.min(h, 220);
    h = h >= 10.5 ? Math.max(10.5, Math.round(h / 3.5) * 3.5) : Math.max(4.5, h);
    const q = srand(), t = b.t || 'yes', office = /commercial|retail|office|hotel|public|civic|industrial|warehouse|hospital|school|university/.test(t), house = /house|detached|semidetached|terrace|bungalow|hut|garage|shed|roof/.test(t);
    const v = h > 38 ? (q < 0.55 ? 2 : 1) : office ? (h > 21 ? 1 : (q < 0.5 ? 1 : 0)) : house ? (q < 0.5 ? 0 : 3) : h > 21 ? (q < 0.35 ? 1 : q < 0.7 ? 0 : 3) : (q < 0.5 ? 0 : 3);
    const ci = srand() * BLD_COLS[v].length | 0, key = 'b' + v + ci, mat = buckets.get(key)?.mat || eMat({ color: BLD_COLS[v][ci], ...WIN[v], emissive: 0xffffff, emissiveIntensity: 0.85, roughness: 1, metalness: 1, normalScale: new THREE.Vector2(0.8, 0.8) });
    if (h >= 10.5) {
      const si = srand() * 4 | 0, pk = 'p' + si, pmat = buckets.get(pk)?.mat || eMat({ color: 0xffffff, ...STORE[si], emissive: 0xffffff, emissiveIntensity: 0.85, roughness: 1, metalness: 1, normalScale: new THREE.Vector2(0.7, 0.7) });
      osmWalls(pts, 0, 4.7, 8, 4.5, pk, pmat); osmWalls(pts, 4.7, h, 8, 7, key, mat);
    } else osmWalls(pts, 0, h, 8, 7, key, mat);
    osmFlat(p, h + 0.02, 10, 'roof', lam('#5d5866')); osmAddShape(p);
  }
  // 가로등 / 가로수 / 주차된 차
  const G = OSMG, parked = [];
  for (const e of G.edges) {
    if (e.w >= 14 && e.len < 20) continue; const a = G.nodes[e.a], hw = e.w / 2;
    for (let t = 12, k = 0; t < e.len - 8; t += 26, k++) {
      const sd = k % 2 ? 1 : -1, nx = -e.dz * sd, nz = e.dx * sd, bx = a.x + e.dx * t + nx * (hw + 0.9), bz = a.z + e.dz * t + nz * (hw + 0.9);
      if (Math.abs(bx) < 500 && Math.abs(bz) < 500) lampAt(bx, bz, nx, nz, 0.03);
      if (Math.random() < 0.45 && e.w <= 12) { const sx = -nx, sz = -nz, tx = a.x + e.dx * (t + 13) + sx * (hw + 2.3), tz = a.z + e.dz * (t + 13) + sz * (hw + 2.3); if (t + 13 < e.len && Math.abs(tx) < 500 && Math.abs(tz) < 500 && !pushOutOsm(tx, tz, 0.6)) { addTree(-1, -1, tx, tz); osmCircle(tx, tz, 0.45); } }
    }
  }
  for (const p of D.parks) { const ar = Math.abs(polyArea(p.p)), pp = p.p; let mnx = 1e9, mxx = -1e9, mnz = 1e9, mxz = -1e9; for (let i = 0; i < pp.length; i += 2) { mnx = Math.min(mnx, pp[i]); mxx = Math.max(mxx, pp[i]); mnz = Math.min(mnz, pp[i + 1]); mxz = Math.max(mxz, pp[i + 1]); }
    for (let k = 0, n = Math.min(40, ar / 220 | 0), tr = 0; k < n && tr < n * 8; tr++) { const x = mnx + Math.random() * (mxx - mnx), z = mnz + Math.random() * (mxz - mnz); if (inPoly(x, z, pp) && !pushOutOsm(x, z, 0.6)) { addTree(-1, -1, x, z); osmCircle(x, z, 0.45); k++; } } }
  for (let k = 0; k < 18; k++) { const s = osmRoadSpot(0, 0, 0, 1e9, 'curb'); if (s) parked.push({ x: s.x, z: s.z, h: Math.atan2(s.dx, s.dz) }); }
  // 시작 위치
  let start = { x: 0, z: 0, h: 0 }, red = { x: 0, z: 8, h: 0 }; const n0 = osmNearest(0, 0, 400);
  if (n0) { const e = G.edges[n0.e], a = G.nodes[e.a], t = clamp(n0.t, 8, Math.max(8, e.len - 12)), hw = e.w / 2; start = { x: a.x + e.dx * t - e.dz * (hw + 1.4), z: a.z + e.dz * t + e.dx * (hw + 1.4), h: Math.atan2(e.dx, e.dz) }; red = { x: a.x + e.dx * (t + 4.5) - e.dz * 2.3, z: a.z + e.dz * (t + 4.5) + e.dx * 2.3, h: Math.atan2(e.dx, e.dz) }; }
  const far = (lo, hi, skip) => { for (let k = 0; k < 200; k++) { const nd = G.nodes[Math.random() * G.nodes.length | 0], d = Math.hypot(nd.x, nd.z); if (d >= lo && d <= hi && (!skip || Math.hypot(nd.x - skip.x, nd.z - skip.z) > 120)) return { x: nd.x + 5, z: nd.z + 5 }; } return { x: lo, z: lo }; };
  const hosp = far(120, 380), station = far(120, 380, hosp);
  return { start, red, hosp, station, parked };
}
const parkedSpots = [];
function buildGrid() {
for (let i = 0; i < N; i++) for (let j = 0; j < N; j++) {
  const x0 = i * P + R / 2, z0 = j * P + R / 2, cx = x0 + B / 2, cz = z0 + B / 2;
  addLamps(x0, z0);
  addGeo('walk', walkMat, boxUV(new THREE.BoxGeometry(B, 0.25, B), 4).translate(cx, 0.125, cz));
  const ix0 = x0 + SW, iz0 = z0 + SW, IS = B - 2 * SW;
  const c = clamp(1 - Math.hypot(cx - CITY / 2, cz - CITY / 2) / (CITY * 0.55), 0, 1);
  const r = srand();
  let kind = r < 0.1 ? 'park' : r < 0.2 ? 'lot' : 'bld';
  if (i === 4 && j === 3) kind = 'lot';
  if (i === 3 && j === 4) kind = 'park';
  blocks.push({ i, j, x0, z0, kind });
  if (kind === 'park') {
    addGeo('grass', grassMat, boxUV(new THREE.BoxGeometry(IS, 0.06, IS), 6).translate(cx, 0.28, cz));
    const n = 6 + (srand() * 5 | 0);
    for (let k = 0; k < n; k++) addTree(i, j, rr(ix0 + 3, ix0 + IS - 3), rr(iz0 + 3, iz0 + IS - 3));
  } else if (kind === 'lot') {
    addGeo('lot', lotMat, boxUV(new THREE.BoxGeometry(IS, 0.05, IS), 10).translate(cx, 0.275, cz));
    for (let row = 0; row < 2; row++) for (let k = 0; k < 8; k++) {
      const px = ix0 + 4 + k * 6, pz = row ? iz0 + IS - 8 : iz0 + 8;
      addGeo('lotline', lam('#e8e8e8'), new THREE.BoxGeometry(0.15, 0.02, 5).translate(px - 3, 0.31, pz), false);
      if (srand() < 0.3) parkedSpots.push({ x: px, z: pz, h: row ? Math.PI : 0 });
    }
  } else {
    const H = () => 8 + srand() * 16 + (srand() < 0.3 + c * 0.45 ? c * c * rr(28, 78) : 0);
    const lr = srand(), gap = 3;
    if (lr < 0.25) { const ins = rr(0, 4); addBuilding(i, j, ix0 + ins, iz0 + ins, IS - 2 * ins, IS - 2 * ins, H(), c); }
    else if (lr < 0.6) {
      const w = (IS - gap) / 2;
      if (srand() < 0.5) { addBuilding(i, j, ix0, iz0, w, IS, H()); addBuilding(i, j, ix0 + w + gap, iz0, w, IS, H()); }
      else { addBuilding(i, j, ix0, iz0, IS, w, H()); addBuilding(i, j, ix0, iz0 + w + gap, IS, w, H()); }
    } else {
      const q = (IS - gap) / 2;
      for (let a = 0; a < 2; a++) for (let b = 0; b < 2; b++) { const ins = rr(0, 2.5); addBuilding(i, j, ix0 + a * (q + gap) + ins, iz0 + b * (q + gap) + ins, q - 2 * ins, q - 2 * ins, H()); }
    }
  }
}
// roads
for (let k = 0; k <= N; k++) {
  addGeo('road', roadMat, new THREE.PlaneGeometry(CITY + R, R).rotateX(-Math.PI / 2).translate(CITY / 2, 0.02, k * P), false);
  addGeo('road', null, new THREE.PlaneGeometry(CITY + R, R).rotateX(-Math.PI / 2).rotateY(Math.PI / 2).translate(k * P, 0.021, CITY / 2), false);
  for (let m = 0; m <= N; m++) addGeo('cross', crossMat, new THREE.PlaneGeometry(R, R).rotateX(-Math.PI / 2).translate(k * P, 0.03, m * P), false);
}
// beach + palms + water
{
  const s = CITY + R + 26;
  addGeo('sand', lam('#e6cf9c'), new THREE.BoxGeometry(s, 0.4, s).translate(CITY / 2, -0.2, CITY / 2), false);
  for (let t = 0; t <= CITY; t += 22) {
    const o = -R / 2 - 11;
    addTree(-1, -1, t, o, true); addTree(-1, -1, t, CITY - o, true); addTree(-1, -1, o, t, true); addTree(-1, -1, CITY - o, t, true);
  }
  const water = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000).rotateX(-Math.PI / 2), waterMat);
  water.position.set(CITY / 2, -0.35, CITY / 2); water.receiveShadow = true; scene.add(water);
}
}
OSMW = OSM ? buildOsmWorld(OSM) : (buildGrid(), null);
if (OSMW) parkedSpots.push(...OSMW.parked);
for (const [, b] of buckets) {
  const m = new THREE.Mesh(mergeGeometries(b.geos), b.mat);
  m.receiveShadow = true; m.castShadow = b.shadow; scene.add(m);
}
function groundY(x, z) {
  if (OSMG) return 0.03;
  const bi = Math.floor(x / P), bj = Math.floor(z / P);
  if (bi < 0 || bj < 0 || bi >= N || bj >= N) return 0;
  const lx = x - bi * P, lz = z - bj * P;
  return (lx > R / 2 && lx < P - R / 2 && lz > R / 2 && lz < P - R / 2) ? 0.25 : 0;
}
function pushOut(cx, cz, r) {
  if (OSMG) return pushOutOsm(cx, cz, r);
  const bi = Math.floor(cx / P), bj = Math.floor(cz / P);
  if (bi < 0 || bj < 0 || bi >= N || bj >= N) return null;
  let sx = 0, sz = 0, hit = false;
  for (const a of colliders[bi + bj * N]) {
    const px = clamp(cx, a[0], a[1]), pz = clamp(cz, a[2], a[3]);
    const dx = cx - px, dz = cz - pz, d2 = dx * dx + dz * dz;
    if (d2 >= r * r) continue;
    hit = true;
    if (d2 > 1e-8) { const d = Math.sqrt(d2); sx += dx / d * (r - d); sz += dz / d * (r - d); }
    else {
      const l = cx - a[0], rg = a[1] - cx, t = cz - a[2], bt = a[3] - cz, m = Math.min(l, rg, t, bt);
      if (m === l) sx -= l + r; else if (m === rg) sx += rg + r; else if (m === t) sz -= t + r; else sz += bt + r;
    }
  }
  return hit ? { x: sx, z: sz } : null;
}

// ================= characters =================
const pedGeo = { gun: new THREE.BoxGeometry(0.1, 0.12, 0.4).translate(0, -0.36, 0.12) };
const SHIRT = ['#e63946', '#f1faee', '#457b9d', '#2a9d8f', '#e9c46a', '#f4a261', '#9b5de5', '#00bbf9', '#f15bb5', '#3a3a3a', '#8ac926'];
const PANTS = ['#1d3557', '#2b2d42', '#6c584c', '#3d405b', '#495057', '#8d99ae'];
const SKIN = ['#f1c9a5', '#e0ac82', '#b07a52', '#7d5636'];
const HAIR = ['#1b1b1b', '#3b2a1e', '#6b4a2b', '#c9a15b', '#4a2c1a', '#8c8c8c'];
// 사람: SkinnedMesh(뼈대 11개, 메시 1개 = draw call 1개). 부위별 vertex color(+굽힘 부위는 두 뼈에 가중치) + 구워 넣은 AO. NPC 는 변형 풀에서 지오메트리 공유
// 7.5등신 비율, 곡선(lathe) 몸통/팔다리, 목/어깨/손/신발, 얼굴(눈·눈썹·코·입·귀), 머리 모양 4종, 안경, 옷(깃/벨트/밑단/소매/코트/치마/배낭)
const pedMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.8, metalness: 0 });
const PB = { hips: 0, chest: 1, head: 2, thL: 3, shL: 4, thR: 5, shR: 6, upL: 7, fL: 8, upR: 9, fR: 10 };
const pstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const pcm = new Map(), pcol = h => { let c = pcm.get(h); if (!c) { c = new THREE.Color(h); pcm.set(h, c); } return c; };
function pedBuild(o) {
  const PSEG = quality === 'low' ? 8 : quality === 'mid' ? 10 : 14, parts = [];
  const add = (geo, col, w, mod) => parts.push([geo, col, w, mod]);
  const bx = (w, h, d, x, y, z, col, bn) => add(new THREE.BoxGeometry(w, h, d).translate(x, y, z), col, bn);
  const sp = (r, sx, sy, sz, x, y, z, col, bn, ws = 8, hs = 6) => add(new THREE.SphereGeometry(r, ws, hs).scale(sx, sy, sz).translate(x, y, z), col, bn);
  const lat = (keys, sx, sz, cx, cz, seg, n) => { // y-r 키를 스플라인으로 부드럽게 돌려 만든 곡면(위아래 뚜껑 포함)
    const pts = new THREE.SplineCurve(keys.map(([y, r]) => new THREE.Vector2(r, y))).getPoints(n);
    for (const p of pts) p.x = Math.max(0, p.x);
    pts.unshift(new THREE.Vector2(0, pts[0].y)); pts.push(new THREE.Vector2(0, pts[pts.length - 1].y));
    const g = new THREE.LatheGeometry(pts, seg); g.scale(sx, 1, sz); g.translate(cx, 0, cz); return g;
  };
  const { shirt, pants, skin, hair, style = 0, dress, shorts, longSl, pack, coat, pcol: packCol = '#2b2d42', fem = false, shoe = '#1d1d22', tucked = true, glasses = false } = o;
  const hw = fem ? 1.07 : 1, fw = fem ? 0.93 : 1, SEG = Math.max(8, PSEG);

  // ---- 몸통(골반~어깨): 허리에서 두 뼈에 가중치를 나눠 비틀 때 안 찢어짐
  const topAll = dress || coat, hemY = tucked ? 1.06 : 0.935;
  const torsoK = [[0.86, 0.14], [0.92, 0.185 * hw], [1.0, 0.17 * hw], [1.1, 0.15], [1.17, 0.147], [1.26, 0.162 * fw], [1.36, 0.18 * fw], [1.46, 0.194 * fw], [1.54, 0.196 * fw], [1.59, 0.165 * fw], [1.625, 0.075]];
  add(lat(torsoK, 1, 0.64, 0, 0, SEG + 2, 30),
    (x, y) => topAll ? shirt : (y > hemY ? shirt : (tucked && y > 1.015 ? '#1c1a19' : pants)),
    (x, y) => { const w = pstep(1.12, 1.28, y); return [[PB.hips, 1 - w], [PB.chest, w]]; },
    (x, y, z) => (!tucked && !topAll && y > 0.93 && y < 1.03) ? [x * 1.035, y, z * 1.035] : [x, y, z]);
  if (fem && !dress) { for (const s of [-1, 1]) sp(0.062, 1, 0.95, 0.9, s * 0.074, 1.4, 0.088, shirt, PB.chest, 8, 6); }
  // 목 + 깃
  add(lat([[1.55, 0.06], [1.62, 0.052], [1.7, 0.05], [1.74, 0.052]], 1, 1, 0, 0.008, 8, 8), skin,
    (x, y) => { const w = pstep(1.6, 1.68, y); return [[PB.chest, 1 - w], [PB.head, w]]; });
  add(new THREE.TorusGeometry(0.06, 0.011, 5, 12).rotateX(Math.PI / 2).scale(1, 1, 1.1).translate(0, 1.63, 0.004), coat ? '#1d1d1d' : shirt, PB.chest);

  // ---- 머리
  const hh = 0.135, hwd = 0.088, hd = 0.105, hy = 1.82;
  const hs = (x, y) => { const dy = y - hy, t = dy < 0 ? -dy / hh : 0, w = hwd * (1 - 0.26 * Math.pow(t, 1.6)), q = 1 - (x / w) ** 2 - (dy / hh) ** 2; return hd * (dy < 0 ? 1 - 0.1 * t : 1) * Math.sqrt(Math.max(0, q)); };
  const skull = new THREE.SphereGeometry(1, PSEG + 4, PSEG + 1), sp0 = skull.attributes.position;
  for (let i = 0; i < sp0.count; i++) {
    let x = sp0.getX(i), y = sp0.getY(i), z = sp0.getZ(i); const t = y < 0 ? -y : 0;
    sp0.setXYZ(i, x * hwd * (1 - 0.26 * Math.pow(t, 1.6)), y * hh + hy, z * hd * (y < 0 ? 1 - 0.1 * t : 1));
  }
  skull.computeVertexNormals();
  const hairY = (x, z) => { let b = 1.89 - 0.15 * clamp((0.04 - z) / 0.14, 0, 1); if (Math.abs(x) > 0.07) b = Math.min(b, 1.855); return b; };
  const hairC = style === 3 ? '#' + pcol(skin).clone().lerp(pcol(hair), 0.62).getHexString() : hair;
  const hair0 = style === 3 ? 1.03 : 1.065;
  { // 머리카락 껍질: 두개골 삼각형 중 머리선 위쪽을 조금 부풀려서 복사
    const idx = skull.index.array, keep = [];
    for (let i = 0; i < idx.length; i += 3) { let cx = 0, cy = 0, cz = 0; for (let k = 0; k < 3; k++) { cx += sp0.getX(idx[i + k]); cy += sp0.getY(idx[i + k]); cz += sp0.getZ(idx[i + k]); } cx /= 3; cy /= 3; cz /= 3; if (cy > hairY(cx, cz)) keep.push(idx[i], idx[i + 1], idx[i + 2]); }
    const sh = skull.clone(); sh.setIndex(keep); sh.translate(0, -hy, 0); sh.scale(hair0, hair0, hair0); sh.translate(0, hy, -0.004); add(sh, hairC, PB.head);
  }
  add(skull, (x, y, z) => y > hairY(x, z) ? hairC : skin, PB.head);
  if (style === 1) add(new THREE.CapsuleGeometry(0.093, 0.2, 4, 8).scale(1.08, 1, 0.62).translate(0, 1.67, -0.068), hair, PB.head);
  if (style === 2) sp(0.056, 1, 1, 1, 0, 1.975, -0.085, hair, PB.head, 8, 6);
  for (const s of [-1, 1]) sp(0.017, 0.5, 1.35, 0.9, s * (hwd + 0.001), 1.815, -0.006, skin, PB.head); // 귀
  for (const s of [-1, 1]) { // 눈 / 눈썹
    const ex = s * 0.036, ey = 1.835, z = hs(Math.abs(ex), ey);
    sp(0.0135, 1.15, 0.85, 0.55, ex, ey, z - 0.003, '#efebe4', PB.head); sp(0.0072, 1, 1, 0.5, ex, ey, z + 0.002, '#2b1d14', PB.head);
    bx(0.04, 0.008, 0.012, ex, 1.868, hs(Math.abs(ex), 1.868) - 0.004, hair, PB.head);
  }
  sp(0.01, 0.8, 2.3, 0.8, 0, 1.826, hs(0, 1.826), skin, PB.head); sp(0.0145, 0.95, 1.2, 1.1, 0, 1.804, hs(0, 1.804) + 0.006, skin, PB.head); // 코
  sp(0.02, 1.4, 0.34, 0.55, 0, 1.748, hs(0, 1.748), '#b45c58', PB.head); sp(0.017, 1.25, 0.34, 0.55, 0, 1.738, hs(0, 1.738), '#b86a64', PB.head); // 입술
  if (glasses) {
    for (const s of [-1, 1]) add(new THREE.TorusGeometry(0.021, 0.003, 4, 10).translate(s * 0.036, 1.835, hs(0.036, 1.835) + 0.008), '#171717', PB.head);
    bx(0.02, 0.003, 0.003, 0, 1.838, hs(0, 1.838) + 0.009, '#171717', PB.head);
    for (const s of [-1, 1]) bx(0.003, 0.003, 0.1, s * 0.083, 1.835, 0.04, '#171717', PB.head);
  }

  // ---- 치마/코트/배낭
  if (dress) add(lat([[0.62, 0.285], [0.72, 0.265], [0.84, 0.23], [0.97, 0.185], [1.1, 0.155]], 1, 0.9, 0, 0, SEG + 2, 14), shirt, PB.hips);
  if (coat) add(lat([[0.68, 0.27], [0.8, 0.245], [0.92, 0.215], [1.03, 0.19], [1.15, 0.168]], 1, 0.9, 0, 0, SEG + 2, 14), shirt, PB.hips);
  if (pack) {
    bx(0.3, 0.4, 0.15, 0, 1.4, -0.2, packCol, PB.chest); bx(0.24, 0.16, 0.05, 0, 1.33, -0.29, packCol, PB.chest);
    for (const s of [-1, 1]) bx(0.032, 0.34, 0.02, s * 0.09, 1.43, 0.12, '#1c1c1c', PB.chest);
  }

  // ---- 팔다리 (양쪽)
  const clothY = dress ? 99 : shorts ? 0.56 : 0.075, sleeveY = (longSl || coat) ? 1.0 : 1.4;
  for (const s of [-1, 1]) {
    const L = s < 0, lx = s * 0.095, ax = s * 0.225, th = L ? PB.thL : PB.thR, sh = L ? PB.shL : PB.shR, ua = L ? PB.upL : PB.upR, fa = L ? PB.fL : PB.fR;
    // 다리(고관절 → 발목). 무릎에서 허벅지/정강이 뼈에 가중치를 나눔
    add(lat([[0.07, 0.046], [0.14, 0.05], [0.26, 0.062], [0.34, 0.07], [0.42, 0.063], [0.47, 0.058], [0.55, 0.076], [0.7, 0.093], [0.84, 0.102], [0.93, 0.1]], 1, 1, lx, 0, SEG, 24),
      (x, y) => y > clothY ? pants : skin,
      (x, y) => { if (y > 0.7) { const w = pstep(0.95, 0.84, y); return [[PB.hips, 1 - w], [th, w]]; } const w = pstep(0.54, 0.4, y); return [[th, 1 - w], [sh, w]]; },
      (x, y, z) => y > clothY ? [lx + (x - lx) * 1.1, y, z * 1.1] : [x, y, z]);
    // 신발
    sp(0.05, 0.85, 0.62, 1.55, lx, 0.052, 0.07, shoe, sh); sp(0.046, 0.9, 0.8, 1, lx, 0.06, -0.035, shoe, sh); bx(0.092, 0.018, 0.235, lx, 0.009, 0.03, shoe === '#e9e9e6' ? '#bdbdb8' : '#26262a', sh);
    // 팔(어깨 → 손목)
    add(lat([[0.985, 0.028], [1.05, 0.034], [1.15, 0.041], [1.22, 0.045], [1.28, 0.044], [1.35, 0.049], [1.45, 0.052], [1.54, 0.056], [1.595, 0.048]], 1, 1, ax, 0, Math.max(6, SEG - 2), 20),
      (x, y) => y > sleeveY ? shirt : skin,
      (x, y) => { if (y > 1.4) { const w = pstep(1.62, 1.52, y); return [[PB.chest, 1 - w], [ua, w]]; } const w = pstep(1.34, 1.22, y); return [[ua, 1 - w], [fa, w]]; },
      (x, y, z) => y > sleeveY ? [ax + (x - ax) * 1.07, y, z * 1.07] : [x, y, z]);
    sp(0.05, 1, 1, 1, ax, 1.55, 0, shirt, ua, 8, 6); // 어깨
    // 손: 손바닥 + 손가락 + 엄지
    sp(0.04, 0.6, 1.1, 1, ax, 0.935, 0, skin, fa); sp(0.036, 0.55, 1.2, 0.95, ax, 0.872, 0.005, skin, fa); sp(0.014, 1, 2.4, 1, ax - s * 0.021, 0.925, 0.032, skin, fa, 6, 5);
  }

  const ao = (x, y, z) => { // 구워 넣은 간이 AO: 바닥/사타구니/턱 밑/겨드랑이
    let a = 1; const ax = Math.abs(x);
    if (y < 0.3) a *= 0.86 + 0.14 * y / 0.3;
    if (y > 0.4 && y < 0.9 && ax < 0.06) a *= 0.78 + 0.22 * ax / 0.06;
    if (y > 1.6 && y < 1.7 && z > 0) a *= 0.82;
    if (ax > 0.15 && ax < 0.2 && y > 1.36 && y < 1.54) a *= 0.88;
    return a;
  };
  const gs = parts.map(([geo, col, wt, mod]) => {
    geo = geo.index ? geo.toNonIndexed() : geo; geo.deleteAttribute('uv');
    const pa = geo.attributes.position, n = pa.count, ca = new Float32Array(n * 3), si = new Uint16Array(n * 4), sw = new Float32Array(n * 4), cf = typeof col === 'function';
    for (let i = 0; i < n; i++) {
      let x = pa.getX(i), y = pa.getY(i), z = pa.getZ(i);
      if (mod) { const m = mod(x, y, z); x = m[0]; y = m[1]; z = m[2]; pa.setXYZ(i, x, y, z); }
      const c = pcol(cf ? col(x, y, z) : col), a = ao(x, y, z);
      ca[i * 3] = c.r * a; ca[i * 3 + 1] = c.g * a; ca[i * 3 + 2] = c.b * a;
      if (typeof wt === 'number') { si[i * 4] = wt; sw[i * 4] = 1; }
      else { const w = wt(x, y, z); si[i * 4] = w[0][0]; sw[i * 4] = w[0][1]; si[i * 4 + 1] = w[1][0]; sw[i * 4 + 1] = w[1][1]; }
    }
    geo.setAttribute('color', new THREE.BufferAttribute(ca, 3)); geo.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4)); geo.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
    return geo;
  });
  return mergeGeometries(gs);
}
const pickR = a => a[Math.random() * a.length | 0];
function pedOpts() {
  const R = Math.random, dress = R() < 0.2, fem = dress || R() < 0.3;
  return { shirt: pickR(SHIRT), pants: pickR(PANTS), skin: pickR(SKIN), hair: pickR(HAIR), style: fem ? pickR([1, 1, 2, 0]) : pickR([0, 0, 3, 3, 0]), dress, fem, shorts: !dress && R() < 0.28, longSl: R() < 0.5, pack: R() < 0.22, coat: !dress && R() < 0.18, pcol: pickR(['#2b2d42', '#7a2e3a', '#2f5d50', '#c9a43e', '#3a3a3a']), shoe: pickR(['#1d1d22', '#2b2b30', '#e9e9e6', '#6b4a33', '#3a4a6a']), tucked: R() < 0.5, glasses: R() < 0.1 };
}
const pedPool = [];
function makePerson(shirt, pants, skin, hair, gun) {
  let geo;
  if (gun) geo = pedBuild({ shirt, pants, skin, hair, style: 0, dress: false, shorts: false, longSl: false, pack: false, coat: false });
  else { const i = Math.random() * 30 | 0; geo = pedPool[i] || (pedPool[i] = pedBuild(pedOpts())); }
  const g = new THREE.Group(), mk = (x, y, z) => { const b = new THREE.Bone(); b.position.set(x, y, z); return b; };
  const bones = [mk(0, 0.95, 0), mk(0, 0.4, 0), mk(0, 0.25, 0), mk(-0.095, -0.06, 0), mk(0, -0.42, 0), mk(0.095, -0.06, 0), mk(0, -0.42, 0), mk(-0.225, 0.22, 0), mk(0, -0.29, 0), mk(0.225, 0.22, 0), mk(0, -0.29, 0)];
  bones[0].add(bones[1], bones[3], bones[5]); bones[1].add(bones[2], bones[7], bones[9]); bones[3].add(bones[4]); bones[5].add(bones[6]); bones[7].add(bones[8]); bones[9].add(bones[10]);
  const mesh = new THREE.SkinnedMesh(geo, pedMat); mesh.castShadow = true; mesh.add(bones[0]); g.add(mesh); g.updateMatrixWorld(true);
  mesh.bind(new THREE.Skeleton(bones));
  if (gun) bones[PB.fR].add(new THREE.Mesh(pedGeo.gun, lam('#222')));
  if (!gun) g.scale.set(0.92 + Math.random() * 0.18, 0.93 + Math.random() * 0.14, 1);
  scene.add(g);
  const b = bones;
  return { g, hips: b[0], chest: b[1], head: b[2], legL: b[3], shL: b[4], legR: b[5], shR: b[6], armL: b[7], fL: b[8], armR: b[9], fR: b[10], phase: Math.random() * 6 };
}
function animLegs(o, sp, dt) {
  o.phase += sp * dt * 1.7;
  const k = Math.min(1, sp / 2), ph = o.phase, a = Math.sin(ph) * 0.75 * k, c = Math.cos(ph), s = Math.sin(ph);
  o.legL.rotation.x = a; o.legR.rotation.x = -a;
  o.shL.rotation.x = Math.max(0, -c) * 1.0 * k + 0.03; o.shR.rotation.x = Math.max(0, c) * 1.0 * k + 0.03;
  o.armL.rotation.x = -a * 0.8; o.armR.rotation.x = a * 0.8;
  o.fL.rotation.x = -(0.12 + k * (0.15 + 0.5 * Math.max(0, s))); o.fR.rotation.x = -(0.12 + k * (0.15 + 0.5 * Math.max(0, -s)));
  o.hips.position.y = 0.95 - 0.02 * k + Math.abs(c) * 0.04 * k; o.chest.rotation.y = s * 0.12 * k; o.hips.rotation.y = -s * 0.06 * k; o.head.rotation.y = -s * 0.05 * k;
}

// ================= cars =================
// ---- 자동차: Kenney Car Kit 3.1 (CC0, www.kenney.nl) 모델. 팔레트 텍스처의 '도장' 칸 UV 를 바꿔서 색을 바꿈
const KTEX = (() => { const t = new THREE.Texture(); t.flipY = false; t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; const img = new Image(); img.onload = () => { t.image = img; t.needsUpdate = true; }; img.src = CAR_TEX; return t; })();
const kMat = quality === 'low' ? new THREE.MeshStandardMaterial({ map: KTEX, roughness: 0.55, metalness: 0.1 }) : new THREE.MeshPhysicalMaterial({ map: KTEX, roughness: 0.5, metalness: 0.12, clearcoat: 0.8, clearcoatRoughness: 0.12 });
const b64u = (s, T) => { const bin = atob(s), u8 = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i); return new T(u8.buffer); };
function kMesh(d) {
  const n = d.n, pq = b64u(d.p, Uint16Array), nq = b64u(d.nr, Int8Array), uq = b64u(d.uv, Uint16Array), p = new Float32Array(n * 3), nr = new Float32Array(n * 3), uv = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) { for (let c = 0; c < 3; c++) { p[i * 3 + c] = d.mn[c] + pq[i * 3 + c] / 65535 * (d.mx[c] - d.mn[c]); nr[i * 3 + c] = nq[i * 3 + c] / 127; } for (let c = 0; c < 2; c++) uv[i * 2 + c] = d.um[c] + uq[i * 2 + c] / 65535 * (d.ux[c] - d.um[c]); }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(p, 3)); g.setAttribute('normal', new THREE.BufferAttribute(nr, 3)); g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  g.setIndex(new THREE.BufferAttribute(b64u(d.i, d.i32 ? Uint32Array : Uint16Array), 1)); return g;
}
const kCache = new Map(), kVar = new Map();
function kModel(name) {
  let m = kCache.get(name); if (m) return m;
  const d = CAR_MODELS[name], wR = kMesh(d.wf), wL = wR.clone().rotateY(Math.PI);
  m = { d, body: kMesh(d.body), wR, wL, bp: d.bodyPos, fz: d.wpos.fr[2], bz: d.wpos.br[2], wx: Math.abs(d.wpos.fr[0]), top: d.body.mx[1] + d.bodyPos[1], front: d.body.mx[2] + d.bodyPos[2], back: d.body.mn[2] + d.bodyPos[2] };
  kCache.set(name, m); return m;
}
// 팔레트 칸 [열,행]: 모델별 원래 도장 칸 / 색 이름별 바꿀 칸
const K_PAINT = { sedan: [6, 1], 'sedan-sports': [6, 1], 'hatchback-sports': [3, 1], suv: [3, 1], 'suv-luxury': [4, 1], van: [7, 1], truck: [3, 1], delivery: [3, 1] };
const K_CELL = { '#e94f37': [6, 1], '#f6c445': [4, 1], '#3c91e6': [7, 1], '#5fbf77': [3, 1], '#f2f2f2': [6, 2], '#2b2b33': [4, 2], '#ff8fab': [7, 3], '#8e6cef': [1, 0], '#ff9f1c': [5, 1], '#2ec4b6': [4, 3], '#7d1d2c': [2, 3], '#9aa5b1': [3, 2] };
function kBody(name, hex) {
  const K = kModel(name), src = K_PAINT[name], dst = K_CELL[hex];
  if (!src || !dst || (src[0] === dst[0] && src[1] === dst[1])) return K.body;
  const key = name + hex; let g = kVar.get(key); if (g) return g;
  g = K.body.clone(); const uv = new Float32Array(K.body.attributes.uv.array);
  for (let i = 0; i < uv.length; i += 2) if (Math.floor(uv[i] * 8) === src[0] && Math.floor(uv[i + 1] * 4) === src[1]) { uv[i] += (dst[0] - src[0]) / 8; uv[i + 1] += (dst[1] - src[1]) / 4; }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2)); kVar.set(key, g); return g;
}
const KS = 1.5, CIV_MODELS = ['sedan', 'sedan', 'sedan-sports', 'hatchback-sports', 'hatchback-sports', 'suv', 'suv-luxury', 'taxi', 'van', 'truck', 'delivery'];
const cars = [];
function makeCar(type, color, model) {
  const name = type === 'cop' ? 'police' : (model || CIV_MODELS[Math.random() * CIV_MODELS.length | 0]), K = kModel(name);
  const g = new THREE.Group(), rig = new THREE.Group(), mod = new THREE.Group(); mod.scale.setScalar(KS);
  const bodyMesh = new THREE.Mesh(kBody(name, color), kMat); bodyMesh.position.set(...K.bp); bodyMesh.castShadow = true; mod.add(bodyMesh);
  const wp = [], wm = [];
  for (const [sx, front] of [[-1, 1], [1, 1], [-1, 0], [1, 0]]) {
    const p = new THREE.Group(), m = new THREE.Mesh(sx < 0 ? K.wR : K.wL, kMat); p.position.set(sx * K.wx, 0.3, front ? K.fz : K.bz); p.add(m); mod.add(p); wp.push(p); wm.push(m);
  }
  const lz = (z, w) => mergeGeometries([-1, 1].map(x => new THREE.BoxGeometry(0.34, 0.1, 0.05).translate(x * 0.5, K.bp[1] + 0.4, z)));
  const head = new THREE.Mesh(lz(K.front + 0.005), headMat), tail = new THREE.Mesh(lz(K.back - 0.005), tailOff); mod.add(head, tail);
  rig.add(mod); g.add(rig);
  const fire = new THREE.Mesh(carGeoFire, fireMat); fire.position.set(0, 1.3, 1.3); fire.visible = false; g.add(fire);
  const c = { g, body: rig, bodyMesh, cabin: { material: null }, glass: { material: null }, driverM: { visible: false }, head, tail, wp, wm, wheelRot: 0, pitch: 0, fire, type, paintHex: color, kname: name, x: 0, z: 0, y: 0, h: 0, vx: 0, vz: 0, vF: 0, vL: 0, steer: 0, steerIn: 0, throttle: 0, hb: false, health: 100, burning: false, burnT: 0, wreck: false, wreckT: 0, driver: null, mode: 'traffic', ti: 0, tj: 0, d: 0, stuckT: 0, revT: 0, revSteer: 1, waitT: 0, ignoreT: 0, panicT: 0, shootT: 1, hitByPlayerT: -99, wasDirect: false };
  if (type === 'cop') {
    c.mR = new THREE.MeshBasicMaterial({ color: 0x550000 }); c.mB = new THREE.MeshBasicMaterial({ color: 0x000055 });
    const r = new THREE.Mesh(carGeoBar, c.mR), b = new THREE.Mesh(carGeoBar, c.mB), ty = K.top * KS + 0.08;
    r.position.set(-0.3, ty, -0.1); b.position.set(0.3, ty, -0.1); g.add(r, b);
  }
  scene.add(g); cars.push(c);
  return c;
}
const carGeoBar = new THREE.BoxGeometry(0.55, 0.18, 0.36), carGeoFire = new THREE.IcosahedronGeometry(0.75, 0);
function removeCar(c) { scene.remove(c.g); const i = cars.indexOf(c); if (i >= 0) cars.splice(i, 1); }
function snapRoute(c) {
  if (OSMG) return osmSnap(c);
  const i = Math.round(c.x / P), j = Math.round(c.z / P), fx = Math.sin(c.h), fz = Math.cos(c.h);
  const onH = Math.abs(c.z - j * P) < R / 2 + 3, onV = Math.abs(c.x - i * P) < R / 2 + 3;
  if (onH && (!onV || Math.abs(fx) > Math.abs(fz))) { c.d = fx >= 0 ? 0 : 2; c.ti = fx >= 0 ? Math.floor(c.x / P) + 1 : Math.ceil(c.x / P) - 1; c.tj = j; }
  else if (onV) { c.d = fz >= 0 ? 1 : 3; c.tj = fz >= 0 ? Math.floor(c.z / P) + 1 : Math.ceil(c.z / P) - 1; c.ti = i; }
  else { c.ti = i; c.tj = j; const dx = i * P - c.x, dz = j * P - c.z; c.d = Math.abs(dx) > Math.abs(dz) ? (dx > 0 ? 0 : 2) : (dz > 0 ? 1 : 3); }
  c.ti = clamp(c.ti, 0, N); c.tj = clamp(c.tj, 0, N);
}
function advanceNode(c, chase) {
  if (OSMG) return osmAdvance(c, chase);
  const opts = [];
  for (let nd = 0; nd < 4; nd++) { if (nd === (c.d + 2) % 4) continue; const ni = c.ti + DX[nd], nj = c.tj + DZ[nd]; if (ni >= 0 && nj >= 0 && ni <= N && nj <= N) opts.push(nd); }
  if (!opts.length) opts.push((c.d + 2) % 4);
  let nd;
  if (chase) { let bd = 1e9; for (const o of opts) { const d = Math.hypot((c.ti + DX[o]) * P - player.x, (c.tj + DZ[o]) * P - player.z); if (d < bd) { bd = d; nd = o; } } }
  else nd = opts.includes(c.d) && Math.random() < 0.55 ? c.d : pick(opts);
  c.d = nd; c.ti += DX[nd]; c.tj += DZ[nd];
}
function spawnRoadCar(type, mode, minD, maxD, behind = false) {
  if (OSMG) {
    for (let k = 0; k < 40; k++) {
      const sp = osmRoadSpot(player.x, player.z, minD, maxD, 'lane'); if (!sp) continue;
      if (behind && k < 25 && ((sp.x - player.x) * Math.sin(camYaw) + (sp.z - player.z) * Math.cos(camYaw)) > 0) continue;
      if (cars.some(o => Math.abs(o.x - sp.x) < 8 && Math.abs(o.z - sp.z) < 8)) continue;
      const c = makeCar(type, pick(CAR_COL)); Object.assign(c, { x: sp.x, z: sp.z, h: Math.atan2(sp.dx, sp.dz), rp: sp.dirS > 0 ? sp.e.a : sp.e.b, rn: sp.dirS > 0 ? sp.e.b : sp.e.a, driver: 'ai', mode });
      c.vx = Math.sin(c.h) * 8; c.vz = Math.cos(c.h) * 8; return c;
    }
    return null;
  }
  for (let tries = 0; tries < 60; tries++) {
    const i = Math.random() * (N + 1) | 0, j = Math.random() * (N + 1) | 0, d = Math.random() * 4 | 0;
    const ni = i + DX[d], nj = j + DZ[d];
    if (ni < 0 || nj < 0 || ni > N || nj > N) continue;
    const t = 12 + Math.random() * (P - 24);
    const x = i * P + DX[d] * t - DZ[d] * LANE, z = j * P + DZ[d] * t + DX[d] * LANE;
    const pd = Math.hypot(x - player.x, z - player.z);
    if (pd < minD || pd > maxD) continue;
    if (behind && tries < 40 && ((x - player.x) * Math.sin(camYaw) + (z - player.z) * Math.cos(camYaw)) > 0) continue;
    if (cars.some(o => Math.abs(o.x - x) < 8 && Math.abs(o.z - z) < 8)) continue;
    const c = makeCar(type, pick(CAR_COL));
    Object.assign(c, { x, z, h: Math.atan2(DX[d], DZ[d]), ti: ni, tj: nj, d, driver: 'ai', mode });
    c.vx = Math.sin(c.h) * 8; c.vz = Math.cos(c.h) * 8;
    return c;
  }
  return null;
}

// ================= peds =================
const peds = [];
function osmPerim(pd) {
  const G = OSMG; let e = G.edges[pd.e]; if (!e) { pd.e = 0; e = G.edges[0]; pd.s = 0; }
  if (pd.s > e.len || pd.s < 0) {
    const node = pd.s > e.len ? e.b : e.a, opts = G.adj[node].filter(i => i !== pd.e), ni = opts.length ? opts[Math.random() * opts.length | 0] : pd.e, e2 = G.edges[ni];
    pd.e = ni; if (e2.a === node) { pd.s = 0; pd.dir = 1; } else { pd.s = e2.len; pd.dir = -1; } e = e2;
  }
  const a = G.nodes[e.a], hw = e.w / 2 + 1.5 + (pd.off || 0) * 0.5, side = pd.side || 1, sc = clamp(pd.s, 0, e.len);
  return [a.x + e.dx * sc - e.dz * side * hw, a.z + e.dz * sc + e.dx * side * hw, e.dx * pd.dir, e.dz * pd.dir];
}
function perim(pd) {
  if (OSMG) return osmPerim(pd);
  const b = blocks[pd.b], x0 = b.x0 + 2.3, z0 = b.z0 + 2.3, L = B - 4.6;
  const s = ((pd.s % (4 * L)) + 4 * L) % (4 * L), side = Math.floor(s / L), u = s - side * L;
  let x, z, dx, dz, nx, nz;
  if (side === 0) { x = x0 + u; z = z0; dx = 1; dz = 0; nx = 0; nz = -1; }
  else if (side === 1) { x = x0 + L; z = z0 + u; dx = 0; dz = 1; nx = 1; nz = 0; }
  else if (side === 2) { x = x0 + L - u; z = z0 + L; dx = -1; dz = 0; nx = 0; nz = 1; }
  else { x = x0; z = z0 + L - u; dx = 0; dz = -1; nx = -1; nz = 0; }
  return [x + nx * pd.off, z + nz * pd.off, dx * pd.dir, dz * pd.dir];
}
function placePedNear(pd, x, z) {
  if (OSMG) { const n = osmNearest(x, z, 200); if (n) { pd.e = n.e; pd.s = n.t; pd.side = Math.random() < 0.5 ? 1 : -1; } return; }
  const bi = clamp(Math.floor(x / P), 0, N - 1), bj = clamp(Math.floor(z / P), 0, N - 1);
  pd.b = bi * N + bj;
  const b = blocks[pd.b], x0 = b.x0 + 2.3, z0 = b.z0 + 2.3, L = B - 4.6;
  const c = [[0, clamp(x - x0, 0, L), Math.abs(z - z0)], [1, clamp(z - z0, 0, L), Math.abs(x - x0 - L)], [2, clamp(x0 + L - x, 0, L), Math.abs(z - z0 - L)], [3, clamp(z0 + L - z, 0, L), Math.abs(x - x0)]];
  c.sort((a, b) => a[2] - b[2]);
  pd.s = c[0][0] * L + c[0][1];
}
function respawnPed(pd, far = true) {
  if (OSMG) { for (let t = 0; t < 30; t++) { pd.e = Math.random() * OSMG.edges.length | 0; pd.s = Math.random() * OSMG.edges[pd.e].len; pd.side = Math.random() < 0.5 ? 1 : -1; const [x, z] = osmPerim(pd), d = Math.hypot(x - player.x, z - player.z); if (!far || (d > 70 && d < 220)) break; } pd.state = 'walk'; pd.t = 0; pd.p.g.rotation.set(0, 0, 0); return; }
  for (let t = 0; t < 30; t++) {
    pd.b = Math.random() * blocks.length | 0; pd.s = Math.random() * 1000;
    const [x, z] = perim(pd);
    const d = Math.hypot(x - player.x, z - player.z);
    if (!far || (d > 70 && d < 220)) break;
  }
  pd.state = 'walk'; pd.t = 0; pd.p.g.rotation.set(0, 0, 0);
}
function killPed(pd, vx, vz, byPlayer, vehicle) {
  if (pd.state === 'dead') return;
  pd.state = 'dead'; pd.t = 0; pd.vx = vx; pd.vz = vz; pd.vy = vehicle ? 5 : 1.5;
  scare(pd.x, pd.z, 25);
  sfx.noise(0.12, 0.35, 700);
  if (byPlayer) crime(4);
}
function scare(x, z, r) { for (const p of peds) if (p.state === 'walk' && Math.hypot(p.x - x, p.z - z) < r) { p.state = 'flee'; p.t = 6 + Math.random() * 3; if (Math.random() < 0.5) p.dir *= -1; } }

// ================= player & state =================
const player = { x: 4 * P - R / 2 - 2.5, z: 4 * P - R / 2 - 2.5, y: 0.25, h: 0, kx: 0, kz: 0, hp: 100, car: null, dead: false, hitCd: 0, fireCd: 0, aimT: 0, bustT: 0 };
player.p = makePerson('#f7f7f7', '#2f4b7c', '#e0ac82', '#1b1b1b', true);
let money = 500; try { money = +localStorage.getItem('ulsan_money') || 500; } catch (e) { }
let heat = 0, stars = 0, unseenT = 0, copSpawnT = 0, deadT = 0, deadKind = '', time = 0, shake = 0;
let state = 'menu', camYaw = 0.7, dragYaw = 0, maintT = 0;
const HOSPITAL = OSMW ? OSMW.hosp : { x: 1 * P + R / 2 + 2.5, z: (N - 1) * P + R / 2 + 2.5 };
const STATION = OSMW ? OSMW.station : { x: (N - 1) * P + R / 2 + 2.5, z: 1 * P + R / 2 + 2.5 };

function crime(n) {
  heat += n; unseenT = 0;
  const ns = TH.filter(t => heat >= t).length;
  if (ns > stars) { stars = ns; $('stars').classList.remove('pop'); void $('stars').offsetWidth; $('stars').classList.add('pop'); }
}
function damage(n) {
  if (player.dead) return;
  player.hp -= n; $('hurt').style.opacity = 0.6;
  if (player.hp <= 0) endLife('wasted');
}
function endLife(kind) {
  if (player.dead) return;
  player.dead = true; deadT = 3.4; deadKind = kind;
  if (player.car) { player.car.driver = null; player.car = null; }
  if (kind === 'wasted') { player.p.g.rotation.x = -Math.PI / 2; money -= Math.min(money, 200); }
  else money -= Math.min(money, 300);
  showMsg(kind === 'busted' ? 'BUSTED' : 'WASTED', kind === 'busted' ? '체포됐어요 · 벌금 $300' : '병원으로 이송 · 병원비 $200', kind);
  heat = 0; stars = 0;
  for (const c of cars) if (c.mode === 'chase') { c.mode = 'traffic'; snapRoute(c); }
  if (mission.stage === 'deliver') { mission.stage = 'none'; mission.t = 2; }
}
function respawn() {
  const s = deadKind === 'busted' ? STATION : HOSPITAL;
  player.x = s.x; player.z = s.z; player.hp = 100; player.dead = false; player.kx = player.kz = 0; player.bustT = 0;
  player.p.g.rotation.set(0, 0, 0);
  $('msg').className = 'hud';
  for (const c of [...cars]) if (c.type === 'cop' && Math.hypot(c.x - s.x, c.z - s.z) < 60 && c.driver === 'ai') removeCar(c);
}

// ================= input =================
const keys = {}, input = { mx: 0, my: 0, sprint: false, fire: false, hb: false, enterQ: false };
let touchFire = false, touchHB = false;
addEventListener('keydown', e => {
  if (e.repeat) { if (['Space', 'ArrowUp', 'ArrowDown'].includes(e.code)) e.preventDefault(); return; }
  keys[e.code] = true;
  if ((e.code === 'KeyE' || e.code === 'KeyF') && state === 'play') input.enterQ = true;
  if (e.code === 'Enter' && state === 'menu') startGame();
  if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
});
addEventListener('keyup', e => { keys[e.code] = false; });
addEventListener('blur', () => { for (const k in keys) keys[k] = false; });
const joy = { id: null, ox: 0, oy: 0, mx: 0, my: 0 }, drag = { id: null, lx: 0 };
const JR = 56;
addEventListener('pointerdown', e => {
  if (state !== 'play' || e.target.closest('.btn,#start')) return;
  if (e.pointerType !== 'mouse' && e.clientX < innerWidth * 0.5 && joy.id === null) {
    joy.id = e.pointerId; joy.ox = e.clientX; joy.oy = e.clientY;
    const j = $('joy'); j.style.left = e.clientX + 'px'; j.style.top = e.clientY + 'px'; j.classList.add('on');
  } else if (drag.id === null) { drag.id = e.pointerId; drag.lx = e.clientX; }
});
addEventListener('pointermove', e => {
  if (e.pointerId === joy.id) {
    let dx = e.clientX - joy.ox, dy = e.clientY - joy.oy; const l = Math.hypot(dx, dy);
    if (l > JR) { dx *= JR / l; dy *= JR / l; }
    $('knob').style.transform = `translate(${dx}px,${dy}px)`;
    joy.mx = dx / JR; joy.my = -dy / JR;
  } else if (e.pointerId === drag.id) { dragYaw -= (e.clientX - drag.lx) * 0.006; drag.lx = e.clientX; }
});
const endPtr = e => {
  if (e.pointerId === joy.id) { joy.id = null; joy.mx = joy.my = 0; $('joy').classList.remove('on'); $('knob').style.transform = ''; }
  if (e.pointerId === drag.id) drag.id = null;
};
addEventListener('pointerup', endPtr); addEventListener('pointercancel', endPtr);
function bindBtn(el, down, up) {
  el.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); try { el.setPointerCapture(e.pointerId); } catch (_) { } el.classList.add('on'); down(); });
  const end = () => { el.classList.remove('on'); up && up(); };
  el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end); el.addEventListener('lostpointercapture', end);
}
bindBtn($('bFire'), () => touchFire = true, () => touchFire = false);
bindBtn($('bEnter'), () => input.enterQ = true);
bindBtn($('bHB'), () => touchHB = true, () => touchHB = false);
addEventListener('contextmenu', e => e.preventDefault());
function readInput() {
  const k = c => keys[c] ? 1 : 0;
  let mx = (k('KeyD') || k('ArrowRight')) - (k('KeyA') || k('ArrowLeft'));
  let my = (k('KeyW') || k('ArrowUp')) - (k('KeyS') || k('ArrowDown'));
  if (joy.id !== null) { mx = Math.abs(joy.mx) > 0.12 ? joy.mx : 0; my = Math.abs(joy.my) > 0.12 ? joy.my : 0; }
  input.mx = mx; input.my = my;
  input.sprint = !!(keys.ShiftLeft || keys.ShiftRight);
  input.fire = touchFire || (!player.car && !!keys.Space) || !!keys.KeyJ;
  input.hb = touchHB || (!!player.car && !!keys.Space);
}

// ================= audio =================
const sfx = (() => {
  let AC = null, master, eng, engG, siren, sirenG, noiseBuf, sirenPhase = 0, rainG, windG;
  return {
    init() {
      if (AC) return;
      try {
        AC = new (window.AudioContext || window.webkitAudioContext)();
        master = AC.createGain(); master.gain.value = 0.55; master.connect(AC.destination);
        eng = AC.createOscillator(); eng.type = 'sawtooth'; const lp = AC.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 380;
        engG = AC.createGain(); engG.gain.value = 0; eng.connect(lp).connect(engG).connect(master); eng.start();
        siren = AC.createOscillator(); siren.type = 'square'; sirenG = AC.createGain(); sirenG.gain.value = 0;
        const sl = AC.createBiquadFilter(); sl.type = 'lowpass'; sl.frequency.value = 1800; siren.connect(sl).connect(sirenG).connect(master); siren.start();
        noiseBuf = AC.createBuffer(1, AC.sampleRate, AC.sampleRate); const d = noiseBuf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
        const rs = AC.createBufferSource(); rs.buffer = noiseBuf; rs.loop = true; const hp = AC.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 1500; rainG = AC.createGain(); rainG.gain.value = 0; rs.connect(hp).connect(rainG).connect(master); rs.start();
        const ws = AC.createBufferSource(); ws.buffer = noiseBuf; ws.loop = true; ws.playbackRate.value = 0.6; const wl = AC.createBiquadFilter(); wl.type = 'lowpass'; wl.frequency.value = 420; windG = AC.createGain(); windG.gain.value = 0; ws.connect(wl).connect(windG).connect(master); ws.start();
      } catch (e) { AC = null; }
    },
    weather(rain, wind, snow) { if (!AC) return; const t = AC.currentTime; rainG.gain.setTargetAtTime(rain * 0.07, t, 0.5); windG.gain.setTargetAtTime(0.012 + wind * 0.05 + snow * 0.01, t, 0.8); },
    thunder() { this.noise(2.4, 0.6, 160); this.noise(0.9, 0.35, 700); },
    noise(dur, vol, freq) {
      if (!AC || vol < 0.01) return;
      const s = AC.createBufferSource(); s.buffer = noiseBuf; const f = AC.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = freq;
      const g = AC.createGain(), t = AC.currentTime; g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      s.connect(f).connect(g).connect(master); s.start(t); s.stop(t + dur + 0.05);
    },
    frame(engine, speed, thr, sirenVol, dt) {
      if (!AC) return;
      const t = AC.currentTime;
      eng.frequency.setTargetAtTime(42 + speed * 3.6 + Math.max(0, thr) * 18, t, 0.08);
      engG.gain.setTargetAtTime(engine ? 0.07 : 0, t, 0.1);
      sirenPhase += dt;
      siren.frequency.setTargetAtTime((sirenPhase % 0.9) < 0.45 ? 720 : 960, t, 0.03);
      sirenG.gain.setTargetAtTime(sirenVol, t, 0.15);
    }
  };
})();

// ================= fx =================
const tracers = [], flashes = [];
for (let i = 0; i < 12; i++) {
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(6), 3));
  const l = new THREE.Line(g, new THREE.LineBasicMaterial({ color: 0xfff1a0, transparent: true })); l.visible = false; l.frustumCulled = false; scene.add(l); tracers.push({ l, t: 0 });
}
for (let i = 0; i < 6; i++) {
  const m = new THREE.Mesh(new THREE.IcosahedronGeometry(1, 1), new THREE.MeshBasicMaterial({ color: 0xffa040, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
  m.visible = false; scene.add(m); flashes.push({ m, t: 0, s: 1, life: 1 });
}
function tracer(x1, y1, z1, x2, y2, z2) {
  const tr = tracers.find(t => t.t <= 0) || tracers[0];
  const a = tr.l.geometry.attributes.position; a.setXYZ(0, x1, y1, z1); a.setXYZ(1, x2, y2, z2); a.needsUpdate = true;
  tr.t = 0.07; tr.l.visible = true;
}
function flash(x, y, z, size, life) {
  const f = flashes.find(t => t.t <= 0) || flashes[0];
  f.m.position.set(x, y, z); f.t = life; f.life = life; f.s = size; f.m.visible = true;
}
const marker = new THREE.Group();
{
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(2.2, 2.2, 60, 24, 1, true), new THREE.MeshBasicMaterial({ color: 0xffd23f, transparent: true, opacity: 0.25, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, fog: false }));
  beam.position.y = 30;
  const ring = new THREE.Mesh(new THREE.TorusGeometry(2.4, 0.16, 8, 40).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffd23f }));
  ring.position.y = 0.35;
  const arrow = new THREE.Mesh(new THREE.ConeGeometry(0.8, 1.6, 4).rotateX(Math.PI), new THREE.MeshBasicMaterial({ color: 0xffd23f }));
  marker.add(beam, ring, arrow); marker.userData = { beam, ring, arrow };
  scene.add(marker);
}

// ================= mission =================
const mission = { stage: 'none', x: 0, z: 0, t: 1.5, reward: 0 };
function roadPoint(minD, maxD) {
  if (OSMG) { const sp = osmRoadSpot(player.x, player.z, minD, maxD, 'walk'); return sp ? { x: sp.x, z: sp.z, d: sp.d } : { x: player.x + 30, z: player.z, d: 30 }; }
  for (let k = 0; k < 80; k++) {
    const i = Math.random() * (N + 1) | 0, j = Math.random() * (N + 1) | 0, d = Math.random() * 4 | 0;
    const ni = i + DX[d], nj = j + DZ[d]; if (ni < 0 || nj < 0 || ni > N || nj > N) continue;
    const t = 15 + Math.random() * (P - 30), side = Math.random() < 0.5 ? 1 : -1;
    const x = i * P + DX[d] * t - DZ[d] * 5.6 * side, z = j * P + DZ[d] * t + DX[d] * 5.6 * side;
    const dd = Math.hypot(x - player.x, z - player.z);
    if (dd >= minD && dd <= maxD) return { x, z, d: dd };
  }
  return { x: player.x + 30, z: player.z, d: 30 };
}
function updateMission(dt) {
  if (mission.stage === 'none') { mission.t -= dt; if (mission.t <= 0) { const p = roadPoint(40, 170); Object.assign(mission, p, { stage: 'pickup' }); } }
  else {
    const d = Math.hypot(player.x - mission.x, player.z - mission.z);
    if (mission.stage === 'deliver') { mission.t -= dt; if (mission.t <= 0) { toast('배달 실패! 시간 초과'); mission.stage = 'none'; mission.t = 3; } }
    if (d < 4.5 && !player.dead) {
      if (mission.stage === 'pickup') {
        const p = roadPoint(200, 420);
        Object.assign(mission, p, { stage: 'deliver', t: Math.round(p.d / 9 + 25), reward: Math.round((150 + p.d * 1.6) / 10) * 10 });
        toast('택배 픽업! 제한시간 안에 배달하세요'); sfx.noise(0.08, 0.2, 3000);
      } else {
        const bonus = Math.round(mission.t) * 5;
        money += mission.reward + bonus; toast(`배달 완료 +$${mission.reward + bonus}`, true);
        mission.stage = 'none'; mission.t = 2.5;
      }
    }
  }
  marker.visible = mission.stage !== 'none';
  if (marker.visible) {
    const col = mission.stage === 'pickup' ? 0x52e0ff : 0xffd23f, u = marker.userData;
    u.beam.material.color.setHex(col); u.ring.material.color.setHex(col); u.arrow.material.color.setHex(col);
    marker.position.set(mission.x, groundY(mission.x, mission.z), mission.z);
    u.arrow.position.y = 3.2 + Math.sin(time * 3) * 0.4; u.arrow.rotation.y = time * 2;
  }
}

// ================= gameplay =================
function nearestCar(r) {
  let best = null, bd = r;
  for (const c of cars) { if (c.wreck || c.burning) continue; const d = Math.hypot(c.x - player.x, c.z - player.z); if (d < bd) { bd = d; best = c; } }
  return best;
}
function ejectDriver(c) {
  const pd = peds.find(p => p.state === 'dead') || peds.reduce((a, b) => Math.hypot(a.x - player.x, a.z - player.z) > Math.hypot(b.x - player.x, b.z - player.z) ? a : b);
  pd.p.g.rotation.set(0, 0, 0); placePedNear(pd, c.x, c.z); pd.state = 'flee'; pd.t = 10;
}
function tryEnter() {
  const c = nearestCar(4.2); if (!c) return;
  if (c.driver === 'ai') {
    ejectDriver(c);
    crime(c.type === 'cop' ? 12 : cars.some(o => o.type === 'cop' && o !== c && Math.hypot(o.x - c.x, o.z - c.z) < 45) ? 4 : 1);
    toast(c.type === 'cop' ? '경찰차 탈취!' : '차량 탈취!');
  }
  c.driver = 'player'; c.mode = null; player.car = c; c.hitByPlayerT = time;
}
function exitCar() {
  const c = player.car, sp = Math.hypot(c.vx, c.vz);
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  let ox = fz * 2.4, oz = -fx * 2.4;
  if (pushOut(c.x + ox, c.z + oz, 0.5)) { ox = -ox; oz = -oz; }
  player.x = c.x + ox; player.z = c.z + oz; player.h = c.h;
  player.car = null; c.driver = null;
  if (sp > 9) { damage(sp * 1.2); player.kx = c.vx * 0.5; player.kz = c.vz * 0.5; }
}
function shoot() {
  player.fireCd = 0.26; player.aimT = 0.4;
  let best = null, bs = 1e9, isPed = false;
  const consider = (x, z, o, ped) => {
    const dx = x - player.x, dz = z - player.z, d = Math.hypot(dx, dz);
    if (d > 32 || d < 0.3) return;
    const ang = Math.abs(wrapA(Math.atan2(dx, dz) - player.h)); if (ang > 0.55) return;
    const s = d + ang * 28; if (s < bs) { bs = s; best = o; isPed = ped; }
  };
  for (const p of peds) if (p.state !== 'dead') consider(p.x, p.z, p, true);
  for (const c of cars) if (!c.wreck) consider(c.x, c.z, c, false);
  const fx = Math.sin(player.h), fz = Math.cos(player.h);
  if (best) player.h = Math.atan2(best.x - player.x, best.z - player.z);
  const hx = Math.sin(player.h), hz = Math.cos(player.h);
  const gx = player.x + hx * 0.75 + hz * 0.4, gz = player.z + hz * 0.75 - hx * 0.4, gy = player.y + 1.5;
  if (best) {
    tracer(gx, gy, gz, best.x, (best.y || 0) + (isPed ? 1.3 : 1), best.z);
    if (isPed) { const d = Math.hypot(best.x - player.x, best.z - player.z) || 1; killPed(best, (best.x - player.x) / d * 3, (best.z - player.z) / d * 3, true, false); }
    else { best.health -= 14; best.hitByPlayerT = time; best.panicT = 6; if (best.type === 'cop') crime(5); }
  } else tracer(gx, gy, gz, player.x + fx * 32, gy, player.z + fz * 32);
  flash(gx, gy, gz, 0.35, 0.06);
  sfx.noise(0.16, 0.6, 2600); scare(player.x, player.z, 40);
  if (cars.some(c => c.type === 'cop' && !c.wreck && Math.hypot(c.x - player.x, c.z - player.z) < 40)) crime(2);
}
function explode(c) {
  c.wreck = true; c.burning = false; c.fire.visible = false; if (c.bodyMesh) c.bodyMesh.material = wreckMat; c.cabin.material = wreckMat; c.glass.material = wreckMat; c.driverM.visible = false; c.head.visible = c.tail.visible = false; c.wreckT = 0;
  const byP = time - c.hitByPlayerT < 12;
  if (c.driver === 'player') { player.car = null; c.driver = null; damage(999); }
  c.driver = null; c.vx *= 0.2; c.vz *= 0.2;
  flash(c.x, 1.5, c.z, 7, 0.6);
  const dPl = Math.hypot(c.x - player.x, c.z - player.z);
  sfx.noise(1.3, clamp(1 - dPl / 160, 0, 1), 420); shake = Math.max(shake, clamp(1.6 - dPl / 40, 0, 1.6));
  if (c.type === 'cop' && byP) crime(12);
  for (const p of peds) { const d = Math.hypot(p.x - c.x, p.z - c.z); if (d < 7) killPed(p, (p.x - c.x) / (d || 1) * 8, (p.z - c.z) / (d || 1) * 8, byP, true); }
  for (const o of cars) { if (o === c || o.wreck) continue; const d = Math.hypot(o.x - c.x, o.z - c.z); if (d < 8) { o.health -= (8 - d) * 16; o.vx += (o.x - c.x) / (d || 1) * 6; o.vz += (o.z - c.z) / (d || 1) * 6; if (byP) o.hitByPlayerT = time; } }
  if (!player.car && dPl < 7) { damage((7 - dPl) * 15); player.kx = (player.x - c.x) / (dPl || 1) * 10; player.kz = (player.z - c.z) / (dPl || 1) * 10; }
}
function hitCar(c, impact) {
  if (impact < 3.5 || c.wreck) return;
  c.health -= (impact - 3) * 2.6;
  const d = Math.hypot(c.x - player.x, c.z - player.z);
  if (d < 60) sfx.noise(0.22, clamp(impact / 25, 0, 0.7) * (1 - d / 60), 900);
  if (c.driver === 'player') shake = Math.max(shake, clamp(impact / 25, 0, 0.8));
}

function updatePlayer(dt) {
  player.hitCd -= dt; player.fireCd -= dt; player.aimT -= dt;
  if (player.dead) { deadT -= dt; if (deadT <= 0) respawn(); input.enterQ = false; return; }
  if (input.enterQ) { input.enterQ = false; if (player.car) exitCar(); else tryEnter(); }
  if (player.car) {
    const c = player.car; c.throttle = input.my; c.steerIn = input.mx; c.hb = input.hb;
    player.x = c.x; player.z = c.z; player.y = c.y;
    return;
  }
  const fx = Math.sin(camYaw), fz = Math.cos(camYaw);
  let dx = fx * input.my - fz * input.mx, dz = fz * input.my + fx * input.mx, m = Math.hypot(dx, dz), sp = 0;
  if (m > 0.12) { dx /= m; dz /= m; sp = (input.sprint ? 10 : 7.2) * Math.min(1, m); if (player.aimT <= 0) player.h = lerpA(player.h, Math.atan2(dx, dz), 1 - Math.exp(-14 * dt)); }
  player.x += (dx * sp + player.kx) * dt; player.z += (dz * sp + player.kz) * dt;
  player.kx *= Math.exp(-5 * dt); player.kz *= Math.exp(-5 * dt);
  const p = pushOut(player.x, player.z, 0.45); if (p) { player.x += p.x; player.z += p.z; }
  player.x = clamp(player.x, MINB, MAXB); player.z = clamp(player.z, MINB, MAXB);
  player.y += (groundY(player.x, player.z) - player.y) * Math.min(1, dt * 15);
  animLegs(player.p, sp, dt);
  player.p.armR.rotation.x = player.aimT > 0 ? -Math.PI / 2 : -Math.sin(player.p.phase) * 0.6 * Math.min(1, sp / 2);
  if (player.aimT > 0) player.p.fR.rotation.x = -0.05;
  if (input.fire && player.fireCd <= 0) shoot();
}

function routeNode(c) { // 목표 노드 위치 + 진행 방향
  if (OSMG) { const a = OSMG.nodes[c.rp], b = OSMG.nodes[c.rn], dx = b.x - a.x, dz = b.z - a.z, l = Math.hypot(dx, dz) || 1; return [b.x, b.z, dx / l, dz / l]; }
  return [c.ti * P, c.tj * P, DX[c.d], DZ[c.d]];
}
function carAI(c, dt) {
  if (c.wreck) return;
  if (c.driver !== 'ai') { if (!c.driver) { c.throttle = 0; c.steerIn = 0; c.hb = false; } return; }
  if (c.health <= 0) { c.driver = null; ejectDriver(c); return; }
  c.panicT -= dt; c.ignoreT -= dt;
  const sp = Math.hypot(c.vx, c.vz);
  if (c.revT > 0) { c.revT -= dt; c.throttle = -0.9; c.steerIn = -c.revSteer; c.hb = false; if (c.revT <= 0) snapRoute(c); return; }
  const chase = c.mode === 'chase';
  const pd = Math.hypot(player.x - c.x, player.z - c.z);
  const direct = chase && pd < 34 && !player.dead;
  let tx, tz;
  if (direct) {
    const pc = player.car; tx = player.x + (pc ? pc.vx * 0.45 : 0); tz = player.z + (pc ? pc.vz * 0.45 : 0); c.wasDirect = true;
  } else {
    if (c.wasDirect) { c.wasDirect = false; snapRoute(c); }
    let [nxp, nzp, rdx, rdz] = routeNode(c), along = (nxp - c.x) * rdx + (nzp - c.z) * rdz;
    if (along < (chase ? 9 : 7)) { advanceNode(c, chase); [nxp, nzp, rdx, rdz] = routeNode(c); along = (nxp - c.x) * rdx + (nzp - c.z) * rdz; }
    const off = chase ? 1.6 : (OSMG ? 2.3 : LANE);
    const lx = nxp - rdz * off, lz = nzp + rdx * off, t = (c.x - lx) * rdx + (c.z - lz) * rdz;
    tx = lx + rdx * (t + 9); tz = lz + rdz * (t + 9);
  }
  const diff = wrapA(Math.atan2(tx - c.x, tz - c.z) - c.h);
  c.steerIn = clamp(-diff * 2.3, -1, 1);
  let vt = chase ? (direct ? (player.car ? 30 : clamp(pd - 6, 0, 16)) : 27) : (c.panicT > 0 ? 24 : 11);
  if (Math.abs(diff) > 0.45) vt = Math.min(vt, chase ? 13 : 6);
  if (!chase && c.ignoreT <= 0) {
    const fx = Math.sin(c.h), fz = Math.cos(c.h);
    let blocked = false;
    const check = (x, z, w) => { const rx = x - c.x, rz = z - c.z, f = rx * fx + rz * fz, l = rx * -fz + rz * fx; if (f > 0 && f < 12 && Math.abs(l) < w) { vt = Math.min(vt, f < 6.5 ? 0 : 4); blocked = true; } };
    for (const o of cars) if (o !== c && Math.abs(o.x - c.x) < 13 && Math.abs(o.z - c.z) < 13) check(o.x, o.z, 2.3);
    if (!player.car) check(player.x, player.z, 1.6);
    if (blocked && sp < 1) { c.waitT += dt; if (c.waitT > 4) { c.ignoreT = 2; c.waitT = 0; } } else c.waitT = 0;
  }
  c.throttle = clamp((vt - c.vF) * 0.4, -1, 1); c.hb = false;
  if (c.throttle > 0.3 && sp < 0.7) c.stuckT += dt; else c.stuckT = Math.max(0, c.stuckT - dt * 0.5);
  if (c.stuckT > (chase ? 1.1 : 2.5)) { c.stuckT = 0; c.revT = 1.1; c.revSteer = c.steerIn >= 0 ? 1 : -1; }
}

function integrateCar(c, dt) {
  if (c.wreck) { const k = Math.exp(-3 * dt); c.vx *= k; c.vz *= k; c.x += c.vx * dt; c.z += c.vz * dt; return; }
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  let vF = c.vx * fx + c.vz * fz, vL = c.vx * -fz + c.vz * fx;
  const drv = !!c.driver, thr = drv ? c.throttle : 0, hb = drv && c.hb;
  c.steer += ((drv ? clamp(c.steerIn, -1, 1) : 0) - c.steer) * Math.min(1, dt * (c.driver === 'player' ? 7 : 5));
  const maxF = c.type === 'cop' ? 31 : (c.driver === 'player' ? 34 : 25);
  if (thr > 0.02) vF += (vF < -0.5 ? 24 : (c.driver === 'player' ? 16 : 13.5) * (1 - Math.max(0, vF) / maxF)) * thr * dt;
  else if (thr < -0.02) vF += (vF > 0.5 ? 24 : 8 * (1 - Math.max(0, -vF) / 11)) * thr * dt;
  else { const roll = (drv ? 2 : 3.5) * dt; vF = Math.abs(vF) < roll ? 0 : vF - Math.sign(vF) * roll; }
  vF -= vF * 0.1 * dt;
  if (hb) vF -= vF * 0.9 * dt;
  const sf = clamp(vF / 5, -1, 1) * (1 - Math.min(Math.abs(vF) / 70, 0.45));
  c.h -= c.steer * 2.3 * sf * dt * (hb ? 1.55 : 1);
  vL *= Math.exp(-(hb ? 0.9 : 7.5) * dt);
  const nx = Math.sin(c.h), nz = Math.cos(c.h);
  c.vx = nx * vF - nz * vL; c.vz = nz * vF + nx * vL;
  c.x += c.vx * dt; c.z += c.vz * dt; c.vF = vF; c.vL = vL;
}
function carWorld(c) {
  const fx = Math.sin(c.h), fz = Math.cos(c.h);
  for (const o of [1.25, -1.25]) {
    const p = pushOut(c.x + fx * o, c.z + fz * o, 1.05);
    if (!p) continue;
    c.x += p.x; c.z += p.z;
    const l = Math.hypot(p.x, p.z) || 1, nx = p.x / l, nz = p.z / l, vn = c.vx * nx + c.vz * nz;
    if (vn < 0) { c.vx -= nx * vn * 1.3; c.vz -= nz * vn * 1.3; c.vx *= 0.93; c.vz *= 0.93; hitCar(c, -vn); }
  }
  if (c.x < MINB) { c.x = MINB; hitCar(c, Math.abs(c.vx)); c.vx = Math.abs(c.vx) * 0.3; }
  if (c.x > MAXB) { c.x = MAXB; hitCar(c, Math.abs(c.vx)); c.vx = -Math.abs(c.vx) * 0.3; }
  if (c.z < MINB) { c.z = MINB; hitCar(c, Math.abs(c.vz)); c.vz = Math.abs(c.vz) * 0.3; }
  if (c.z > MAXB) { c.z = MAXB; hitCar(c, Math.abs(c.vz)); c.vz = -Math.abs(c.vz) * 0.3; }
}
function carCar() {
  for (let i = 0; i < cars.length; i++) for (let j = i + 1; j < cars.length; j++) {
    const a = cars[i], b = cars[j];
    if (Math.abs(a.x - b.x) > 6.5 || Math.abs(a.z - b.z) > 6.5) continue;
    const afx = Math.sin(a.h), afz = Math.cos(a.h), bfx = Math.sin(b.h), bfz = Math.cos(b.h);
    for (const oa of [1.25, -1.25]) for (const ob of [1.25, -1.25]) {
      const ax = a.x + afx * oa, az = a.z + afz * oa, bx = b.x + bfx * ob, bz = b.z + bfz * ob;
      const dx = bx - ax, dz = bz - az, d2 = dx * dx + dz * dz;
      if (d2 >= 4.41 || d2 < 1e-6) continue;
      const d = Math.sqrt(d2), nx = dx / d, nz = dz / d, pen = 2.1 - d;
      a.x -= nx * pen / 2; a.z -= nz * pen / 2; b.x += nx * pen / 2; b.z += nz * pen / 2;
      const vrel = (b.vx - a.vx) * nx + (b.vz - a.vz) * nz;
      if (vrel < 0) {
        const jj = -1.3 * vrel / 2; a.vx -= nx * jj; a.vz -= nz * jj; b.vx += nx * jj; b.vz += nz * jj;
        hitCar(a, -vrel * 0.8); hitCar(b, -vrel * 0.8);
        for (const [p, q] of [[a, b], [b, a]]) if (p.driver === 'player') { q.hitByPlayerT = time; if (q.type === 'cop' && -vrel > 5 && Math.hypot(p.vx, p.vz) > Math.hypot(q.vx, q.vz)) crime(3); }
      }
    }
  }
}
function carBodies() {
  for (const c of cars) {
    const sp = Math.hypot(c.vx, c.vz), fx = Math.sin(c.h), fz = Math.cos(c.h);
    for (const o of [1.25, -1.25]) {
      const cx = c.x + fx * o, cz = c.z + fz * o;
      if (sp > 2.5) for (const p of peds) {
        if (p.state === 'dead' || Math.abs(p.x - cx) > 2 || Math.abs(p.z - cz) > 2) continue;
        if (Math.hypot(p.x - cx, p.z - cz) < 1.45) killPed(p, c.vx * 0.8, c.vz * 0.8, c.driver === 'player', true);
      }
      if (!player.car && !player.dead) {
        const dx = player.x - cx, dz = player.z - cz, d = Math.hypot(dx, dz);
        if (d < 1.5 && d > 1e-4) {
          player.x += dx / d * (1.5 - d); player.z += dz / d * (1.5 - d);
          if (sp > 6 && player.hitCd <= 0) { player.hitCd = 0.7; damage(sp * 2.2); player.kx = c.vx * 0.7; player.kz = c.vz * 0.7; shake = 0.6; sfx.noise(0.15, 0.5, 600); }
        }
      }
    }
  }
}
function updatePeds(dt) {
  for (const p of peds) {
    if (p.state === 'dead') {
      p.t += dt;
      if (p.t < 2) {
        p.vy -= 20 * dt; p.x += p.vx * dt; p.z += p.vz * dt; p.y += p.vy * dt;
        const gy = groundY(p.x, p.z); if (p.y < gy) { p.y = gy; p.vy = 0; p.vx *= 0.6; p.vz *= 0.6; }
        p.p.g.rotation.x = -Math.min(Math.PI / 2, p.t * 7);
      }
      if (p.t > 20 && Math.hypot(p.x - player.x, p.z - player.z) > 60) respawnPed(p);
    } else {
      let sp = p.speed;
      if (p.state === 'flee') { sp = 4.8; p.t -= dt; if (p.t <= 0) p.state = 'walk'; }
      p.s += p.dir * sp * dt;
      const [x, z, dx, dz] = perim(p);
      p.x = x; p.z = z; p.y = SIDEY;
      p.p.g.rotation.y = lerpA(p.p.g.rotation.y, Math.atan2(dx, dz), 1 - Math.exp(-10 * dt));
      animLegs(p.p, sp, dt);
    }
    p.p.g.position.set(p.x, p.y, p.z);
  }
}
function updateCops(dt) {
  if (player.dead) { player.bustT = 0; return; }
  let near = 1e9, nearCop = null;
  for (const c of cars) {
    if (c.type !== 'cop' || c.wreck || c.driver !== 'ai' || c.mode !== 'chase') continue;
    const d = Math.hypot(c.x - player.x, c.z - player.z);
    if (d < near) { near = d; nearCop = c; }
    if (stars >= 3 && d < 24 && Math.hypot(c.vx, c.vz) < 14) {
      c.shootT -= dt;
      if (c.shootT <= 0) {
        c.shootT = 0.6 + Math.random() * 0.7;
        tracer(c.x, 1.5, c.z, player.x + (Math.random() - 0.5) * 2, player.y + 1.2, player.z + (Math.random() - 0.5) * 2);
        sfx.noise(0.14, clamp(0.5 - d / 60, 0, 0.5), 2400);
        if (Math.random() < 0.35) { if (player.car) player.car.health -= 6; else damage(7); }
      }
    }
  }
  const psp = player.car ? Math.hypot(player.car.vx, player.car.vz) : 0;
  const busting = nearCop && near < 6.5 && Math.hypot(nearCop.vx, nearCop.vz) < 4 && (!player.car || psp < 2);
  player.bustT = busting ? player.bustT + dt : Math.max(0, player.bustT - dt);
  if (player.bustT > (player.car ? 2.5 : 1.6)) endLife('busted');
  return near;
}
function updateWanted(dt, nearCop) {
  if (stars > 0) {
    if (nearCop < 50) unseenT = 0; else unseenT += dt;
    if (unseenT > 8 + stars * 2) { stars--; heat = stars > 0 ? TH[stars - 1] : 0; unseenT = 0; if (stars === 0) toast('수배 해제'); }
  }
  const chasing = cars.filter(c => c.type === 'cop' && c.mode === 'chase' && !c.wreck && c.driver === 'ai');
  const want = COPS_FOR[stars];
  if (stars === 0) { for (const c of chasing) { c.mode = 'traffic'; snapRoute(c); } }
  else if (chasing.length < want) {
    const patrol = cars.find(c => c.type === 'cop' && c.mode === 'traffic' && c.driver === 'ai' && !c.wreck && Math.hypot(c.x - player.x, c.z - player.z) < 160);
    if (patrol) patrol.mode = 'chase';
    else { copSpawnT -= dt; if (copSpawnT <= 0) { copSpawnT = 2.2; spawnRoadCar('cop', 'chase', 75, 150, true); } }
  } else if (chasing.length > want + 1) { const far = chasing.find(c => Math.hypot(c.x - player.x, c.z - player.z) > 130); if (far) { far.mode = 'traffic'; snapRoute(far); } }
}
function maintain() {
  const civ = cars.filter(c => c.type === 'civ' && c.driver === 'ai').length;
  if (civ < 22) spawnRoadCar('civ', 'traffic', 90, 300);
  const cops = cars.filter(c => c.type === 'cop' && !c.wreck);
  if (cops.length < 2) spawnRoadCar('cop', 'traffic', 90, 300);
  for (const c of [...cars]) {
    const d = Math.hypot(c.x - player.x, c.z - player.z);
    if (c.wreck && c.wreckT > 30 && d > 70) removeCar(c);
    else if (c.type === 'cop' && c.mode === 'traffic' && c.driver === 'ai' && cops.length > 4 && d > 180) { removeCar(c); cops.pop(); }
  }
  if (cars.length > 56) { const ab = cars.filter(c => !c.driver && !c.wreck).sort((a, b) => Math.hypot(b.x - player.x, b.z - player.z) - Math.hypot(a.x - player.x, a.z - player.z))[0]; if (ab && Math.hypot(ab.x - player.x, ab.z - player.z) > 150) removeCar(ab); }
}

// ================= camera =================
const camPos = new THREE.Vector3(CX, 140, CZ - 200);
function updateCamera(dt) {
  let tx, tz, ty, dist, hgt, ahead;
  if (state === 'menu') {
    camYaw += dt * 0.07; tx = CX; tz = CZ; ty = 0; dist = 230; hgt = 120; ahead = 0;
  } else if (player.car) {
    const c = player.car, sp = Math.abs(c.vF);
    camYaw = lerpA(camYaw, c.h, 1 - Math.exp(-(sp > 2 ? 3.2 : 1.2) * dt)); dragYaw = 0;
    tx = c.x; tz = c.z; ty = c.y; dist = 11 + sp * 0.13; hgt = 6.5 + sp * 0.08; ahead = 2 + sp * 0.25;
  } else {
    camYaw += dragYaw; dragYaw = 0; tx = player.x; tz = player.z; ty = player.y; dist = 8.5; hgt = 6.3; ahead = 2;
  }
  const fx = Math.sin(camYaw), fz = Math.cos(camYaw);
  const want = new THREE.Vector3(tx - fx * dist, ty + hgt, tz - fz * dist);
  camPos.lerp(want, state === 'menu' ? 1 - Math.exp(-1 * dt) : 1 - Math.exp(-7 * dt));
  shake *= Math.exp(-4 * dt);
  camera.position.set(camPos.x + (Math.random() - 0.5) * shake, camPos.y + (Math.random() - 0.5) * shake, camPos.z + (Math.random() - 0.5) * shake);
  camera.lookAt(tx + fx * ahead, ty + 1.4, tz + fz * ahead);
  if (window.__camOv) { camera.position.fromArray(window.__camOv.p); camera.lookAt(...window.__camOv.t); }
  sun.position.set(tx + lightDir.x * 200, lightDir.y * 200, tz + lightDir.z * 200); sun.target.position.set(tx, 0, tz); sun.target.updateMatrixWorld();
}

// ================= HUD =================
function drawOsmMap(x, o) {
  const D = OSM; x.fillStyle = '#41444d'; x.fillRect(0, 0, x.canvas.width, x.canvas.height);
  const poly = (p, col) => { x.fillStyle = col; x.beginPath(); for (let i = 0; i < p.length; i += 2) { const px = o + p[i], pz = o + p[i + 1]; if (i) x.lineTo(px, pz); else x.moveTo(px, pz); } x.closePath(); x.fill(); };
  for (const q of D.parks) poly(q.p, '#3f6e3c'); for (const q of D.water) poly(q.p, '#1d4c66');
  x.lineCap = 'round'; x.lineJoin = 'round'; x.strokeStyle = '#8f95a0';
  for (const r of D.roads) { x.lineWidth = r.w; x.beginPath(); for (let i = 0; i < r.p.length; i += 2) { if (i) x.lineTo(o + r.p[i], o + r.p[i + 1]); else x.moveTo(o + r.p[i], o + r.p[i + 1]); } x.stroke(); }
  for (const b of D.blds) poly(b.p, '#262830');
}
const mapOff = MINB - 25, mapSize = Math.ceil(MAXB + 25 - mapOff);
const mapC = makeCanvas(mapSize, mapSize);
{
  const x = mapC.getContext('2d'), o = -mapOff;
  x.fillStyle = '#1d4c66'; x.fillRect(0, 0, mapSize, mapSize);
  if (OSMG) drawOsmMap(x, o); else {
  x.fillStyle = '#9b8a62'; x.fillRect(o - R / 2 - 13, o - R / 2 - 13, CITY + R + 26, CITY + R + 26);
  x.fillStyle = '#8f95a0'; x.fillRect(o - R / 2, o - R / 2, CITY + R, CITY + R);
  for (const b of blocks) { x.fillStyle = b.kind === 'park' ? '#3f6e3c' : b.kind === 'lot' ? '#4b4d55' : '#41444d'; x.fillRect(o + b.x0, o + b.z0, B, B); }
  x.fillStyle = '#262830'; for (const list of colliders) for (const a of list) if (a[1] - a[0] > 2) x.fillRect(o + a[0], o + a[2], a[1] - a[0], a[3] - a[2]);
  }
  const icon = (p, bg, t) => { x.fillStyle = bg; x.fillRect(o + p.x - 6, o + p.z - 6, 12, 12); x.fillStyle = '#fff'; x.font = 'bold 10px sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText(t, o + p.x, o + p.z + 1); };
  icon(HOSPITAL, '#e5383b', 'H'); icon(STATION, '#2f6fe4', 'P');
}
const radar = $('radar'), rctx = radar.getContext('2d');
function drawRadar() {
  const css = radar.clientWidth || 132, dpr = Math.min(2, devicePixelRatio);
  if (radar.width !== Math.round(css * dpr)) { radar.width = radar.height = Math.round(css * dpr); }
  const W = radar.width, cx = W / 2, s = W / 132 * 0.78;
  const fx = Math.sin(camYaw), fz = Math.cos(camYaw), px = player.x, pz = player.z;
  rctx.setTransform(1, 0, 0, 1, 0, 0); rctx.clearRect(0, 0, W, W);
  rctx.save(); rctx.beginPath(); rctx.arc(cx, cx, cx, 0, Math.PI * 2); rctx.clip();
  rctx.setTransform(-s * fz, -s * fx, s * fx, -s * fz, cx + s * (-fz * (mapOff - px) + fx * (mapOff - pz)), cx + s * (-fx * (mapOff - px) - fz * (mapOff - pz)));
  rctx.drawImage(mapC, 0, 0);
  rctx.setTransform(1, 0, 0, 1, 0, 0);
  const toS = (x, z) => { const dx = x - px, dz = z - pz; return [cx + s * (-fz * dx + fx * dz), cx + s * (-fx * dx - fz * dz)]; };
  const dot = (x, z, col, r, edge) => {
    let [u, v] = toS(x, z); const ddx = u - cx, ddy = v - cx, l = Math.hypot(ddx, ddy), m = cx - r - 3;
    if (l > m) { if (!edge) return; u = cx + ddx / l * m; v = cx + ddy / l * m; }
    rctx.beginPath(); rctx.arc(u, v, r, 0, Math.PI * 2); rctx.fillStyle = col; rctx.fill(); rctx.lineWidth = 1.5 * dpr; rctx.strokeStyle = '#000'; rctx.stroke();
  };
  for (const c of cars) if (c.type === 'cop' && !c.wreck && c !== player.car) dot(c.x, c.z, c.mode === 'chase' ? ((time * 4 | 0) % 2 ? '#ff3b3b' : '#3b7bff') : '#7aa0ff', 3.2 * dpr, false);
  if (mission.stage !== 'none') dot(mission.x, mission.z, mission.stage === 'pickup' ? '#52e0ff' : '#ffd23f', 5 * dpr, true);
  const h = player.car ? player.car.h : player.h, hx = Math.sin(h), hz = Math.cos(h);
  const u = -fz * hx + fx * hz, v = -fx * hx - fz * hz, a = Math.atan2(v, u);
  rctx.translate(cx, cx); rctx.rotate(a + Math.PI / 2);
  rctx.beginPath(); rctx.moveTo(0, -8 * dpr); rctx.lineTo(6 * dpr, 6 * dpr); rctx.lineTo(0, 3 * dpr); rctx.lineTo(-6 * dpr, 6 * dpr); rctx.closePath();
  rctx.fillStyle = '#fff'; rctx.fill(); rctx.strokeStyle = '#000'; rctx.lineWidth = 1.5 * dpr; rctx.stroke();
  rctx.restore();
}
let toastT = 0;
function toast(t, good) { const el = $('toast'); el.textContent = t; el.className = 'hud show' + (good ? ' good' : ''); toastT = 2.6; }
function showMsg(t, sub, kind) { $('msgT').textContent = t; $('msgS').textContent = sub; $('msg').className = 'hud show ' + kind; }
const starEls = [...document.querySelectorAll('#stars i')];
let lastSave = 0;
function updateHUD(dt) {
  $('money').textContent = '$' + String(Math.max(0, Math.floor(money))).padStart(8, '0');
  starEls.forEach((e, k) => e.classList.toggle('on', k < stars));
  $('stars').classList.toggle('blink', stars > 0 && unseenT > 3);
  $('hp').style.width = clamp(player.hp, 0, 100) + '%';
  const c = player.car;
  $('carRow').style.display = c ? '' : 'none';
  if (c) { $('chp').style.width = clamp(c.health, 0, 100) + '%'; $('spd').textContent = Math.round(Math.abs(c.vF) * 3.6); }
  let mt = '';
  if (mission.stage === 'pickup') mt = '<b>택배 픽업</b> 파란 표시로 가세요 · ' + Math.round(Math.hypot(mission.x - player.x, mission.z - player.z)) + 'm';
  else if (mission.stage === 'deliver') mt = `<b>배달 중</b> 노란 표시까지 · <span class="${mission.t < 10 ? 'warn' : ''}">${Math.max(0, Math.ceil(mission.t))}초</span> · $${mission.reward}`;
  $('mission').innerHTML = mt; $('mission').style.display = mt ? '' : 'none';
  toastT -= dt; if (toastT <= 0) $('toast').classList.remove('show');
  const hurt = $('hurt'); hurt.style.opacity = Math.max(0, (+hurt.style.opacity || 0) - dt * 1.5);
  const nc = !player.car && !player.dead && nearestCar(4.2);
  $('bEnter').textContent = player.car ? '하차' : '탑승';
  $('bEnter').classList.toggle('hint', !!nc);
  $('hintE').style.display = (!isTouch && nc) ? '' : 'none';
  document.body.classList.toggle('driving', !!c);
  if (time - lastSave > 5) { lastSave = time; try { localStorage.setItem('ulsan_money', Math.floor(money)); } catch (e) { } }
}

// ================= sync & loop =================
function syncCar(c, dt) {
  c.y += (groundY(c.x, c.z) - c.y) * Math.min(1, dt * 12);
  c.g.position.set(c.x, c.y, c.z); c.g.rotation.y = c.h;
  c.body.rotation.z = clamp(-c.vL * 0.015, -0.08, 0.08);
  c.pitch += ((c.driver && !c.wreck ? -clamp(c.throttle, -1, 1) * 0.022 : 0) - c.pitch) * Math.min(1, dt * 6); c.body.rotation.x = c.pitch;
  c.wheelRot += c.vF * dt / 0.37;
  c.driverM.visible = !!c.driver && !c.wreck;
  const wd = (c.x - camera.position.x) ** 2 + (c.z - camera.position.z) ** 2, wv = wd < 4900;
  if (!c.wreck) c.glass.material = wd < 3600 ? glassMat : glassFar;
  for (let k = 0; k < 4; k++) { c.wm[k].visible = wv; if (wv) c.wm[k].rotation.x = c.wheelRot; }
  c.wp[0].rotation.y = c.wp[1].rotation.y = -c.steer * 0.5;
  if (!c.wreck) c.tail.material = (c.hb && c.driver) || (c.driver && c.throttle < -0.1 && c.vF > 0.5) ? tailOn : tailOff;
  if (c.burning) { const s = 0.7 + Math.random() * 0.6; c.fire.scale.set(s, s * 1.4, s); fireMat.color.setHSL(0.05 + Math.random() * 0.05, 1, 0.55); }
  if (c.mR) {
    const on = c.mode === 'chase' || (c === player.car && stars > 0), ph = (time * 6 | 0) % 2;
    c.mR.color.setHex(on && ph ? 0xff2020 : 0x550000); c.mB.color.setHex(on && !ph ? 0x2a5cff : 0x000055);
  }
}
function update(dt) {
  time += dt;
  readInput();
  if (state === 'play') updatePlayer(dt);
  for (const c of cars) carAI(c, dt);
  const steps = Math.max(1, Math.ceil(dt / 0.017)), h = dt / steps;
  for (let s = 0; s < steps; s++) { for (const c of cars) integrateCar(c, h); carCar(); for (const c of cars) carWorld(c); }
  carBodies();
  for (const c of [...cars]) {
    if (!c.wreck && c.health <= 0 && !c.burning) { c.burning = true; c.burnT = 4.5; c.fire.visible = true; if (c === player.car) toast('차에 불이 붙었어요! 빨리 내리세요'); }
    if (c.burning) { c.burnT -= dt; if (c.burnT <= 0) explode(c); }
    if (c.wreck) c.wreckT += dt;
    syncCar(c, dt);
  }
  updatePeds(dt);
  let nearCop = 1e9;
  if (state === 'play') { nearCop = updateCops(dt) ?? 1e9; updateWanted(dt, nearCop); updateMission(dt); }
  maintT -= dt; if (maintT <= 0) { maintT = 0.6; maintain(); }
  for (const t of tracers) if (t.t > 0) { t.t -= dt; t.l.material.opacity = t.t / 0.07; if (t.t <= 0) t.l.visible = false; }
  for (const f of flashes) if (f.t > 0) { f.t -= dt; const k = 1 - f.t / f.life; f.m.scale.setScalar(f.s * (0.4 + k)); f.m.material.opacity = 1 - k; if (f.t <= 0) f.m.visible = false; }
  player.p.g.position.set(player.x, player.y, player.z); player.p.g.rotation.y = player.h; player.p.g.visible = !player.car;
  updateCamera(dt);
  if (state === 'play') { updateHUD(dt); drawRadar(); }
  const pc = player.car;
  sfx.frame(!!pc && !player.dead, pc ? Math.abs(pc.vF) : 0, pc ? pc.throttle : 0, stars > 0 && nearCop < 90 ? 0.05 * (1 - nearCop / 90) : 0, dt);
}

// ================= init =================
function setPedCount(n) {
  while (peds.length > n) { const p = peds.pop(); scene.remove(p.p.g); }
  while (peds.length < n) {
  const p = { p: makePerson(pick(SHIRT), pick(PANTS), pick(SKIN), pick(HAIR), false), b: 0, s: 0, dir: Math.random() < 0.5 ? 1 : -1, off: Math.random() * 2 - 1, speed: 1.2 + Math.random() * 0.8, state: 'walk', t: 0, x: 0, z: 0, y: 0.25, vx: 0, vz: 0, vy: 0 };
  peds.push(p); respawnPed(p, false);
  }
}
if (OSMW) { Object.assign(player, { x: OSMW.start.x, z: OSMW.start.z, y: 0.03 }); }
for (const s of parkedSpots) { const c = makeCar('civ', pick(CAR_COL)); Object.assign(c, { x: s.x, z: s.z, h: s.h }); }
{ const c = makeCar('civ', '#e94f37', 'sedan'); Object.assign(c, OSMW ? OSMW.red : { x: 4 * P - LANE, z: 4 * P - 24, h: 0 }); }
for (let k = 0; k < 22; k++) spawnRoadCar('civ', 'traffic', 25, 600);
for (let k = 0; k < 3; k++) spawnRoadCar('cop', 'traffic', 60, 600);
for (const c of cars) syncCar(c, 1);
player.h = OSMW ? OSMW.start.h : Math.PI * 0.75;

function startGame() {
  if (state !== 'menu') return;
  sfx.init(); state = 'play'; camYaw = player.h;
  $('start').classList.add('gone'); document.body.classList.add('playing');
  toast('주차된 빨간 차에 다가가서 탑승해보세요');
  if (isTouch) try { document.documentElement.requestFullscreen?.().catch(() => { }); } catch (e) { }
}
$('play').addEventListener('click', startGame);
applyQuality();
$('qbtn').addEventListener('click', () => {
  const o = ['low', 'mid', 'high']; quality = o[(o.indexOf(quality) + 1) % 3];
  try { localStorage.setItem('ulsan_q', quality); } catch (e) { }
  applyQuality();
});

// ================= 위치 + 시간: 브라우저 위치(없으면 울산)와 현재 시각으로 태양/달/별/낮밤을 계산 =================
function setLocLabel() { const b = $('lbtn'); if (b) b.textContent = '위치: ' + (LOC_NAME || (LAT.toFixed(2) + ', ' + LON.toFixed(2))) + (LOC_REAL ? '' : ' (기본)'); }
async function reverseName() {
  try { const r = await fetch('https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=' + LAT + '&longitude=' + LON + '&localityLanguage=ko'); const j = await r.json(); LOC_NAME = j.city || j.locality || j.principalSubdivision || ''; saveLoc(); setLocLabel(); } catch (e) { }
}
function saveLoc() { try { localStorage.setItem('ulsan_loc', JSON.stringify({ lat: LAT, lon: LON, name: LOC_NAME })); } catch (e) { } }
function askLocation() {
  if (!navigator.geolocation) return;
  navigator.geolocation.getCurrentPosition(p => {
    const la = Math.round(p.coords.latitude * 100) / 100, lo = Math.round(p.coords.longitude * 100) / 100;
    const moved = Math.abs(la - LAT) > 0.05 || Math.abs(lo - LON) > 0.05 || !LOC_REAL; LAT = la; LON = lo; LOC_REAL = true;
    if (moved) { LOC_NAME = ''; reverseName(); } setLocLabel(); saveLoc(); fetchWeather(); osmEnsure(false);
  }, () => { }, { timeout: 8000, maximumAge: 3600000 });
}
const RAD = Math.PI / 180, smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
function solarPos(date, lat, lon) { // NOAA 간이식: 고도/방위(북=0, 동=90) 도 단위
  const d = date.getTime() / 86400000 + 2440587.5 - 2451545.0, g = ((357.529 + 0.98560028 * d) % 360) * RAD, q = (280.459 + 0.98564736 * d) % 360;
  const L = (q + 1.915 * Math.sin(g) + 0.02 * Math.sin(2 * g)) * RAD, e = (23.439 - 3.6e-7 * d) * RAD;
  const ra = Math.atan2(Math.cos(e) * Math.sin(L), Math.cos(L)), dec = Math.asin(Math.sin(e) * Math.sin(L));
  const H = (((18.697374558 + 24.06570982441908 * d) % 24) * 15 + lon) * RAD - ra, la = lat * RAD;
  const el = Math.asin(Math.sin(la) * Math.sin(dec) + Math.cos(la) * Math.cos(dec) * Math.cos(H));
  const az = Math.atan2(-Math.sin(H) * Math.cos(dec), Math.sin(dec) * Math.cos(la) - Math.cos(dec) * Math.sin(la) * Math.cos(H));
  return { el: el / RAD, az: ((az / RAD) + 360) % 360 };
}
const TNAME = ['실시간', '아침', '낮', '노을', '밤', '가속'];
let tMode = 0; try { tMode = Math.max(0, Math.min(5, +localStorage.getItem('ulsan_t') || 0)); } catch (e) { }
let tAccel0 = Date.now(), tClockTxt = '';
function dayAt(h, m) { const d = new Date(); d.setHours(h, m, 0, 0); return d; }
function findTime(target, evening) { // 오늘 날짜에서 태양 고도가 target 이 되는 시각(저녁/아침)
  const d = new Date(); d.setHours(evening ? 12 : 2, 0, 0, 0);
  for (let i = 0; i < 12 * 60; i++) { const t = new Date(d.getTime() + i * 60000), e = solarPos(t, LAT, LON).el; if (evening ? e <= target : e >= target) return t; }
  return evening ? dayAt(19, 0) : dayAt(7, 0);
}
function simDate() {
  if (tMode === 0) return new Date();
  if (tMode === 1) return findTime(14, false);
  if (tMode === 2) return dayAt(13, 0);
  if (tMode === 3) return findTime(7, true);
  if (tMode === 4) return dayAt(0, 30);
  return new Date(tAccel0 + (Date.now() - tAccel0) * 600);
}
const T = { el: 12, day: 0, dusk: 1, night: 0, lampOn: 0.1, bright: 0.6, sunI: 2.7 };
const lightDir = new THREE.Vector3(), moonDir = new THREE.Vector3();
const SUNC_LOW = new THREE.Color(0xffb27a), SUNC_MID = new THREE.Color(0xffe0bd), SUNC_HIGH = new THREE.Color(0xfff6ec), MOONC = new THREE.Color(0x8fa6d8);
const sunColor = new THREE.Color(), _tc = new THREE.Color();
// 별 / 달
const starMat = new THREE.ShaderMaterial({
  uniforms: { uA: { value: 0 }, uT: { value: 0 }, uPR: { value: 1 } },
  vertexShader: 'attribute float aS; varying float vB; uniform float uT, uPR; void main(){ vB = 0.55 + 0.45 * sin(uT * (1.0 + aS) + aS * 40.0); gl_PointSize = (1.2 + aS * 2.2) * uPR; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: 'uniform float uA; varying float vB; void main(){ float d = length(gl_PointCoord - 0.5); gl_FragColor = vec4(vec3(0.85, 0.9, 1.0), smoothstep(0.5, 0.1, d) * vB * uA); }',
  transparent: false, blending: THREE.AdditiveBlending, depthWrite: false, depthTest: false, fog: false
});
const SC = 1800, starPos = new Float32Array(SC * 3), starS = new Float32Array(SC);
for (let i = 0; i < SC; i++) { const u = Math.random() * 2 - 1, a = Math.random() * 6.2832, r = Math.sqrt(1 - u * u), y = Math.abs(u) * 0.97 + 0.03; starPos.set([Math.cos(a) * r * 360, y * 360, Math.sin(a) * r * 360], i * 3); starS[i] = Math.random(); }
const starGeo = new THREE.BufferGeometry(); starGeo.setAttribute('position', new THREE.BufferAttribute(starPos, 3)); starGeo.setAttribute('aS', new THREE.BufferAttribute(starS, 1));
const starPts = new THREE.Points(starGeo, starMat); starPts.frustumCulled = false; starPts.renderOrder = -0.7; scene.add(starPts);
const moonTex = (() => {
  const c = makeCanvas(128, 128), x = c.getContext('2d'), gl = x.createRadialGradient(64, 64, 8, 64, 64, 64); gl.addColorStop(0, 'rgba(190,205,240,.55)'); gl.addColorStop(1, 'rgba(190,205,240,0)'); x.fillStyle = gl; x.fillRect(0, 0, 128, 128);
  x.fillStyle = '#eef2fb'; x.beginPath(); x.arc(64, 64, 20, 0, 6.2832); x.fill();
  x.fillStyle = 'rgba(150,160,185,.35)'; for (const [a, b, r] of [[58, 58, 5], [72, 66, 4], [62, 74, 3.5], [70, 54, 2.5]]) { x.beginPath(); x.arc(a, b, r, 0, 6.2832); x.fill(); }
  return tex(c, false);
})();
const moon = new THREE.Sprite(new THREE.SpriteMaterial({ map: moonTex, transparent: false, blending: THREE.CustomBlending, blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneMinusSrcAlphaFactor, depthTest: false, depthWrite: false, fog: false }));
moon.scale.setScalar(90); moon.renderOrder = -0.6; moon.frustumCulled = false; scene.add(moon);
function updateTime(dt) {
  const now = simDate(), sp = solarPos(now, LAT, LON), el = sp.el, az = sp.az * RAD, ce = Math.cos(el * RAD);
  sunDir.set(Math.sin(az) * ce, Math.sin(el * RAD), Math.cos(az) * ce).normalize();
  T.el = el; T.night = 1 - smooth(-9, 1, el); T.day = smooth(6, 26, el); T.dusk = smooth(-6, 4, el); T.lampOn = 1 - smooth(0, 14, el); T.bright = 0.1 + 0.9 * smooth(-8, 12, el);
  const nightLight = smooth(-2, 6, el);
  if (el > -1) { lightDir.copy(sunDir); sunColor.copy(SUNC_LOW).lerp(SUNC_MID, smooth(2, 16, el)).lerp(SUNC_HIGH, smooth(16, 42, el)); T.sunI = 2.9 * smooth(-2, 9, el) + 0.05; }
  else { moonDir.set(-sunDir.x, Math.max(0.35, -sunDir.y * 0.8 + 0.3), -sunDir.z).normalize(); lightDir.copy(moonDir); sunColor.copy(MOONC); T.sunI = 0.42 * smooth(-1, -8, el) + 0.05; }
  moonDir.set(-sunDir.x, Math.max(0.3, Math.min(0.8, -sunDir.y * 0.7 + 0.35)), -sunDir.z).normalize();
  lightDir.y = Math.max(lightDir.y, 0.16); lightDir.normalize();
  sky.material.uniforms.sunPosition.value.copy(sunDir);
  starPts.position.copy(camera.position); starMat.uniforms.uA.value = T.night * (1 - 0.92 * wc.cloud) * (1 - wc.fog) * (1 - 0.9 * wc.rain); starMat.uniforms.uT.value = time; starMat.uniforms.uPR.value = renderer.getPixelRatio(); starPts.visible = starMat.uniforms.uA.value > 0.01;
  moon.position.copy(camera.position).addScaledVector(moonDir, 330); moon.material.opacity = T.night * (1 - 0.85 * wc.cloud) * (1 - wc.rain); moon.visible = moon.material.opacity > 0.02;
  // 야간 점등: 가로등/웅덩이/창문/전조등
  lampBulbMat.emissiveIntensity = 4 * T.lampOn + 0.15; poolMat.opacity = 0.5 * T.lampOn; headMat.emissiveIntensity = 0.5 + 2.4 * T.lampOn;
  const wi = 0.1 + 0.8 * T.lampOn; for (const m of emisMats) m.emissiveIntensity = wi;
  const hh = now.getHours(), mm = now.getMinutes(); tClockTxt = (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm;
  const tb = $('tbtn'); if (tb && tb._t !== tMode + tClockTxt) { tb._t = tMode + tClockTxt; tb.textContent = '시간: ' + TNAME[tMode] + ' ' + tClockTxt + (el > 0 ? ' ☀' : ' ☾'); }
}
$('tbtn').addEventListener('click', () => { tMode = (tMode + 1) % 6; tAccel0 = Date.now(); try { localStorage.setItem('ulsan_t', tMode); } catch (e) { } });
$('lbtn').addEventListener('click', () => { LOC_REAL = false; askLocation(); });
setLocLabel(); askLocation(); if (LOC_REAL && !LOC_NAME) reverseName();
window.__time = { set(m) { tMode = m; tAccel0 = Date.now(); }, T, get loc() { return [LAT, LON, LOC_NAME]; }, solarPos };

// ================= 날씨: 울산 실시간 날씨(Open-Meteo, 키 불필요)를 받아와 하늘/구름/안개/비/눈/번개/젖은 노면에 반영 =================
const WNAME = ['실시간', '맑음', '흐림', '비', '눈', '안개', '뇌우'];
const WPRESET = [null, { cloud: 0.08, rain: 0, snow: 0, fog: 0, wind: 0.25, thunder: 0, desc: '맑음' }, { cloud: 0.92, rain: 0, snow: 0, fog: 0.12, wind: 0.4, thunder: 0, desc: '흐림' },
  { cloud: 0.95, rain: 0.75, snow: 0, fog: 0.2, wind: 0.6, thunder: 0, desc: '비' }, { cloud: 0.92, rain: 0, snow: 0.8, fog: 0.15, wind: 0.3, thunder: 0, desc: '눈' },
  { cloud: 0.8, rain: 0, snow: 0, fog: 0.95, wind: 0.1, thunder: 0, desc: '안개' }, { cloud: 1, rain: 1, snow: 0, fog: 0.2, wind: 0.9, thunder: 1, desc: '뇌우' }];
let wMode = 0; try { wMode = Math.max(0, Math.min(6, +localStorage.getItem('ulsan_w') || 0)); } catch (e) { }
const wt = { cloud: 0.1, rain: 0, snow: 0, fog: 0, wind: 0.25, thunder: 0, desc: '맑음', temp: null }, wc = { cloud: 0.1, rain: 0, snow: 0, fog: 0, wind: 0.25, thunder: 0 };
let wLive = null, wetAmt = 0, snowAmt = 0, wFlash = 0, wThunderT = 8, wJump = true;
function liveFrom(c) {
  const code = c.weather_code, cc = (c.cloud_cover || 0) / 100, p = c.precipitation || 0, o = { cloud: cc, rain: 0, snow: 0, fog: 0, wind: clamp((c.wind_speed_10m || 0) / 35, 0.08, 1), thunder: 0, desc: '맑음', temp: c.temperature_2m };
  const ri = b => clamp(Math.max(b, Math.min(1, p / 4)), 0.2, 1);
  if (code === 0) { o.desc = '맑음'; o.cloud = Math.min(o.cloud, 0.2); }
  else if (code <= 2) { o.desc = code === 1 ? '대체로 맑음' : '구름 많음'; o.cloud = Math.max(o.cloud, code === 1 ? 0.2 : 0.5); }
  else if (code === 3) { o.desc = '흐림'; o.cloud = Math.max(o.cloud, 0.88); }
  else if (code === 45 || code === 48) { o.desc = '안개'; o.fog = 0.9; o.cloud = Math.max(o.cloud, 0.7); }
  else if (code >= 51 && code <= 57) { o.desc = '이슬비'; o.rain = ri(0.25); o.cloud = Math.max(o.cloud, 0.9); }
  else if (code >= 61 && code <= 67) { o.desc = '비'; o.rain = ri(code === 61 ? 0.45 : code === 63 ? 0.7 : 1); o.cloud = Math.max(o.cloud, 0.92); }
  else if ((code >= 71 && code <= 77) || code === 85 || code === 86) { o.desc = '눈'; o.snow = clamp(code === 71 || code === 77 ? 0.45 : code === 73 || code === 85 ? 0.75 : 1, 0.3, 1); o.cloud = Math.max(o.cloud, 0.9); }
  else if (code >= 80 && code <= 82) { o.desc = '소나기'; o.rain = ri(code === 80 ? 0.5 : code === 81 ? 0.75 : 1); o.cloud = Math.max(o.cloud, 0.9); }
  else if (code >= 95) { o.desc = '뇌우'; o.rain = ri(0.9); o.thunder = 1; o.cloud = 1; }
  return o;
}
function applyWeatherMode() {
  const src = wMode ? WPRESET[wMode] : (wLive || WPRESET[1]);
  for (const k of ['cloud', 'rain', 'snow', 'fog', 'wind', 'thunder']) wt[k] = src[k];
  wt.desc = src.desc; wt.temp = wMode ? null : (wLive ? wLive.temp : null);
  const b = $('wbtn'); if (b) b.textContent = '날씨: ' + (wMode ? WNAME[wMode] : (wLive ? wt.desc + (wt.temp != null ? ' ' + Math.round(wt.temp) + '°C' : '') + ' (실시간)' : '실시간 (확인 중)'));
}
async function fetchWeather() {
  try {
    const r = await fetch('https://api.open-meteo.com/v1/forecast?latitude=' + LAT + '&longitude=' + LON + '&current=temperature_2m,weather_code,cloud_cover,precipitation,wind_speed_10m&wind_speed_unit=kmh&timezone=Asia%2FSeoul');
    const j = await r.json(); if (j && j.current) { wLive = liveFrom(j.current); window.__wlive = j.current; applyWeatherMode(); }
  } catch (e) { }
}
// 구름 돔(절차 노이즈 fbm). 덮개/그림자/바람 이동 + 해 방향 노을 빛
const cloudMat = new THREE.ShaderMaterial({
  uniforms: { uTime: { value: 0 }, uCover: { value: 0.1 }, uDark: { value: 0 }, uWind: { value: new THREE.Vector2(0.004, 0.002) }, uSun: { value: sunDir.clone() }, uLit: { value: new THREE.Color(1, 0.72, 0.58) }, uShade: { value: new THREE.Color(0.45, 0.38, 0.5) }, uGlow: { value: 1 } },
  vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform float uTime, uCover, uDark; uniform vec2 uWind; uniform vec3 uSun, uLit, uShade; uniform float uGlow; varying vec3 vDir;
float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
float fbm(vec2 p){ float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * n(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5; } return s; }
void main(){
  vec3 d = normalize(vDir); float up = max(d.y, 0.0);
  vec2 uv = d.xz / (up + 0.2) * 1.5 + uWind * uTime;
  float c = fbm(uv), thr = 1.0 - uCover * 0.92;
  float m = smoothstep(thr, thr + 0.22, c);
  float hz = mix(smoothstep(-0.04, 0.2, d.y), 1.0, uCover * uCover);
  float shade = smoothstep(thr, thr + 0.45, c);
  float sg = pow(max(dot(d, uSun), 0.0), 5.0);
  vec3 col = mix(uLit, uShade, shade * 0.75 + uDark * 0.45);
  col += vec3(1.0, 0.5, 0.25) * sg * (1.0 - uDark) * 0.9 * (1.0 - shade * 0.6) * uGlow;
  gl_FragColor = vec4(col, m * hz * (0.5 + 0.5 * uCover));
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`,
  side: THREE.BackSide, transparent: false, blending: THREE.CustomBlending, blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneMinusSrcAlphaFactor, depthWrite: false, depthTest: false, fog: false
});
const cloudDome = new THREE.Mesh(new THREE.SphereGeometry(380, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2 + 0.2), cloudMat); cloudDome.renderOrder = -0.5; cloudDome.frustumCulled = false; scene.add(cloudDome);
// 비(선분 스트릭) / 눈(점) : GPU 에서 카메라 주변 상자를 순환
const PREC_VS = `uniform vec3 uCam; uniform float uTime, uPR; uniform vec2 uWind; attribute float aEnd; varying float vA;
const vec3 BOX = vec3(60.0, 36.0, 60.0);`;
const rainMat = new THREE.ShaderMaterial({
  uniforms: { uCam: { value: new THREE.Vector3() }, uTime: { value: 0 }, uWind: { value: new THREE.Vector2() }, uPR: { value: 1 }, uOpacity: { value: 0 } },
  vertexShader: PREC_VS + `void main(){
    vec3 vel = vec3(uWind.x * 4.0, -28.0, uWind.y * 4.0);
    vec3 rel = mod(position + vel * uTime - uCam, BOX) - BOX * 0.5; vec3 wp = uCam + rel;
    wp -= aEnd * normalize(vel) * 1.1; vA = (1.0 - aEnd * 0.85) * (1.0 - smoothstep(18.0, 30.0, length(rel.xz)));
    gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0); }`,
  fragmentShader: 'uniform float uOpacity; varying float vA; void main(){ gl_FragColor = vec4(0.78, 0.84, 0.92, vA * uOpacity); }',
  transparent: true, depthWrite: false, fog: false
});
const RN = 3200, rainPos = new Float32Array(RN * 6), rainEnd = new Float32Array(RN * 2);
for (let i = 0; i < RN; i++) { const x = Math.random() * 60, y = Math.random() * 36, z = Math.random() * 60; rainPos.set([x, y, z, x, y, z], i * 6); rainEnd[i * 2 + 1] = 1; }
const rainGeo = new THREE.BufferGeometry(); rainGeo.setAttribute('position', new THREE.BufferAttribute(rainPos, 3)); rainGeo.setAttribute('aEnd', new THREE.BufferAttribute(rainEnd, 1));
const rainMesh = new THREE.LineSegments(rainGeo, rainMat); rainMesh.frustumCulled = false; rainMesh.visible = false; rainMesh.renderOrder = 5; scene.add(rainMesh);
const snowMat = new THREE.ShaderMaterial({
  uniforms: { uCam: { value: new THREE.Vector3() }, uTime: { value: 0 }, uWind: { value: new THREE.Vector2() }, uPR: { value: 1 }, uOpacity: { value: 0 } },
  vertexShader: PREC_VS + `void main(){
    vec3 p = position + vec3(sin(uTime * 0.7 + position.z) * 1.2 + uWind.x * uTime * 2.5, -uTime * 1.8, cos(uTime * 0.6 + position.x) * 1.2 + uWind.y * uTime * 2.5);
    vec3 rel = mod(p - uCam, BOX) - BOX * 0.5; vec4 mv = viewMatrix * vec4(uCam + rel, 1.0);
    gl_PointSize = clamp(uPR * 90.0 / max(-mv.z, 1.0), 2.5, 16.0 * uPR); vA = 1.0 - smoothstep(18.0, 30.0, length(rel.xz));
    gl_Position = projectionMatrix * mv; }`,
  fragmentShader: 'uniform float uOpacity; varying float vA; void main(){ float d = length(gl_PointCoord - 0.5); gl_FragColor = vec4(1.0, 1.0, 1.0, smoothstep(0.5, 0.15, d) * vA * uOpacity); }',
  transparent: true, depthWrite: false, fog: false
});
const SN = 2400, snowPos = new Float32Array(SN * 3); for (let i = 0; i < SN; i++) snowPos.set([Math.random() * 60, Math.random() * 36, Math.random() * 60], i * 3);
const snowGeo = new THREE.BufferGeometry(); snowGeo.setAttribute('position', new THREE.BufferAttribute(snowPos, 3));
const snowMesh = new THREE.Points(snowGeo, snowMat); snowMesh.frustumCulled = false; snowMesh.visible = false; snowMesh.renderOrder = 5; scene.add(snowMesh);

const FOG_NIGHT = new THREE.Color(0x0b1020), FOG_DAY = new THREE.Color(0xb4cbe0), HEMI_NIGHT = new THREE.Color(0x1c2a55), HEMI_DAY = new THREE.Color(0xc9e1ff), HEMIG_NIGHT = new THREE.Color(0x0a0c14), HEMIG_DAY = new THREE.Color(0x7a6f5f), LIT_NIGHT = new THREE.Color(0.07, 0.09, 0.15), LIT_SUNSET = new THREE.Color(1, 0.72, 0.58), LIT_DAY = new THREE.Color(1, 1, 1), SHD_NIGHT = new THREE.Color(0.02, 0.03, 0.06), SHD_SUNSET = new THREE.Color(0.45, 0.38, 0.5), SHD_DAY = new THREE.Color(0.5, 0.56, 0.66);
const m3 = (n, s, d) => { const a = n + (s - n) * T.dusk; return a + (d - a) * T.day; };
const FOG_CLEAR = new THREE.Color(0xeb9a7e), FOG_GRAY = new THREE.Color(0x8d98a3), FOG_SNOW = new THREE.Color(0xb9c0c8), FOG_MIST = new THREE.Color(0xaeb4ba);
const SUN_CLEAR = new THREE.Color(0xffb27a), SUN_GRAY = new THREE.Color(0xdde4ec), HEMI_CLEAR = new THREE.Color(0xffd6c0), HEMI_GRAY = new THREE.Color(0xcdd6e0), HEMIG_CLEAR = new THREE.Color(0x5a4a78), HEMIG_GRAY = new THREE.Color(0x4a5360);
const LIT_CLEAR = new THREE.Color(1, 0.72, 0.58), LIT_GRAY = new THREE.Color(0.8, 0.82, 0.86), SHD_CLEAR = new THREE.Color(0.45, 0.38, 0.5), SHD_GRAY = new THREE.Color(0.24, 0.26, 0.3), WATER_CLEAR = new THREE.Color('#2d7da3'), WATER_GRAY = new THREE.Color('#566f80'), _c = new THREE.Color();
const groundMats = [roadMat, crossMat, walkMat, lotMat, grassMat];
function updateWeather(dt) {
  dt = clamp(dt, 0, 0.1);
  const k = 1 - Math.exp(-dt * (wJump ? 50 : 0.45));
  for (const key of ['cloud', 'rain', 'snow', 'fog', 'wind', 'thunder']) wc[key] += (wt[key] - wc[key]) * k;
  const wetT = Math.min(1, wc.rain * 1.4), snowT = Math.min(1, wc.snow * 1.3);
  wetAmt += (wetT - wetAmt) * (1 - Math.exp(-dt * (wJump ? 50 : wetT > wetAmt ? 0.5 : 0.04)));
  snowAmt += (snowT - snowAmt) * (1 - Math.exp(-dt * (wJump ? 50 : snowT > snowAmt ? 0.12 : 0.015)));
  wJump = false;
  const gloom = Math.max(wc.cloud * 0.7, wc.rain * 0.85, wc.snow * 0.6, wc.fog * 0.6), dark = Math.max(wc.rain, wc.thunder, wc.cloud * 0.35);
  const cu = cloudMat.uniforms; cu.uTime.value += dt; cu.uCover.value = wc.cloud; cu.uDark.value = dark; cu.uWind.value.set(0.0035 + wc.wind * 0.012, 0.0018 + wc.wind * 0.006);
  cu.uLit.value.copy(LIT_NIGHT).lerp(LIT_SUNSET, T.dusk).lerp(LIT_DAY, T.day).lerp(_c.copy(LIT_GRAY).multiplyScalar(T.bright), gloom); cu.uShade.value.copy(SHD_NIGHT).lerp(SHD_SUNSET, T.dusk).lerp(SHD_DAY, T.day).lerp(_c.copy(SHD_GRAY).multiplyScalar(T.bright), Math.max(gloom, dark)); cu.uSun.value.copy(sunDir); cu.uGlow.value = T.dusk * (1 - 0.85 * T.day) * (T.el > -3 ? 1 : 0);
  cloudDome.position.copy(camera.position);
  // 번개: 번쩍임 + 천둥
  if (wc.thunder > 0.4) { wThunderT -= dt; if (wThunderT < 0) { wThunderT = 5 + Math.random() * 11; wFlash = 1; setTimeout(() => { wFlash = Math.max(wFlash, 0.7); }, 110); setTimeout(() => sfx.thunder(), 400 + Math.random() * 1800); } }
  wFlash *= Math.exp(-dt * 9);
  sky.material.uniforms.turbidity.value = 4 + 6 * (1 - T.day) + 10 * gloom; sky.material.uniforms.rayleigh.value = 1.6 + 1.6 * (1 - T.day);
  const fogMix = Math.max(wc.rain * 0.7, wc.cloud * 0.55);
  const fc = scene.fog.color.copy(FOG_NIGHT).lerp(FOG_CLEAR, T.dusk).lerp(FOG_DAY, T.day).lerp(_c.copy(FOG_GRAY).multiplyScalar(T.bright), fogMix); if (wc.snow > 0.05) fc.lerp(_c.copy(FOG_SNOW).multiplyScalar(T.bright), Math.min(1, wc.snow)); if (wc.fog > 0.05) fc.lerp(_c.copy(FOG_MIST).multiplyScalar(T.bright), Math.min(1, wc.fog));
  scene.fog.near = 110 * (1 - wc.fog) * (1 - 0.35 * wc.rain) * (1 - 0.3 * wc.snow) + 6 * wc.fog; scene.fog.far = 360 * (1 - 0.78 * wc.fog) * (1 - 0.4 * wc.rain) * (1 - 0.35 * wc.snow);
  sun.intensity = T.sunI * (1 - 0.9 * gloom) + wFlash * 1.2; sun.color.copy(sunColor).lerp(_c.copy(SUN_GRAY).multiplyScalar(Math.max(0.35, T.bright)), gloom);
  hemi.intensity = m3(0.3, 0.35, 0.55) + 0.5 * gloom * T.bright + wFlash * 2.4; hemi.color.copy(HEMI_NIGHT).lerp(HEMI_CLEAR, T.dusk).lerp(HEMI_DAY, T.day).lerp(_c.copy(HEMI_GRAY).multiplyScalar(T.bright), gloom); hemi.groundColor.copy(HEMIG_NIGHT).lerp(HEMIG_CLEAR, T.dusk).lerp(HEMIG_DAY, T.day).lerp(_c.copy(HEMIG_GRAY).multiplyScalar(T.bright), gloom);
  scene.environmentIntensity = m3(0.06, 0.45, 0.55) * (1 - 0.45 * gloom) + 0.25 * wetAmt * T.bright + wFlash * 0.8; renderer.toneMappingExposure = m3(1.2, 1, 0.95) + 0.2 * gloom;
  for (const m of groundMats) { m.roughness = 1 - 0.58 * wetAmt; m.color.setScalar(1 - 0.3 * wetAmt - 0.1 * snowAmt); m.emissive.setScalar(0.2 * snowAmt); }
  const wm = matCache.get('#5d5866'); if (wm) wm.emissive.setScalar(0.3 * snowAmt);
  const cp = camera.position, wv = cu.uWind.value;
  const rv = wc.rain > 0.03; rainMesh.visible = rv; if (rv) { rainMat.uniforms.uCam.value.copy(cp); rainMat.uniforms.uTime.value = time; rainMat.uniforms.uWind.value.set(wc.wind * 3 - 1, wc.wind * 1.5); rainMat.uniforms.uOpacity.value = 0.2 + 0.4 * wc.rain; rainGeo.setDrawRange(0, Math.floor(RN * (0.15 + 0.85 * wc.rain)) * 2); }
  const sv = wc.snow > 0.03; snowMesh.visible = sv; if (sv) { snowMat.uniforms.uCam.value.copy(cp); snowMat.uniforms.uTime.value = time; snowMat.uniforms.uWind.value.set(wc.wind * 2, wc.wind); snowMat.uniforms.uPR.value = renderer.getPixelRatio(); snowMat.uniforms.uOpacity.value = 0.55 + 0.4 * wc.snow; snowGeo.setDrawRange(0, Math.floor(SN * (0.2 + 0.8 * wc.snow))); }
  WU.uTime.value = time; WU.uWind.value = 0.25 + wc.wind * 1.2;
  waterMat.color.lerpColors(WATER_CLEAR, WATER_GRAY, gloom).multiplyScalar(0.22 + 0.78 * T.bright); waterMat.normalScale.setScalar(0.55 * (1 + wc.wind * 1.1) + wc.rain * 0.2);
  const wo = waterMat.normalMap.offset, sp = 1 + wc.wind * 3; wo.x += dt * 0.0022 * sp; wo.y += dt * 0.0013 * sp;
  sfx.weather(wc.rain, wc.wind, wc.snow);
}
applyWeatherMode(); fetchWeather(); setInterval(fetchWeather, 600000);
$('wbtn').addEventListener('click', () => { wMode = (wMode + 1) % 7; try { localStorage.setItem('ulsan_w', wMode); } catch (e) { } applyWeatherMode(); });
window.__dbg = { scene, renderer, camera, cloudDome, rainMesh, snowMesh, composer: () => composer };
window.__weather = { set(m) { wMode = m; applyWeatherMode(); wJump = true; }, wc, wt, get live() { return wLive; } };

// ---- 맵 선택(격자 도시 / 내 주변 OSM) 및 불러오기
function setMapStat(t) { const e = $('mapstat'); if (e) e.textContent = t; }
function setMapBtn() { const b = $('mapbtn'); if (b) b.textContent = '맵: ' + (OSM_WANT ? '내 주변 (OpenStreetMap)' : '격자 도시'); }
function osmCacheOk() { try { const d = JSON.parse(localStorage.getItem('ulsan_osm') || 'null'); return !!(d && d.roads && Math.abs(d.lat - LAT) < 0.004 && Math.abs(d.lon - LON) < 0.004); } catch (e) { return false; } }
let osmBusy = false;
async function osmEnsure(force) {
  if (!OSM_WANT || osmBusy) return;
  if (!force && osmCacheOk()) { if (!OSMG && state === 'menu') { location.reload(); return; } setMapStat(OSMG ? '내 주변 지도 사용 중 (건물 ' + OSM.blds.length + '개, 도로 ' + OSM.roads.length + '개)' : '지도 준비 완료 - 새로고침하면 적용돼요'); return; }
  osmBusy = true; setMapStat('내 주변 지도를 불러오는 중… (' + LAT.toFixed(3) + ', ' + LON.toFixed(3) + ')');
  try {
    const d = await osmFetch(LAT, LON); if (d.roads.length < 3) throw new Error('도로 데이터가 너무 적어요');
    localStorage.setItem('ulsan_osm', JSON.stringify(d)); osmBusy = false;
    if (state === 'menu') { location.reload(); return; } setMapStat('지도 준비 완료 - 새로고침하면 적용돼요');
  } catch (e) { osmBusy = false; setMapStat('지도 불러오기 실패 - 격자 도시로 시작해요 (' + (e && e.message || e) + ')'); }
}
$('mapbtn').addEventListener('click', () => {
  OSM_WANT = !OSM_WANT; try { localStorage.setItem('ulsan_map', OSM_WANT ? 'osm' : 'grid'); } catch (e) { }
  setMapBtn(); if (OSM_WANT) osmEnsure(false); else { setMapStat(''); if (OSMG && state === 'menu') location.reload(); }
});
setMapBtn(); if (OSMG) setMapStat('내 주변 지도 사용 중 (건물 ' + OSM.blds.length + '개, 도로 ' + OSM.roads.length + '개)'); else if (OSM_WANT) osmEnsure(false);
window.__osm = { ensure: osmEnsure, get ok() { return !!OSMG; }, get data() { return OSM; } };
let last = performance.now(), fpsAcc = 0, fpsN = 0;
function loop(now) {
  const dt = Math.min(0.066, (now - last) / 1000); last = now;
  update(dt);
  sky.position.copy(camera.position); updateTime(dt); updateWeather(dt);
  if (composer) composer.render(dt); else renderer.render(scene, camera);
  fpsAcc += dt; fpsN++; if (fpsAcc > 1) { window.__fps = fpsN / fpsAcc; fpsAcc = 0; fpsN = 0; }
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
window.__game = { player, cars, peds, get stars() { return stars; }, crime, startGame, mission, input, keys };
