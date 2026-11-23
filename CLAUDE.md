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

## v0.6 사람 모델 개선
- `pedBuild`: 7.5등신 비율, 스플라인 lathe 곡면 몸통/팔다리, 목/어깨/손(손가락·엄지)/신발(밑창), 얼굴(눈·눈썹·코·입술·귀), 머리 4종(짧은/긴/묶음/삭발풍) + 두개골 삼각형으로 만든 머리선, 안경, 깃/벨트/밑단/소매/코트/치마/배낭. 허리·목·어깨·팔꿈치·무릎은 두 뼈에 가중치를 나눠 굽혀도 안 찢어짐. 구운 AO(vertex color). 화질별 분할 수(low 8/mid 10/high 14). draw call 은 사람당 1개 그대로.
- 뼈 위치/비율이 바뀜(`makePerson`): 어깨 x±0.225, 힙 x±0.095, 머리뼈=목 밑(y1.6). 코트/치마는 힙 뼈에 고정이라 큰 보폭에서 다리가 살짝 비침.

## Godot 이식 (2026-11, `godot/` 폴더, 웹 버전과 별개)
- 엔진: Godot 4.7.2 (winget `GodotEngine.GodotEngine`, 콘솔 실행 파일은 `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.2-stable_win64_console.exe`). Forward+, GDScript(코드만으로 씬 구성, `main.tscn` 은 스크립트 하나만 붙임).
- 1단계(수직 슬라이스) 완료: 8×8 격자 도시(`scripts/city.gd`: 절차적 창문 텍스처+야간 emission, 차선/횡단보도 SurfaceTool, 경사 턱 인도), Kenney 차 10종 GLB(`assets/cars`, CC0), 걷기/차 탑승 운전(`player.gd`, `car.gd`), 물리 하늘+ACES+SSAO+글로우, 시간 키 T.
- 스크린샷 검증: `godot --path godot -- --shot=out.png --cam=x,y,z,tx,ty,tz [--hour=h]` (150프레임 후 저장·종료). 새 에셋을 넣으면 `godot --headless --path godot --import` 한 번.
- 좌표: Godot 는 -Z 가 앞. Kenney 모델은 +Z 가 앞이라 car.gd 에서 180도 회전.
- 다음: 실사 사람 GLB(뼈대+걷기), 교통 AI/NPC, 가로등/나무 디테일, 날씨/실시간 시간/OSM 이식, 차 실사 모델.
- 사람(2단계): Mixamo 캐릭터 `godot/assets/people/character.fbx`(뼈 65개 `mixamorig9_*`, 텍스처 8장 ≈50MB — git 에 올릴 땐 LFS 필요) + 애니메이션은 FBX 에서 `scripts/extract_anim.gd -- <fbx이름> <저장이름>` 으로 `anim_<이름>.res` 만 뽑아 쓰고 FBX 는 지움(텍스처 중복 방지). `player.gd` 가 AnimationLibrary "g" 로 붙임. Mixamo 재질은 알파 0.8+깊이선처리라 `_fix_materials` 로 불투명화(속눈썹/머리카락만 scissor). 현재 애니메이션: standing_up 만(걷기/달리기/서있기 아직 없음).

## Godot 3단계: 실제 세계 지도 월드 (godot/scripts)
- 임시 격자 도시(city.gd)는 삭제. 이제 `world.gd` 가 플레이어 주변 z14 타일 3x3 을 스트리밍: 지형=Terrarium 고도(AWS s3 elevation-tiles-prod, PNG), 도로/건물/물/토지=OpenFreeMap 벡터 타일(https://tiles.openfreemap.org/planet TileJSON → .pbf, 무료/키 없음, 원본 비압축). 디스크 캐시 `user://cache`.
- 구성: `geo.gd`(위경도↔메르카토르↔로컬; 로컬 +x 동/-z 북, 원점=선택 위치, k=cos(lat)), `net.gd`(HTTP+캐시), `mvt.gd`(.pbf 디코더; 함정: _value() 가 pos 를 end 로 옮기니 호출 쪽에서 또 더하면 값이 첫 번째만 읽힘), `chunk_builder.gd`(스레드: 지형 128x128 격자+색(landcover/landuse/park)+물 carve+스커트, 도로 스트립(등급별 높이차로 z-fight 완화, 다리=끝점 보간, 터널 생략), 건물 압출+지붕+충돌 faces, 물 폴리곤 삼각분할), `wmats.gd`(재질), `world.gd`(청크 생성/삭제, `height_at`, 충돌: HeightMapShape3D + 건물 ConcavePolygonShape3D).
- 검색: Open-Meteo 지오코딩(한국어, 무료). Nominatim 은 이 PC 에서 연결 안 됨. 키 `/` 로 검색창, Enter 로 이동(`_go`). 테스트: `--ll=lat,lon --cam=x,y,z,tx,ty,tz`(y 는 지면 기준 상대) `--frame=N --shot=out.png`.
- 알려진 한계/TODO: 스폰이 연못/건물 안일 수 있음(도로 위로 보정 필요), 원점 재설정(멀리 가면 정밀도) 미구현, 청크 경계 물 높이 단차, 차/NPC 는 아직 도로 AI 없음(2단계), 나무/가로등/신호 없음, 건물 외관은 높이만 반영(상자+창문), 날씨/실시간 시간 미이식.
- 사람 애니메이션(Godot): 원본 FBX 는 `godot/assets/people/src/`, `scripts/extract_anim.gd`(인자 없이 실행)가 전부 `anim_<이름>.res` 로 뽑으면서 Hips 루트 모션(x,z)을 제거하고 idle/walking/drunk_walk 는 루프로 설정. 보유: standing_up, idle, walking, drunk_walk, left/right_turn, walk_to_stop, run_to_stop, running_to_turn. `player.gd` 가 이동 속도/STRIDE 로 재생 속도를 맞춰 걷기 재생(달리기 전용 루프가 없어 걷기를 빠르게), 도착 시 standing_up, G 키 술취한 걸음. 새 애니메이션 추가: src 에 FBX 넣고 `godot --headless --path godot --import` 후 extract_anim 실행, player.gd 의 ANIMS 에 이름 추가.
- 테스트 플래그: `--walk`(자동 전진) `--walk=run`, `--frame=N`(로딩 후 N프레임에 스크린샷).
- Godot 2단계(교통): 청크 빌더가 도로선(3m 간격 3D 점, 도로 윗면 y, 다리 보간)을 `out["net"]` 으로 내보내고 `roadnet.gd` 가 월드 도로 그래프로 이어 붙임(다른 선의 점이 3.2m·높이차 3m 안이면 같은 노드=교차로, 일방통행 `oneway` 반영, 청크 언로드 시 노드 삭제 — 간선은 소비 쪽에서 `nodes.has` 로 검사). `npc_car.gd`(AnimatableBody3D, 우측통행, 교차로 직진 선호, 코너 감속, 앞차/플레이어 감지 감속) `npc_ped.gd`(Mixamo 캐릭터, 도로 폭/2+1.6m 옆 인도쪽, 140m 밖 비표시) `traffic.gd`(플레이어 70~380m 에 차 26대/보행자 14명 유지, 520m 밖 삭제). 플레이어 스폰은 가장 가까운 도로 옆(`main._on_center_ready`)이고 내 차는 그 도로 차선 위. 키: Shift=달리기(running 애니), C=박수, G=술취한 걸음.
- 알려진 한계: 교차로 신호/양보 없음(차끼리 겹쳐 지나감), 보행자-차 충돌 없음, 좌측통행 국가 미반영(`npc_car.side`), 터널 도로 제외, 도로 폭 정보만 있고 차선 수 무시.
- Godot 3단계(세계 지도 화면): `worldmap.gd`(Control, M 키). 슬리피 맵 직접 구현(타일 캐시 `net.fetch`, 확대 중엔 낮은 줌 타일을 늘려 임시 표시, 휠=커서 기준 확대, 드래그 이동, 클릭=선택, 더블클릭/[여기로 이동]=`chosen(lat,lon,name)` → `main._go`). 타일: `tile.openstreetmap.de`(OSM 공식 .org 는 이 PC 에서 연결 안 됨, CARTO 는 이제 API 키 필요, Stadia 401). 검색은 Open-Meteo 지오코딩 5건 버튼, 대륙별 주요 도시 17개 빠른 이동 버튼. 테스트: `--map=<줌>`(로딩 후 지도 열기). 타일은 서버 속도 때문에 한꺼번에 안 차고 점점 채워짐.
- Godot 4단계(하늘/시간/날씨/밤): `atmos.gd` 가 담당. 시간=선택한 장소의 현재 시각(NOAA `solar_pos`, 장소 UTC 오프셋은 Open-Meteo `timezone=auto`) → 태양/달 DirectionalLight(달은 별도 라이트, 그림자 없음), ProceduralSkyMaterial 색(낮/노을/밤/흐림), 별(POINTS 메시), 앰비언트. 날씨=Open-Meteo 현재값(weather_code/cloud_cover/precipitation/wind) → 구름/비/눈/안개/뇌우(번개 앰비언트 번쩍). 비/눈=GPUParticles3D(카메라 추종), 젖은 노면(`wmats.set_weather`: 거칠기↓/어둡게), 눈 덮임은 emission 으로 흉내. 키: T=시간 고정 순환(실시간→06:30→12:00→18:30→00:00), K=날씨 수동 순환(실시간/맑음/구름/비/눈/안개/뇌우, 수동 중엔 실시간 값이 안 덮음). 테스트: `--tm=N --wx=N`. 가로등: 청크 빌더가 도로선을 따라 42m(major)/56m(minor) 간격으로 위치를 내보내고 world 가 MultiMesh(기둥+발광 전구) + 노면 빛 무리(가산 쿼드)로 그림. 차 전조등/후미등: `lights.gd`(발광 구 + 노면 빛 타원, 내 차만 SpotLight 2개). 좌측통행: BigDataCloud 역지오코딩 countryCode ∈ LEFT_HAND → `traffic.side=-1`(NPC 차 차선 반대편), 지명 표시도 여기서. 
- 함정 모음: 스폰 시 카메라가 내 차 안에 들어가 화면이 막히던 문제 → 시작 yaw 를 차 방향으로. 스폰 위치는 `world.inside_building`(청크별 건물 폴리곤)으로 건물 안을 피함. 카메라는 건물 안이면 거리 단축 + 레이캐스트로 지형/건물 충돌. 물 수면 높이는 타일 경계 점을 빼고 낮은 쪽 25% 값(경계에 걸친 육지 때문에 수면이 언덕 높이에 뜨던 문제).
- Godot 소리(`scripts/sfx.gd`): 외부 음원 없이 전부 코드로 합성(AudioStreamWAV 16비트 22.05kHz). 엔진(36Hz+배음 9개, 정수 주기라 1초 루프 이음매 없음, pitch_scale 로 RPM) / 타이어 / 경적(H) / 충돌(속도 급감 감지) / 문 닫기(탑승·하차) / 발소리 3종(걷기 0.75m, 달리기 1.15m 보폭) / 비 / 바람 / 천둥(atmos.lightning 시그널 후 0.4~2.8초 지연) / 도시 웅웅(도로 거리 비례) / 새소리 3종(낮, 도로에서 35m+, 3D). NPC 차는 가까운 10대(70m 이내)에만 3D 엔진음(`EngineSfx` 노드)을 붙였다 뗌. N=음소거. 확인: `--dump-sfx=<폴더>` 로 WAV 12개 저장(파형 분석/청취용). 이 PC 는 오디오 장치가 없어(WASAPI 초기화 실패 → 더미 드라이버) 실제로 들어 보지는 못했고 파형 수치만 검증함 → 음량/음색은 사용자 피드백으로 조정. 음량 상수는 sfx.update 안(`_db(...)` 호출부).
- Godot 신호등/교통 규칙: `signals.gd`(청크 단위 증분 — 서울 17만 노드에서 한 번에 계산하면 0.6초 끊겨서 청크당 30~45ms 로 분산) 가 도로 그래프에서 3갈래 이상 갈라지는 노드(큰 도로 포함)를 22m 안에서 묶어 교차로로 만들고 접근 방향을 두 위상으로 나눠 신호(초록 17s/노랑 3s/전적색 2.5s, 주기 46s, 교차로마다 오프셋)를 돌림. `signal_view.gd`(260m 안 교차로에만 신호등 기둥+3색 등, 상태 바뀔 때만 재질 교체, 밤엔 발광 강화, 좌측통행이면 반대편 기둥). `traffic.junction_ahead(car)` 가 차의 앞 경로 75m 를 훑어 첫 교차로를 찾고(도로 점이 3m 간격이라 현재 간선만 보면 안 됨!) 차는 0.15초마다 갱신: 신호면 정지선 6m 앞에서 감속도 3.5 로 정지(노랑은 멈출 수 있을 때만), 신호 없는 3갈래 교차로는 큰 도로 우선/같은 등급이면 오른쪽 차 우선(`traffic.side` 로 좌측통행 반전)으로 양보, 6초 기다리면 교착 방지로 진행. 검증(서울 2400프레임, `--sigdbg`): 신호 접근 517건, 빨강 대기 205건(최대 4대 동시), 신호 위반 0건. 한계: 보행자 횡단/보행 신호 없음, 좌우회전 구분 없음(직진 위상과 함께 감), 교차로 안에서 차끼리 충돌 회피는 양보 규칙 수준.
- Godot 횡단보도: `signal_view._zebra` 가 각 교차로 팔의 입구 노드(`arm.base`)에서 1.5m 바깥에 얼룩말 무늬(폭 0.45m 간격 0.95m, 길이 2.4m)와 5m 바깥에 정지선(들어오는 차선 쪽 절반)을 지형 높이 +0.27m 로 그림(차 정지 위치 = 입구 노드 6m 앞이라 차 앞부분이 횡단보도 전에 섬). 보행자(`npc_ped.gd`): 신호 교차로 팔에 닿으면(`_entry_arm`) 60% 확률로 건너고 싶어함 → 연석에서 idle 로 대기 → 그 팔의 차 신호가 빨강이고 초록까지 `cross_dur+1.5`초 이상 남았을 때 출발, 횡단 중 초록으로 바뀌면 1.8배 속도, 36초 넘게 기다리면 포기. 횡단 폭 = 도로폭+3.2m, 속도 1.5m/s. 차는 `speed_limit_for` 에서 앞 14m 의 같은 차선(횡방향 2.3m 이내) 보행자 앞에서 정지. 보행자 스폰의 절반은 신호 교차로 22m 밖에서 교차로 쪽으로 걷게 함. 검증(서울 3600프레임): 횡단 42/177 샘플, 동시 최대 2명. 한계: 보행자 신호등 없음(차 신호로 판단), 횡단보도가 겹치는 Y자 교차로는 무늬가 겹쳐 지저분, 플레이어는 신호를 어겨도 반응 없음.
- Godot 건물 외관 개선(`chunk_builder.gd` 건물/나무 구간, `wmats.gd`, `world.gd`): ① 벽: 층 높이 3.2m, 벽 한 면의 창 개수를 정수로(길이/3m) 맞춰 UV 를 잡아 창이 잘리지 않음. 높이 9m+ 비주택은 1층 4.2m 상가 띠(간판 3색 + 쇼윈도, 밤엔 쇼윈도/간판 발광, 타일 가로 5m). 건물마다 정점 색(`_tint`)으로 밝기/색조 변화(재질에 `vertex_color_use_as_albedo`). ② 지붕: 높이 12m 이하·면적 450㎡ 미만·꼭짓점 14개 이하 건물은 4면 경사 지붕(중심 꼭짓점 팬, 지역별 기와/슬레이트/붉은색), 14m+·180㎡+ 평지붕은 옥상 설비 상자 1~2개. ③ 지역 팔레트(`wmats.region_of` 위경도 박스: 0 일반/1 동아시아/2 유럽/3 중동·지중해/4 아메리카/5 북유럽) 6종 파사드(4,5 는 공통 유리/오피스 타워, 45m+ 는 유리). 재질은 지역별 지연 생성, `all_mats` 로 밤 발광 일괄 제어. ④ 나무: 가로수(큰 도로 양쪽 15m, 작은 도로 번갈아 19m, 도로 폭/2+2.6m, 다리 제외), 숲(landcover wood/forest 6.5m 격자)/공원/묘지 격자+지터. 도로·건물·물 위는 피함(`_blocked`: 12m 도로점 해시 + 40m 건물 bbox 해시). 청크당 상한 1500그루, MultiMesh 3개(줄기/활엽수 잎(구 2개)/침엽수 잎(원뿔 3개)), 인스턴스 색=잎 색, 그림자 끔, 650m 밖 비표시. 계절(`_season_of`: 시스템 날짜+위도; 남반구는 6개월 이동, 북위/남위 23도 안은 항상 초록): 봄 연두/여름 초록/가을 주황·노랑·갈색 섞임/겨울 앙상한 작은 갈색 덩어리. 침엽수 비율 12%(북유럽 60%, 숲 +25%, 열대 3%).
- 성능 메모: 서울 시청(최고밀도)에서 1280x720 33fps(Intel UHD 770, 그림자+SSAO+MSAA), 나무 유무와 무관. 청크 하나 생성 2~3.4초(백그라운드 스레드). `--fps` 플래그로 FPS 출력.
- Godot 프로그램 제목: "EARTH CITY"(`godot/project.godot` config/name, HUD 첫 줄). 사용자 데이터 폴더(지도 타일 캐시 `user://cache`)는 `config/use_custom_user_dir` 로 예전 이름 "ULSAN CITY" 를 유지해서 제목을 바꿔도 캐시가 사라지지 않음. 웹 버전(`src/`)은 아직 "ULSAN CITY" 그대로.
- Godot 추가 작업(2026-11, 사용 한도로 중단): 설정 저장(`settings.gd`, user://settings.cfg: 마지막 위치/음량/화질), ESC 일시정지 메뉴(`menu.gd`: 음량, 음소거, 그림자, SSAO, 나무, 전체화면, MSAA, 해상도 배율, 교통량), 불러오는 중 화면(진행 n/9), 게임패드(스틱/트리거/X·Y·Start), 달 위상·위치(`atmos._update_sky_objects`, 확인됨), 구름 돔 셰이더(sin 해시를 정수형 해시로 바꾸고 지평선 근처(dir.y<0.06)를 잘라 줄무늬 해결(밤 스크린샷 확인, 낮 미확인)), 물결 법선맵 애니메이션(미확인).
- 남은 일 처리(2026-11-23): 나무 충돌(world._tree_colliders: 플레이어 12m 안 나무에만 풀 48개 원기둥, 0.4초마다), 바람 흔들림(wmats.TREE_SHADER, 풍속 -> set_wind), 보행자 신호등(signal_view: 기둥에 양면 적/녹 등, 차 신호 빨강=보행 녹색), 달리기/걷기 정지 애니메이션(player.gd), NPC 차 색 변형(npc_car._tint), 8km 이상 멀어지면 새 원점으로 다시 불러오기(main._process), 세계지도 [IP로 내 위치](ipwho.is, 누를 때만 요청). 저장소: origin=Jinchaejapchae/EarthCity, Git LFS(godot/assets/people 의 fbx/png/res)로 푸시 완료(lfs.url 에 Jinchaejapchae@ 필요, locksverify false). .gitignore 의 *.png 때문에 godot 텍스처는 !godot/assets/**/*.png 로 예외.
- 남은 일: Windows 내보내기(템플릿 1.3GB 내려받는 중, D:Claude	pl), 낮 구름/물결 확인, 구름 윗부분 조정.

- 로딩 속도 개선(2026-11-23): 벡터+고도 타일 동시 요청(world._load), 동시 HTTP 16, 가운데 타일 우선(거리순) + 주변 타일 건물 생성은 가운데가 끝난 뒤 시작, _instantiate 를 프레임 나눠 실행(끊김 감소). 처음 가는 도시에서 가운데 타일 표시까지 8~10초 -> 약 5초(시작 포함). T/K 키(시간/날씨 수동)는 제거 — 항상 현지 실시간. 맥 내보내기: 프리셋 macOS(universal, 서명 없음, ETC2/ASTC 필요), 내려받은 앱은 xattr -cr + codesign --force --deep -s - 필요, 릴리스 mac-v1.0(Jinchaejapchae/EarthCity). gh 는 dr0561 로그인이라 릴리스는 GH_TOKEN 에 Jinchaejapchae 자격증명을 넣어 사용.

- 지역 특색(2026-11-23, `style.gd`): region 13종(0 일반 1 동아시아 2 서유럽 3 지중해·북아프리카 4 북미 5 북유럽 6 남아시아 7 동남아 8 중남미 9 사하라이남 10 오세아니아 11 러시아·동유럽 12 아라비아·이란)별 파사드 팔레트(wmats.PALETTES)·경사지붕 색(ST.ROOF)·경사지붕 비율(ST.PITCH, 중동/인도는 거의 평지붕)·NPC 차 색 분포(ST.CAR_COLORS, 한국/일본/중국/인도는 흰색·은색 위주). biome 6종(0 온대 1 열대 2 사막 3 지중해성 4 냉대 5 극지)을 위경도 박스로 판정(biome_of)해 땅/잔디/숲/농지/공원 색, 물 색, 눈선(5000-|위도|*60 m)·수목한계, 나무 종류(열대/사막 야자 = 나무 kind 2, 사막은 관목·성기게, 지중해 사이프러스, 냉대 침엽수 위주, 극지 나무 없음)를 바꿈. 야자 = 줄기(세로로 늘린 일반 줄기) + 처진 잎 8장 MultiMesh. 한계: 위경도 박스는 거친 근사(경계 도시는 어색할 수 있음), 건물 형태 자체(랜드마크)와 간판 글자·보행자 옷은 아직 지역별 구분 없음.

- 지역 특색 2차(2026-11-23): ① 보행자 옷/피부(npc_ped.PED_SHADER: Mixamo 몸 텍스처의 어두운 무채색 부분을 상의/하의 색으로(ny<0.5 하의), 주황 계열 픽셀을 피부색 배수로; style.ped_look 지역별 옷 팔레트·피부 분포, 아라비아는 흰 긴 옷). 플레이어는 원본 그대로. ② 상가 간판 글자(world._apply_signs: SubViewport+Label 한 번 그려 알파를 wmats.apply_sign 으로 간판 띠에 얹음, style.sign_words 지역 언어: 한/일/중/영/프/독/이/스/포/러/아랍/힌디/태국/베트남/인니). 글자 뒤집힘은 shop 벽 u 를 sgn>0 일 때 반대로 해서 해결. ③ 랜드마크 26개(landmarks.gd: 에펠/도쿄타워/피라미드3/빅벤/오페라하우스/타지마할/아야소피아/성베드로/콜로세움/스페이스니들/CN/베를린TV/동방명주/개선문/브란덴부르크/게이트웨이/성바실리/피사/자유의여신상/구세주상/파르테논/사그라다/국회의사당/타워브리지). 실제 위경도 타일의 _instantiate 에서 세우고(박스 충돌 solid), 그 반경(RADIUS) 안의 지도 건물은 chunk_builder.skip 으로 제외. 새 랜드마크는 LIST 에 줄 추가 + build() 에 종류 추가.

- 위성사진(2026-11-23): 타일마다 Sentinel-2 구름 없는 모자이크(https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/g/{z}/{y}/{x}.jpg, z14, 256px ≈ 10m/px, 키 없음, CC BY-NC-SA — 비상업, 메뉴 하단에 출처 표기)를 벡터/고도와 동시에 받아(world._load res[2]) 지형 UV(0..1)에 입힘. wmats.SAT_SHADER(타일별 ShaderMaterial, 노이즈 디테일 곱, 물 칸은 정점 알파 0 으로 제외, 비/눈은 전역 셰이더 값 g_wet/g_snow 로 wmats.set_weather 가 갱신). 사진이 없으면 예전 정점색 지형(기후 색)으로 대체. 건물 지붕 색은 위성 색을 절반 섞음(chunk_builder._roof_color, sat 샘플). 한계: 10m 해상도라 건물 벽/차선은 없음, 위성 합성 시점(2021) 기준이라 최신 건물과 안 맞을 수 있음, 구름 없는 합성이라 현재 날씨/계절과 무관(겨울 눈은 산지만 반영).

- 도로/NPC/건물 보정(2026-11-23): 도로 띠가 중심선 높이로 평평해서 경사면에서 땅에 묻히거나 뜨던 문제 -> 띠를 3열(좌/중/우)로 만들고 가장자리마다 지형 높이를 따름(chunk_builder._strip). NPC 차는 차선 위치의 지형 높이+리프트로 배치(다리는 노드 높이 유지, npc_car._place). 경사 지붕은 볼록 다각형에만(_is_convex), 지붕 삼각분할 실패 시 뒤집어 재시도/부채꼴 대체. 남은 한계: OSM building:part 겹침으로 인한 z-파이팅, 가파른 경사지 건물이 반쯤 묻혀 보임. 위성사진 요청은 8초 제한(optional fetch), 로딩 화면에 경과 초 표시, 테스트 플래그 --hop=lat,lon(첫 로딩 후 재이동).
