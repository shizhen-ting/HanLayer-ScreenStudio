(() => {
  const DICT = window.__SS_ZH_DICT__ || {};
  const PATTERNS = (window.__SS_ZH_PATTERNS__ || []).map(([p, r]) => [new RegExp(p), r]);
  const SKIP = new Set(['SCRIPT', 'STYLE', 'CODE', 'PRE', 'TEXTAREA', 'NOSCRIPT']);
  const ATTRS = ['placeholder', 'title', 'aria-label', 'alt', 'data-tooltip', 'data-tooltip-content', 'data-tooltip-shortcut'];
  const MISSES = (window.__SS_ZH_MISSES__ = window.__SS_ZH_MISSES__ || []);
  const seenMiss = (window.__SS_ZH_SEEN__ = window.__SS_ZH_SEEN__ || new Set());
  const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
  const cache = new Map();
  function lookup(s) {
    if (cache.has(s)) return cache.get(s);
    let v = Object.prototype.hasOwnProperty.call(DICT, s) ? DICT[s] : null;
    if (v === null) {
      for (const [re, rep] of PATTERNS) {
        if (re.test(s)) { v = s.replace(re, rep); break; }
      }
    }
    cache.set(s, v);
    return v;
  }
  function translateTextNode(node) {
    if (!node) return;
    const pe = node.parentElement;
    if (pe && (SKIP.has(pe.tagName) || pe.isContentEditable)) return;
    const raw = node.nodeValue;
    if (!raw || !/[A-Za-z]/.test(raw)) return;
    const key = norm(raw);
    if (!key) return;
    const v = lookup(key);
    if (v == null || v === key) {
      if (/[A-Za-z]{2}/.test(key) && !/[\u4e00-\u9fff]/.test(key) && key.length < 400 && !seenMiss.has(key) && MISSES.length < 8000) {
        seenMiss.add(key);
        MISSES.push(key);
      }
      return;
    }
    const m = /^(\s*)([\s\S]*?)(\s*)$/.exec(raw);
    node.nodeValue = m[1] + v + m[3];
  }
  const KEYMAP = { Meta: '⌘', Command: '⌘', Cmd: '⌘', Shift: '⇧', Alt: '⌥', Option: '⌥', Control: '⌃', Ctrl: '⌃',
    ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓', Space: '空格', Escape: 'Esc', Backspace: '⌫',
    Enter: '⏎', Return: '⏎', Delete: '⌦', Tab: 'Tab', PageUp: 'Page Up', PageDown: 'Page Down' };
  function trShortcut(v) {
    if (!v) return v;
    const parts = String(v).split('+').map((p) => p.trim()).filter(Boolean);
    if (!parts.length) return v;
    if (parts.length === 1) return KEYMAP[parts[0]] || parts[0];
    const mapped = parts.map((p) => KEYMAP[p] || p);
    return mapped.join('');
  }
  function translateAttrs(el) {
    for (const a of ATTRS) {
      const v = el.getAttribute && el.getAttribute(a);
      if (!v || !/[A-Za-z]/.test(v)) continue;
      const key = norm(v);
      if (a === 'data-tooltip-shortcut') {
        const sc = trShortcut(v);
        if (sc && sc !== v) el.setAttribute(a, sc);
        continue;
      }
      const t = lookup(key);
      if (t && t !== key) el.setAttribute(a, t);
    }
  }
  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { translateTextNode(root); return; }
    if (root.nodeType !== 1) return;
    if (SKIP.has(root.tagName) || root.isContentEditable) return;
    translateAttrs(root);
    const tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
      acceptNode: (n) => {
        if (n.nodeType === 1 && (SKIP.has(n.tagName) || n.isContentEditable)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    let n;
    while ((n = tw.nextNode())) {
      if (n.nodeType === 3) translateTextNode(n);
      else translateAttrs(n);
    }
  }
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      if (m.type === 'characterData') translateTextNode(m.target);
      else if (m.type === 'attributes') translateAttrs(m.target);
      else for (const n of m.addedNodes) walk(n);
    }
  });
  let lastRoot = null;
  function attach() {
    const root = document.documentElement;
    if (!root) return;
    lastRoot = root;
    try { obs.disconnect(); } catch (e) {}
    obs.observe(root, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS });
    walk(document.body || root);
  }
  if (window.__SS_ZH_TIMER__) { try { clearInterval(window.__SS_ZH_TIMER__); } catch (e) {} }
  window.__SS_ZH_TIMER__ = setInterval(() => {
    try {
      if (!document.documentElement) return;
      if (document.documentElement !== lastRoot) attach();
      else walk(document.body || document.documentElement);
      if (document.title) {
        const t = lookup(norm(document.title));
        if (t && t !== document.title) document.title = t;
      }
    } catch (e) {}
  }, 1200);
  const boot = () => {
    attach();
    try {
      if (document.title) { const t = lookup(norm(document.title)); if (t) document.title = t; }
    } catch (e) {}
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot, { once: true });
  else boot();
})();
