# ULSAN CITY — GTA 스타일 오픈월드 브라우저 게임

해 질 녘 항구 도시를 배경으로 한 3D 오픈월드 게임 프로토타입입니다. Three.js로 만들었고, 빌드하면 HTML 파일 하나로 나와요(`dist/index.html`). 폰과 PC 브라우저에서 바로 돌아갑니다.

## 명령어
- `npm install`
- `npm run build`: `src/main.js`를 esbuild로 번들한 뒤 `src/index.html`의 `/*BUNDLE*/` 자리에 인라인해서 `dist/index.html`을 만듭니다.
- `npm test`: 빌드한 다음 헤드리스 Chrome(puppeteer-core)으로 스모크 테스트를 돌리고 `shot*.png` 스크린샷을 남깁니다. Chrome 경로는 `CHROME_PATH` 환경변수로 바꿀 수 있어요. 모바일 뷰포트로 테스트하려면 `node tests/smoke.mjs m`.
- 디버그 훅: `window.__game`(player, cars, peds, stars, crime(), startGame(), keys, input), `window.__fps`

## 구조 (src/main.js, 섹션 주석 기준)
- **world**: 8×8 블록 그리드입니다. `N=8, R=14`(도로 폭), `B=60`(블록), `P=74`(블록 간격). 노드(i,j)는 `(i*P, j*P)`이고, 블록 종류는 bld/park/lot이에요. 같은 재질끼리 지오메트리를 `buckets`에 모아 merge해서 드로우콜을 줄였어요. 충돌용 AABB는 `colliders[bi + bj*N]`에 들어 있습니다.
- **좌표 규칙**: heading `h=0`이면 +z 방향이고, `fwd=(sin h, cos h)`, `right=(-cos h, sin h)`예요. 우회전하면 h가 감소합니다. 우측통행이고 차선 오프셋은 `LANE=3.5`.
- **cars**: 아케이드 물리(`integrateCar`)를 씁니다. 앞뒤 원 2개로 충돌을 처리해요(`carWorld`, `carCar`, `carBodies`). AI 모드는 `traffic`(차선 추종)과 `chase`(경찰, 노드 단위 탐욕 경로, 34m 안이면 직접 추격) 두 가지예요.
- **peds**: 블록 둘레 인도를 따라 걷습니다(`perim`). 상태는 walk/flee/dead.
- **수배**: heat 포인트가 쌓이고, 별 기준값은 `TH=[1,8,20,40,70]`이에요. 경찰 수는 `COPS_FOR`로 정하고, 시야에서 벗어나 있으면 별이 줄어듭니다. 잡히면 BUSTED, 죽으면 WASTED.
- **미션**: 택배 픽업(파란 표시)에서 제한시간 안에 배달(노란 표시)하면 돈을 벌어요. 돈은 localStorage `ulsan_money`에 저장됩니다.
- **HUD/입력**: 회전 미니맵, 별, 체력. 모바일은 왼쪽 화면이 가상 조이스틱이고 오른쪽 드래그가 시점이에요. PC는 WASD, E, Space, Shift, 마우스 드래그.

## v0.2 그래픽 개선 (사용자 요청: "실사 비슷하게") — 1~12 전부 구현 완료, 번들 약 1100KB
목표는 박스 장난감 느낌을 벗어나 반사, 조명, 재질감이 있는 3D로 바꾸는 거예요. 성능은 v0.1에서 폰이 버벅이지 않았으니 그 수준을 유지해야 합니다.

1. **품질 단계**(low/mid/high, localStorage `ulsan_q`, 기본값은 터치 기기 mid, PC high). HUD에 화질 버튼을 둡니다.
2. **렌더러**: `ACESFilmicToneMapping`. 참고로 `PCFSoftShadowMap`은 three 0.187에서 제거됐으니 PCFShadowMap을 쓰세요.
3. **후처리**: EffectComposer → (high: `N8AOPass`(npm `n8ao`, RenderPass 대체, `configuration.gammaCorrection=false`) / 나머지: RenderPass) → `UnrealBloomPass` → `OutputPass`. low에서는 composer 없이 바로 렌더합니다.
4. **하늘**: `three/examples/jsm/objects/Sky.js`. 카메라 far가 900이라 sky는 scale 약 420으로 두고, 매 프레임 카메라 위치를 따라가게 하고, `renderOrder=-1`로 설정하세요. 해 고도는 10~14°이고, DirectionalLight 방향도 해에 맞춥니다. fog 색은 지평선 색에 맞추세요.
5. **환경광/반사**: `@pmndrs/assets/hdri/sunset.exr`(CC0 Polyhaven, data URL)를 `EXRLoader`로 읽고 `PMREMGenerator.fromEquirectangular` 결과를 `scene.environment`에 넣습니다. 전부 MeshStandard/MeshPhysical로 교체하세요.
6. **건물**: 512px 절차적 PBR 텍스처(color, emissive, roughness+metalness 하나로 G=rough B=metal, 높이맵에서 만든 normal). 변형은 주거(창), 오피스(리본창), 유리 타워(반사), 벽돌 4종. 옥상 난간(parapet)도 추가합니다.
7. **도로/인도**: 512px 아스팔트(골재 노이즈, 균열, 닳은 차선, normal/roughness), 콘크리트 보도블록, 잔디 텍스처.
8. **가로등**: 블록당 8개(merge)를 두고 전구는 emissive로 블룸이 걸리게 합니다. 바닥에는 가짜 조명 웅덩이(additive 원형 그라데이션 평면)를 깔아요. 실제 PointLight는 쓰지 마세요.
9. **차 모델**: 옆면 프로필 Shape를 ExtrudeGeometry(bevel)로 뽑아 바퀴 아치가 있는 하부를 만들고, 유리 캐빈과 지붕을 올립니다. 도장은 MeshPhysical clearcoat, 바퀴는 타이어+림(회전, 앞바퀴 조향), 전조등/후미등은 emissive(브레이크 시 밝게). 경찰차는 vertex color로 위 흰색, 아래 검정 투톤.
10. **사람**: 캡슐 몸통, 구 머리, 팔다리 스윙. 몸통+머리는 ped마다 vertex color로 merge해서 메시 수를 줄입니다.
11. **나무/야자수**: icosahedron 클러스터(flatShading, 색 변화)를 쓰고, 야자수 잎은 처지는 판으로 만듭니다.
12. **물**: 낮은 roughness와 움직이는 노이즈 normal map으로 환경을 반사시킵니다.

그다음 후보: 스키드 마크, 배기/연기 파티클, 무기 추가, 라디오, 낮밤 사이클, 스토리 미션.

## 제약 / 메모
- 결과물은 단일 HTML(현재 약 580KB)이에요. 외부 3D 모델은 없고 전부 코드로 생성합니다. HDRI처럼 data URL로 인라인 가능한 CC0 에셋만 사용하세요.
- 헤드리스 swiftshader에서는 FPS가 15~27로 낮게 나와 실제 성능을 판단할 수 없어요. 실기기 체감은 사용자 피드백으로 확인합니다.
- UI 텍스트와 대화는 한국어로 합니다. 사용자는 짧고 구체적인 답을 선호해요.

## v0.3 추가 (그래픽 2차 + 날씨)
- **사람**: SkinnedMesh(뼈 11개, 사람당 draw call 1개). NPC 는 지오메트리 변형 풀 30개 공유. 무릎/팔꿈치 굽힘 걷기(`animLegs`).
- **건물**: 1층 상가(storefront 텍스처 4종) + 장식 띠, 계단식 상층부, 옥상 설비/물탱크/안테나, 주거/벽돌 건물 발코니(`addBalconies`).
- **차**: 문틈/손잡이/그릴/와이퍼/배기구, SUV 루프랙, 해치백 스포일러, 반투명 유리 너머 실내(좌석/대시보드/핸들) + 운전자(`driverM`, 운전자가 있을 때만 보임). 70m 밖은 불투명 유리로 교체.
- **날씨**: 울산 실시간 날씨(Open-Meteo, 키 불필요, 10분마다)를 받아 구름 돔/안개/비/눈/번개/젖은 노면/적설/바람(나무 흔들림, 파도)에 반영. HUD [날씨] 버튼으로 실시간 → 맑음/흐림/비/눈/안개/뇌우 수동 전환(`localStorage ulsan_w`). 오프라인이면 맑음.
- **디버그 훅**: `window.__weather.set(0~6)`, `window.__dbg`, `window.__camOv = {p:[x,y,z], t:[x,y,z]}` (카메라 고정). 해가 (-x,-z) 방향이라 반대쪽(+x,+z)을 보는 샷이 눈부심 없이 찍힘.

## v0.4 추가 (시간/위치/차 모델)
- **위치**: 브라우저 위치 권한(거부/실패 시 울산 기본). 소수 2자리로 반올림해 `localStorage ulsan_loc` 저장, 날씨 요청과 도시 이름 조회(bigdatacloud 역지오코딩)에만 사용. HUD [위치] 버튼 = 다시 확인.
- **시간**: `solarPos()`(NOAA 간이식)로 현재 시각의 태양 고도/방위 -> 하늘(Sky.js)/햇빛 방향·색/안개/하늘빛/별/달/가로등·창문·전조등 점등. 월드 +z=북, +x=동. HUD [시간] 버튼: 실시간/아침/낮/노을/밤/가속(1초=10분). `window.__time`.
- **차 모델**: Kenney Car Kit(CC0) 10종을 `tools/convert-cars.mjs`로 변환(`src/carModels.js`, 자동 생성). 팔레트 텍스처에서 도장 칸 UV를 바꿔 색을 바꿈(`K_PAINT`/`K_CELL`). 라이선스 `assets/KENNEY-LICENSE.txt`. 이전 절차적 차 모델 코드는 제거(git 기록 없음 — 필요하면 이 세션 대화 참고).
- **실제 지도(OSM) 건물/도로**: 아직 미구현. 격자 도시(교통 AI/보행자/충돌)를 갈아엎어야 하는 별도 대형 작업.

## v0.5 추가 (실제 지도 모드)
- 시작 화면 [맵] 버튼: 격자 도시 ↔ 내 주변(OpenStreetMap). OSM 선택 시 현재 위치 반경 450m의 도로/건물/공원/물을 Overpass API(무료, 키 불필요)로 받아 `localStorage ulsan_osm`에 캐시하고 새로고침해서 적용(`osmEnsure`). 실패/오프라인이면 격자 도시.
- 월드 생성은 `buildGrid()`(기존) / `buildOsmWorld(D)` 두 갈래. OSM 모드: 도로 그래프(`OSMG`, 노드/엣지/공간 셀) 위로 교통 AI(`osmAdvance`, `osmSnap`, `routeNode`), 보행자(`osmPerim`), 충돌(`pushOutOsm` 다각형), 미션 지점(`osmRoadSpot`)이 동작. 건물은 실제 외곽선 압출(높이는 height/levels 태그, 없으면 면적 기반 추정) + 1층 상가 텍스처.
- 한계: 한국은 OSM 건물 데이터가 성긴 곳이 많음(울산시청 주변은 450m 안에 건물 48개). 교량/고가/지하도/일방통행/신호등은 무시. 좌표는 Overpass/Open-Meteo/bigdatacloud 에 전송됨(소수 2자리).
- Google 지도는 API 키 + 약관(데이터를 게임 지형으로 재가공 금지) 문제로 사용하지 않음.
