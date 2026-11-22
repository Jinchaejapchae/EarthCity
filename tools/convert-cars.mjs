// Kenney Car Kit(CC0) GLB -> 양자화한 JS 모듈(src/carModels.js). 사용: node tools/convert-cars.mjs <glb 폴더>
import fs from 'fs'; import crypto from 'crypto'; import path from 'path';
const dir = process.argv[2], OUT = 'src/carModels.js';
const MODELS = ['sedan', 'sedan-sports', 'hatchback-sports', 'suv', 'suv-luxury', 'taxi', 'van', 'truck', 'delivery', 'police'];
const b64 = u8 => Buffer.from(u8.buffer, u8.byteOffset, u8.byteLength).toString('base64');
function readGlb(f) {
  const b = fs.readFileSync(f), jl = b.readUInt32LE(12), j = JSON.parse(b.slice(20, 20 + jl).toString()), bo = 20 + jl + 8;
  return { j, bin: b.slice(bo) };
}
function acc(g, i) {
  const { j, bin } = g, a = j.accessors[i], bv = j.bufferViews[a.bufferView], n = a.count, nc = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type];
  const CT = { 5126: Float32Array, 5123: Uint16Array, 5125: Uint32Array, 5121: Uint8Array, 5120: Int8Array, 5122: Int16Array }[a.componentType], es = CT.BYTES_PER_ELEMENT, stride = bv.byteStride || nc * es, off = (bv.byteOffset || 0) + (a.byteOffset || 0);
  const out = new CT(n * nc); const dv = new DataView(bin.buffer, bin.byteOffset);
  for (let k = 0; k < n; k++) for (let c = 0; c < nc; c++) { const p = off + k * stride + c * es; out[k * nc + c] = es === 4 ? (CT === Float32Array ? dv.getFloat32(p, true) : dv.getUint32(p, true)) : es === 2 ? (CT === Int16Array ? dv.getInt16(p, true) : dv.getUint16(p, true)) : (CT === Int8Array ? dv.getInt8(p) : dv.getUint8(p)); }
  return { d: out, n };
}
function meshData(g, mi) {
  const m = g.j.meshes[mi], p = m.primitives[0], P = acc(g, p.attributes.POSITION), N = acc(g, p.attributes.NORMAL), U = acc(g, p.attributes.TEXCOORD_0), I = acc(g, p.indices);
  const n = P.n, mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9]; for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) { mn[c] = Math.min(mn[c], P.d[i * 3 + c]); mx[c] = Math.max(mx[c], P.d[i * 3 + c]); }
  const um = [1e9, 1e9], ux = [-1e9, -1e9]; for (let i = 0; i < n; i++) for (let c = 0; c < 2; c++) { um[c] = Math.min(um[c], U.d[i * 2 + c]); ux[c] = Math.max(ux[c], U.d[i * 2 + c]); }
  const pq = new Uint16Array(n * 3), nq = new Int8Array(n * 3), uq = new Uint16Array(n * 2);
  for (let i = 0; i < n; i++) { for (let c = 0; c < 3; c++) { const r = mx[c] - mn[c] || 1; pq[i * 3 + c] = Math.round((P.d[i * 3 + c] - mn[c]) / r * 65535); nq[i * 3 + c] = Math.round(N.d[i * 3 + c] * 127); } for (let c = 0; c < 2; c++) { const r = ux[c] - um[c] || 1; uq[i * 2 + c] = Math.round((U.d[i * 2 + c] - um[c]) / r * 65535); } }
  const idx = n > 65535 ? new Uint32Array(I.d) : new Uint16Array(I.d);
  return { n, mn, mx, um, ux, p: b64(pq), nr: b64(nq), uv: b64(uq), i: b64(idx), i32: n > 65535 ? 1 : 0 };
}
const out = { models: {}, tex: null }; let texHash = null, total = 0;
for (const name of MODELS) {
  const g = readGlb(path.join(dir, name + '.glb')), nodes = g.j.nodes, byName = Object.fromEntries(nodes.map(n => [n.name, n]));
  const img = g.j.images[0], bv = g.j.bufferViews[img.bufferView], png = g.bin.slice(bv.byteOffset || 0, (bv.byteOffset || 0) + bv.byteLength), h = crypto.createHash('md5').update(png).digest('hex');
  if (!out.tex) { out.tex = 'data:image/png;base64,' + png.toString('base64'); texHash = h; } else if (h !== texHash) console.warn('texture differs:', name, h);
  const wf = meshData(g, byName['wheel-front-right'].mesh), wb = meshData(g, byName['wheel-back-right'].mesh), body = meshData(g, byName['body'].mesh);
  const same = wf.p === wb.p;
  out.models[name] = { body, bodyPos: byName['body'].translation || [0, 0, 0], wf, wb: same ? null : wb, wpos: { fr: byName['wheel-front-right'].translation, br: byName['wheel-back-right'].translation } };
  console.log(name, 'verts', body.n, 'wheelSame', same, 'wheelPos', JSON.stringify(out.models[name].wpos), 'bodyPos', JSON.stringify(out.models[name].bodyPos), 'bb', body.mn.map(v => +v.toFixed(2)), body.mx.map(v => +v.toFixed(2)));
}
const js = '// 자동 생성(tools/convert-cars.mjs). Kenney Car Kit 3.1, CC0 (www.kenney.nl)\nexport const CAR_TEX = ' + JSON.stringify(out.tex) + ';\nexport const CAR_MODELS = ' + JSON.stringify(out.models) + ';\n';
fs.writeFileSync(OUT, js); console.log('written', (js.length / 1024).toFixed(0) + 'KB');
