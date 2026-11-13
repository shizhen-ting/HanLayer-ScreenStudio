const fs = require('fs');
const path = require('path');
const R = path.resolve(__dirname, '..');
const STAGE = process.env.SS_STAGE ? path.resolve(process.env.SS_STAGE) : path.join(R, 'extracted');

// 1) merge dictionary
const dict = {};
for (const f of fs.readdirSync(path.join(R, 'build/out')).filter(f => f.endsWith('.json'))) {
  const d = JSON.parse(fs.readFileSync(path.join(R, 'build/out', f), 'utf8')).translations || {};
  for (const [k, v] of Object.entries(d)) dict[k] = v;
}
const base = path.join(R, 'build/dict-extra.json');
if (fs.existsSync(base)) Object.assign(dict, JSON.parse(fs.readFileSync(base, 'utf8')));
// drop entries that are pure code/CSS leftovers
for (const k of Object.keys(dict)) {
  if (typeof dict[k] !== 'string' || !dict[k].trim()) delete dict[k];
}
fs.writeFileSync(path.join(R, 'build/dict.json'), JSON.stringify(dict, null, 0));

// 2) renderer bundle: core + dict + patterns
const core = fs.readFileSync(path.join(R, 'build/zh-core.js'), 'utf8');
const patternsFile = path.join(R, 'build/patterns.json');
const patterns = fs.existsSync(patternsFile) ? JSON.parse(fs.readFileSync(patternsFile, 'utf8')) : [];
const prelude = `window.__SS_ZH_DICT__=${JSON.stringify(dict)};window.__SS_ZH_PATTERNS__=${JSON.stringify(patterns)};`;
fs.writeFileSync(path.join(STAGE, 'dist/zh.js'), prelude + core);

// 3) patch index.html once
const htmlPath = path.join(STAGE, 'dist/index.html');
let html = fs.readFileSync(htmlPath, 'utf8');
if (!html.includes('zh.js')) {
  html = html.replace('</head>', '    <script src="./zh.js"></script>\n  </head>');
  fs.writeFileSync(htmlPath, html);
}

// 4) main process dictionary + shim
const mainDict = {};
for (const [k, v] of Object.entries(dict)) mainDict[k.replace(/\s+/g, ' ').trim()] = v;
fs.writeFileSync(path.join(STAGE, 'dist-electron/zh-dict.json'), JSON.stringify(mainDict, null, 0));
// 4a) standalone renderer bundle for main-process injection
fs.writeFileSync(path.join(STAGE, 'dist-electron/zh-renderer.js'), prelude + core);

// 4b) preload shim (covers child windows rendered without index.html)
const preloadPath = path.join(STAGE, 'dist-electron/preload.js');
if (!fs.existsSync(path.join(R, 'build/preload.js.orig'))) fs.copyFileSync(preloadPath, path.join(R, 'build/preload.js.orig'));
const origPreload = fs.readFileSync(path.join(R, 'build/preload.js.orig'), 'utf8');
const preloadShim = '\n/* zh-cn preload layer */\n' + prelude + core + '\n';
fs.writeFileSync(preloadPath, origPreload + preloadShim);

const idxPath = path.join(STAGE, 'dist-electron/index.js');
if (!fs.existsSync(path.join(R, 'build/index.js.orig'))) fs.copyFileSync(idxPath, path.join(R, 'build/index.js.orig'));
const origIdx = fs.readFileSync(path.join(R, 'build/index.js.orig'), 'utf8');
if (!origIdx.includes('zh-main')) {
  const shim = fs.readFileSync(path.join(R, 'build/zh-main.js'), 'utf8');
  fs.writeFileSync(idxPath, shim + '\n' + origIdx);
}

console.log('dict entries:', Object.keys(dict).length, 'patterns:', patterns.length);
