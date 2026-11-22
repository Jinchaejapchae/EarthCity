// 로컬 확인용 정적 서버: node tools/serve.mjs  ->  http://localhost:5173
import http from 'http'; import fs from 'fs'; import { fileURLToPath } from 'url'; import path from 'path';
const f = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'dist', 'index.html');
http.createServer((q, r) => { r.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); fs.createReadStream(f).pipe(r); }).listen(5173, () => console.log('http://localhost:5173'));
