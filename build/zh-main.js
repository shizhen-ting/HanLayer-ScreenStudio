/* Screen Studio 中文层 — 主进程 shim（仅做文案替换，不触碰业务逻辑） */
(() => {
  try {
    const fs = require('fs');
    const path = require('path');
    const electron = require('electron');
    const { app, Menu, dialog, BrowserWindow, Notification, Tray } = electron;
    let DICT = {};
    try { DICT = JSON.parse(fs.readFileSync(path.join(__dirname, 'zh-dict.json'), 'utf8')); } catch (e) {}
    const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
    const tr = (s) => {
      if (typeof s !== 'string' || !s) return null;
      const k = norm(s);
      if (Object.prototype.hasOwnProperty.call(DICT, k)) {
        const v = DICT[k];
        const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(s);
        return m[1] + v + m[3];
      }
      return null;
    };
    const trText = (s) => tr(s) || s;

    // ---- 菜单 ----
    const SUPPORTED_ROLES = new Set(['about','services','hide','hideOthers','unhide','quit','fileMenu','editMenu','viewMenu','windowMenu','help','recentDocuments','clearRecentDocuments','toggleDevTools','resetZoom','zoomIn','zoomOut','togglefullscreen','minimize','zoom','front','close','undo','redo','cut','copy','paste','pasteAndMatchStyle','delete','selectAll','startSpeaking','stopSpeaking','toggleTabBar','selectNextTab','selectPreviousTab','moveTabToNewWindow','mergeAllWindows','showSubstitutions','toggleSmartQuotes','toggleSmartDashes','toggleTextReplacement','toggleSpellChecker','showSpellChecker','speechMenu','shareMenu','windowMenu','appMenu','editMenu','viewMenu','fileMenu','help']);
    function translateTemplate(template) {
      if (!Array.isArray(template)) return template;
      return template.map((item) => {
        if (!item || typeof item !== 'object') return item;
        const out = Object.assign({}, item);
        if (typeof out.label === 'string') out.label = trText(out.label).trim();
        if (typeof out.sublabel === 'string') out.sublabel = trText(out.sublabel);
        if (typeof out.toolTip === 'string') out.toolTip = trText(out.toolTip);
        if (Array.isArray(out.submenu)) out.submenu = translateTemplate(out.submenu);
        return out;
      });
    }
    if (Menu && typeof Menu.buildFromTemplate === 'function') {
      const origBuild = Menu.buildFromTemplate.bind(Menu);
      Menu.buildFromTemplate = function (template) { return origBuild(translateTemplate(template)); };
    }
    if (Menu && typeof Menu.setApplicationMenu === 'function') {
      const origSet = Menu.setApplicationMenu.bind(Menu);
      Menu.setApplicationMenu = function (menu) {
        if (process.env.SS_DUMP_MENU) {
          try {
            const dump = [];
            const walk = (m, depth) => {
              if (!m) return;
              for (const it of m.items || []) {
                dump.push({ depth, label: it.label, role: it.role, type: it.type });
                if (it.submenu) walk(it.submenu, depth + 1);
              }
            };
            walk(menu, 0);
            fs.writeFileSync('/tmp/ss-menu.json', JSON.stringify(dump, null, 1));
          } catch (e) {}
        }
        return origSet(menu);
      };
    }

    // ---- 窗口标题 ----
    if (BrowserWindow && BrowserWindow.prototype && BrowserWindow.prototype.setTitle) {
      const origTitle = BrowserWindow.prototype.setTitle;
      BrowserWindow.prototype.setTitle = function (t) { return origTitle.call(this, trText(t)); };
    }

    // ---- 原生对话框 ----
    const trOptions = (opts) => {
      if (!opts || typeof opts !== 'object') return opts;
      const o = Object.assign({}, opts);
      for (const k of ['title', 'message', 'detail', 'buttonLabel', 'name']) {
        if (typeof o[k] === 'string') o[k] = trText(o[k]);
      }
      if (Array.isArray(o.buttons)) o.buttons = o.buttons.map(trText);
      if (Array.isArray(o.filters)) o.filters = o.filters.map((f) => (f && typeof f.name === 'string' ? Object.assign({}, f, { name: trText(f.name) }) : f));
      return o;
    };
    for (const m of ['showMessageBox', 'showMessageBoxSync', 'showOpenDialog', 'showOpenDialogSync', 'showSaveDialog', 'showSaveDialogSync', 'showErrorBox']) {
      if (dialog && typeof dialog[m] === 'function') {
        const orig = dialog[m].bind(dialog);
        dialog[m] = function (win, opts) {
          if (opts === undefined) { return orig(trOptions(win)); }
          return orig(win, trOptions(opts));
        };
      }
    }

    // ---- 系统通知 ----
    if (typeof Notification === 'function') {
      const Orig = Notification;
      const Patched = function (opts) {
        if (opts && typeof opts === 'object') {
          opts = Object.assign({}, opts);
          if (typeof opts.title === 'string') opts.title = trText(opts.title);
          if (typeof opts.body === 'string') opts.body = trText(opts.body);
        }
        return new Orig(opts);
      };
      Patched.prototype = Orig.prototype;
      Patched.isSupported = Orig.isSupported;
      global.Notification = Patched;
    }

    // ---- 菜单栏兜底：给 role 型标准菜单项补中文标签 ----
    try {
      const ROLE_ZH = {
        about: '关于 Screen Studio', hide: '隐藏 Screen Studio', hideOthers: '隐藏其他', unhide: '全部显示',
        quit: '退出 Screen Studio', undo: '撤销', redo: '重做', cut: '剪切', copy: '复制', paste: '粘贴',
        pasteAndMatchStyle: '粘贴并匹配样式', delete: '删除', selectAll: '全选', startSpeaking: '开始朗读',
        stopSpeaking: '停止朗读', minimize: '最小化', zoom: '缩放', front: '前置全部窗口', close: '关闭窗口',
        togglefullscreen: '进入全屏幕', 'toggleDevTools': '开发者工具', resetZoom: '实际大小',
        zoomIn: '放大', zoomOut: '缩小', services: '服务'
      };
      const relabel = () => {
        try {
          const menu = Menu.getApplicationMenu();
          if (!menu) return;
          const walk = (m) => {
            for (const it of m.items || []) {
              try {
                const r = it.role && String(it.role).toLowerCase();
                if (r && ROLE_ZH[r]) { it.label = ROLE_ZH[r]; }
                else if (typeof it.label === 'string' && it.label) { const t = tr(it.label); if (t) it.label = t; }
              } catch (e) {}
              if (it.submenu) walk(it.submenu);
            }
          };
          walk(menu);
        } catch (e) {}
      };
      app.whenReady().then(() => { relabel(); setTimeout(relabel, 1500); setTimeout(relabel, 4000); });
      app.on('browser-window-focus', () => setTimeout(relabel, 300));
    } catch (e) {}

    // ---- 原生菜单/右键菜单/弹层：在主进程入口把 label 换成中文 ----
    try {
      const { ipcMain } = electron;
      const trMenuItems = (items) => {
        if (!Array.isArray(items)) return;
        for (const it of items) {
          if (!it || typeof it !== 'object') continue;
          for (const k of ['label', 'subtitle', 'tooltip', 'title']) {
            if (typeof it[k] === 'string') { const t = tr(it[k]); if (t) it[k] = t; }
          }
          if (Array.isArray(it.options)) {
            for (const op of it.options) {
              if (op && typeof op === 'object' && typeof op.label === 'string') {
                const t = tr(op.label); if (t) op.label = t;
              }
            }
          }
          for (const k of ['items', 'children', 'submenu']) trMenuItems(it[k]);
        }
      };
      const hookMenuPath = (payload) => {
        try {
          if (!payload || typeof payload !== 'object') return;
          const p = payload.path;
          if (typeof p !== 'string') return;
          if (!/^(contextMenu|menu|popover|overlay)\./.test(p)) return;
          const input = payload.input;
          if (!input || typeof input !== 'object') return;
          trMenuItems(input.items);
          if (process.env.SS_LOG_IPC) {
            try { fs.appendFileSync('/tmp/ss-menu-zh.log', p + ' ' + JSON.stringify(input.items || input.submenu || []).slice(0, 600) + '\n'); } catch (e) {}
          }
          trMenuItems(input.submenu);
          trMenuItems(input.children);
          for (const k of ['label', 'title', 'subtitle']) {
            if (typeof input[k] === 'string') { const t = tr(input[k]); if (t) input[k] = t; }
          }
        } catch (e) {}
      };
      for (const m of ['handle', 'handleOnce', 'on', 'once']) {
        if (typeof ipcMain[m] !== 'function') continue;
        const orig = ipcMain[m].bind(ipcMain);
        ipcMain[m] = function (ch, fn) {
          return orig(ch, function (...a) {
            for (const arg of a) {
              if (arg && typeof arg === 'object' && typeof arg.path === 'string') hookMenuPath(arg);
              if (arg && typeof arg === 'object' && arg.input && typeof arg.input === 'object' && typeof arg.input.path === 'string') hookMenuPath(arg.input);
            }
            return fn.apply(this, a);
          });
        };
      }
    } catch (e) {}

    // ---- IPC 诊断（SS_LOG_IPC=1 时记录主进程收到的通道与载荷预览）----
    try {
      if (process.env.SS_LOG_IPC) {
        const { ipcMain } = electron;
        const log = (tag, ch, args) => {
          try {
            const preview = JSON.stringify(args).slice(0, 400);
            fs.appendFileSync('/tmp/ss-ipc.log', tag + ' ' + ch + ' ' + preview + '\n');
          } catch (e) {}
        };
        for (const m of ['handle', 'handleOnce', 'on', 'once']) {
          if (typeof ipcMain[m] !== 'function') continue;
          const orig = ipcMain[m].bind(ipcMain);
          ipcMain[m] = function (ch, fn) {
            return orig(ch, function (...a) { log(m, ch, a.slice(1)); return fn.apply(this, a); });
          };
        }
      }
    } catch (e) {}

    // ---- 注入渲染层翻译器到每个窗口（包括 about:blank 子窗口）----
    try {
      const zhSrc = fs.readFileSync(path.join(__dirname, 'zh-renderer.js'), 'utf8');
      const inject = (wc) => {
        try { wc.executeJavaScript(zhSrc, true).catch(() => {}); } catch (e) {}
      };
      const injectSeries = (wc) => {
        inject(wc);
        for (const d of [250, 600, 1200, 2500, 5000]) setTimeout(() => { try { if (!wc.isDestroyed()) inject(wc); } catch (e) {} }, d);
      };
      app.on('web-contents-created', (_e, wc) => {
        try {
          wc.on('dom-ready', () => injectSeries(wc));
          wc.on('did-finish-load', () => injectSeries(wc));
        } catch (e) {}
      });
      app.on('browser-window-created', (_e, win) => {
        try { win.webContents.on('dom-ready', () => injectSeries(win.webContents)); } catch (e) {}
        try {
          win.on('page-title-updated', (ev, title) => {
            const t = tr(title);
            if (t) { ev.preventDefault(); win.setTitle(t); }
          });
          setTimeout(() => {
            try { const t = tr(win.getTitle()); if (t) win.setTitle(t); } catch (e) {}
          }, 1200);
        } catch (e) {}
      });
    } catch (e) {}

    // ---- 漏译收集：把窗口里没命中的英文写到 userData/zh-misses.json ----
    try {
      const missFile = path.join(app.getPath('userData'), 'zh-misses.json');
      let lastSig = '';
      setInterval(async () => {
        try {
          const acc = new Set();
          for (const w of BrowserWindow.getAllWindows()) {
            if (!w || w.isDestroyed() || !w.webContents) continue;
            try {
              const raw = await w.webContents.executeJavaScript('JSON.stringify(window.__SS_ZH_MISSES__||[])', true);
              for (const s of JSON.parse(raw || '[]')) acc.add(s);
            } catch (e) {}
          }
          const list = [...acc].sort();
          const sig = list.join('\u0001');
          if (sig && sig !== lastSig) {
            lastSig = sig;
            fs.writeFileSync(missFile, JSON.stringify(list, null, 1), 'utf8');
          }
        } catch (e) {}
      }, 15000);
    } catch (e) {}

    // ---- Tray tooltip ----
    if (Tray && Tray.prototype && Tray.prototype.setToolTip) {
      const origTip = Tray.prototype.setToolTip;
      Tray.prototype.setToolTip = function (t) { return origTip.call(this, trText(t)); };
    }
  } catch (e) {
    try { console.error('[zh-main] shim failed:', e && e.message); } catch (_) {}
  }
})();
