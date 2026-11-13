#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Screen Studio 简体中文层 —— 一键重打引擎（只替换文案，不改授权与业务逻辑）"""
import json, os, plistlib, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, 'assets')
DEFAULT_APP = '/Applications/Screen Studio.app'
MARK_MAIN_S = '/* ZH_MAIN_START */'
MARK_MAIN_E = '/* ZH_MAIN_END */'
MARK_PRE_S = '/* ZH_PRELOAD_START */'
MARK_PRE_E = '/* ZH_PRELOAD_END */'
IDENTITY = 'Screen Studio Chinese Localizer'
AGENT_LABEL = 'com.local.sszh.watch'

WATCH_SCRIPT = r'''#!/bin/bash
LOG="$HOME/Library/Logs/sszh-watch.log"
SUP="$HOME/Library/Application Support/Screen Studio 汉化"
STATE="$SUP/localized-state"
APP="/Applications/Screen Studio.app"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
[ -f "$STATE" ] || exit 0
if [ -d "$APP" ]; then
  if [ -d "$APP/Contents/Resources/zh-Hans.lproj" ]; then
    log "ok: localized build in place, no action"
    exit 0
  fi
  log "app is not localized (reinstalled/updated) -> reset TCC"
else
  log "app removed -> reset TCC"
fi
/usr/bin/tccutil reset ScreenCapture com.timpler.screenstudio >>"$LOG" 2>&1
/usr/bin/tccutil reset Accessibility com.timpler.screenstudio >>"$LOG" 2>&1
rm -f "$STATE"
log "done: state cleared"
exit 0
'''


def user_home():
    home = os.path.expanduser('~')
    if os.geteuid() == 0:
        u = console_user()
        if u and os.path.isdir('/Users/' + u):
            home = '/Users/' + u
    return home


def install_watchdog(app):
    """安装/刷新 LaunchAgent：监控 /Applications，卸载或重装后自动清理授权残留。"""
    try:
        home = user_home()
        sup = os.path.join(home, 'Library', 'Application Support', 'Screen Studio 汉化')
        os.makedirs(sup, exist_ok=True)
        script = os.path.join(sup, 'sszh-watch.sh')
        with open(script, 'w', encoding='utf-8') as f:
            f.write(WATCH_SCRIPT)
        os.chmod(script, 0o755)
        agents = os.path.join(home, 'Library', 'LaunchAgents')
        os.makedirs(agents, exist_ok=True)
        plist = os.path.join(agents, AGENT_LABEL + '.plist')
        with open(plist, 'w', encoding='utf-8') as f:
            f.write('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>%s</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>%s</string></array>
<key>WatchPaths</key><array><string>/Applications</string></array>
<key>StartInterval</key><integer>60</integer>
<key>RunAtLoad</key><true/>
</dict></plist>
''' % (AGENT_LABEL, script))
        # 记录“已汉化”状态，供守护脚本判断
        try:
            ver = plistlib.load(open(os.path.join(app, 'Contents', 'Info.plist'), 'rb')) \
                .get('CFBundleShortVersionString', 'unknown')
        except Exception:
            ver = 'unknown'
        with open(os.path.join(sup, 'localized-state'), 'w', encoding='utf-8') as f:
            f.write('%s %s\n' % (ver, app))
        uid = os.getuid()
        if uid == 0:
            u = console_user()
            if u:
                r = run(['id', '-u', u])
                if r.returncode == 0:
                    uid = int(r.stdout.strip())
        run(['launchctl', 'bootout', 'gui/%d/%s' % (uid, AGENT_LABEL)])
        run(['launchctl', 'bootstrap', 'gui/%d' % uid, plist])
    except Exception:
        pass


STEPS = 9


def log(msg):
    print(msg, flush=True)


def step(n, msg):
    log('步骤 %d/%d：%s' % (n, STEPS, msg))


def die(msg):
    print('错误：' + msg, flush=True)
    sys.exit(1)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def strip_block(text, start, end):
    pat = re.compile(re.escape(start) + r'.*?' + re.escape(end) + r'\n?', re.S)
    return pat.sub('', text)


def trust_identity():
    """证书存在但未被信任时（CSSMERR_TP_NOT_TRUSTED），自动加入用户级信任。

    这一步不需要管理员密码：只改当前用户的钥匙串信任设置。
    """
    kc = os.path.expanduser('~/Library/Keychains/login.keychain-db')
    r = run(['security', 'find-certificate', '-c', IDENTITY, '-p', kc])
    if r.returncode != 0 or 'BEGIN CERTIFICATE' not in (r.stdout or ''):
        return False
    pem = os.path.join(tempfile.gettempdir(), 'sszh-identity.pem')
    with open(pem, 'w') as f:
        f.write(r.stdout)
    r = run(['security', 'add-trusted-cert', '-r', 'trustRoot', '-k', kc, pem])
    try:
        os.remove(pem)
    except OSError:
        pass
    return r.returncode == 0


def ensure_identity():
    """本地自建签名证书：保证每次重签后签名身份不变，系统权限不会每次失效。"""
    try:
        r = run(['security', 'find-certificate', '-c', IDENTITY,
                 os.path.expanduser('~/Library/Keychains/login.keychain-db')])
        if r.returncode == 0:
            # 证书在，但可能未被信任（拿得到却签不了）
            if not identity_is_valid():
                log('   证书未被信任，正在加入信任设置…')
                if trust_identity():
                    log('   已信任，签名身份可用')
            return True
        p12 = os.path.join(ASSETS, 'ss-zh.p12')
        if not os.path.exists(p12):
            return False
        r = run(['security', 'import', p12, '-k',
                 os.path.expanduser('~/Library/Keychains/login.keychain-db'),
                 '-P', 'sszh', '-T', '/usr/bin/codesign', '-A'])
        return r.returncode == 0
    except Exception:
        return False


def identity_is_valid():
    """证书存在 ≠ 可用：find-identity -v 只列出被系统信任的签名身份。"""
    r = run(['security', 'find-identity', '-v', '-p', 'codesigning'])
    return IDENTITY in (r.stdout or '')


def has_hardened_runtime(app):
    """新版 Screen Studio 带 hardened runtime，ad-hoc 重签会被 amfid 拒绝。"""
    r = run(['codesign', '-dv', app])
    return 'flags=0x10000(runtime)' in (r.stderr or '')


def sign_app(app):
    run(['xattr', '-cr', app])
    if ensure_identity():
        r = run(['codesign', '--force', '--deep', '--sign', IDENTITY, '--keychain',
                 os.path.expanduser('~/Library/Keychains/login.keychain-db'),
                 '--options', 'runtime', '--entitlements',
                 os.path.join(ASSETS, 'entitlements.plist'), app])
        if r.returncode == 0:
            return True
        log('   本地证书签名失败，改用 ad-hoc：' + (r.stderr or '').strip()[:120])
    if has_hardened_runtime(app):
        log('   警告：签名身份无效且该版本开启了 hardened runtime，ad-hoc 重签后可能无法启动')
    r = run(['codesign', '--force', '--deep', '--sign', '-', '--options', 'runtime',
             '--entitlements', os.path.join(ASSETS, 'entitlements.plist'), app])
    return r.returncode == 0


def find_executables(root):
    out = []
    for base, _dirs, files in os.walk(root):
        for f in files:
            p = os.path.join(base, f)
            try:
                with open(p, 'rb') as fh:
                    head = fh.read(4)
            except Exception:
                continue
            if head in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                out.append(p)
    return out


def console_user():
    try:
        return subprocess.run(['stat', '-f', '%Su', '/dev/console'],
                              capture_output=True, text=True).stdout.strip() or None
    except Exception:
        return None


def launch_app(app):
    import time
    open_as_user(app)
    for _ in range(6):
        time.sleep(1)
        if run(['pgrep', '-f', 'MacOS/Screen Studio']).returncode == 0:
            return
    subprocess.Popen(['/usr/bin/env', '-u', 'ELECTRON_RUN_AS_NODE',
                      os.path.join(app, 'Contents', 'MacOS', 'Screen Studio')],
                     start_new_session=True, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


def open_as_user(app):
    user = console_user() if os.geteuid() == 0 else None
    if user:
        return run(['sudo', '-u', user, 'open', '-a', app])
    return run(['open', '-a', app])


def backup_dir_for(app):
    home = os.path.expanduser('~')
    if os.geteuid() == 0:
        u = console_user()
        if u and os.path.isdir('/Users/' + u):
            home = '/Users/' + u
    return os.path.join(home, 'Library', 'Application Support', 'Screen Studio 汉化')


def restore(app):
    import glob
    res = os.path.join(app, 'Contents', 'Resources')
    bdir = backup_dir_for(app)
    try:
        ver = plistlib.load(open(os.path.join(app, 'Contents', 'Info.plist'), 'rb')) \
            .get('CFBundleShortVersionString', 'unknown')
    except Exception:
        ver = 'unknown'
    cand = os.path.join(bdir, 'app.asar.%s.orig' % ver)
    if not os.path.exists(cand):
        allb = sorted(glob.glob(os.path.join(bdir, 'app.asar.*.orig')),
                      key=os.path.getmtime, reverse=True)
        if not allb:
            die('没有找到备份，无法恢复原版')
        cand = allb[0]
    log('▸ 用备份恢复：%s' % os.path.basename(cand))
    import time
    subprocess.run(['osascript', '-e', 'tell application id "com.timpler.screenstudio" to quit'],
                   capture_output=True)
    time.sleep(2)
    subprocess.run(['pkill', '-f', 'Screen Studio.app/Contents/MacOS/Screen Studio'],
                   capture_output=True)
    time.sleep(1)
    shutil.copy2(cand, os.path.join(res, 'app.asar'))
    bdir_plist = os.path.join(bdir, 'Info.plist.%s.orig' % ver)
    if os.path.exists(bdir_plist):
        shutil.copy2(bdir_plist, os.path.join(app, 'Contents', 'Info.plist'))
    lproj = os.path.join(res, 'zh-Hans.lproj')
    shutil.rmtree(lproj, ignore_errors=True)
    log('▸ 重新签名')
    if not sign_app(app):
        die('签名失败')
    log('▸ 启动 Screen Studio')
    launch_app(app)
    log('完成：已恢复英文原版（内容还原；签名仍是本地证书，苹果原签名需要重装官方包才会回来）。')


def main():
    args = sys.argv[1:]
    if args and args[0] == '--restore':
        restore(os.path.abspath(args[1]) if len(args) > 1 else DEFAULT_APP)
        return
    app = args[0] if args else DEFAULT_APP
    app = os.path.abspath(app)
    if not os.path.isdir(app):
        die('找不到 Screen Studio：%s' % app)
    res = os.path.join(app, 'Contents', 'Resources')
    asar = os.path.join(res, 'app.asar')
    if not os.path.isfile(asar):
        die('这个 app 里没有 app.asar，可能不是 Screen Studio')

    # 前置检查：环境不具备重签条件时，先别动原文件
    if has_hardened_runtime(app) and not identity_is_valid():
        die('这个版本的 Screen Studio 开启了 hardened runtime，\n'
            '  但本机没有可用的代码签名身份（只有 ad-hoc）。\n'
            '  ad-hoc 重签会被 amfid 拒绝，App 启动即退出。\n\n'
            '  解决办法：在「钥匙串访问」中把证书\n'
            '  「Screen Studio Chinese Localizer」设为「始终信任」，再重新运行。')

    step(1, '读取词典')
    with open(os.path.join(ASSETS, 'dict.json'), encoding='utf-8') as f:
        dic = json.load(f)
    with open(os.path.join(ASSETS, 'patterns.json'), encoding='utf-8') as f:
        patterns = json.load(f)
    with open(os.path.join(ASSETS, 'zh-core.js'), encoding='utf-8') as f:
        core = f.read()
    with open(os.path.join(ASSETS, 'zh-main.js'), encoding='utf-8') as f:
        shim = f.read()
    prelude = 'window.__SS_ZH_DICT__=%s;window.__SS_ZH_PATTERNS__=%s;' % (
        json.dumps(dic, ensure_ascii=False), json.dumps(patterns, ensure_ascii=False))

    tmp = tempfile.mkdtemp(prefix='ss-zh-')
    stage = os.path.join(tmp, 'stage')
    try:
        step(2, '解包 app.asar（%d MB）' % (os.path.getsize(asar) // 1048576))
        sys.path.insert(0, HERE)
        from asar_tool import Asar
        Asar(asar).extract(stage)

        step(3, '注入界面翻译层')
        dist = os.path.join(stage, 'dist')
        de = os.path.join(stage, 'dist-electron')
        with open(os.path.join(dist, 'zh.js'), 'w', encoding='utf-8') as f:
            f.write(prelude + core)
        html_path = os.path.join(dist, 'index.html')
        html = open(html_path, encoding='utf-8').read()
        html = re.sub(r'\s*<script src="\./zh\.js"></script>', '', html)
        html = html.replace('</head>', '    <script src="./zh.js"></script>\n  </head>')
        open(html_path, 'w', encoding='utf-8').write(html)

        step(4, '注入菜单与弹层翻译')
        with open(os.path.join(de, 'zh-renderer.js'), 'w', encoding='utf-8') as f:
            f.write(prelude + core)
        main_dict = {re.sub(r'\s+', ' ', k).strip(): v for k, v in dic.items()}
        with open(os.path.join(de, 'zh-dict.json'), 'w', encoding='utf-8') as f:
            json.dump(main_dict, f, ensure_ascii=False)

        idx_path = os.path.join(de, 'index.js')
        idx = open(idx_path, encoding='utf-8').read()
        idx = strip_block(idx, MARK_MAIN_S, MARK_MAIN_E)
        open(idx_path, 'w', encoding='utf-8').write(
            MARK_MAIN_S + '\n' + shim + '\n' + MARK_MAIN_E + '\n' + idx)

        pre_path = os.path.join(de, 'preload.js')
        pre = open(pre_path, encoding='utf-8').read()
        pre = strip_block(pre, MARK_PRE_S, MARK_PRE_E)
        open(pre_path, 'w', encoding='utf-8').write(
            pre + '\n' + MARK_PRE_S + '\n' + prelude + core + '\n' + MARK_PRE_E + '\n')

        step(5, '恢复可执行权限')
        for p in find_executables(os.path.join(stage, 'bin')):
            os.chmod(p, 0o755)

        step(6, '重新打包 asar')
        import asar_pack
        out_asar = os.path.join(tmp, 'app.asar')
        asar_pack.pack(stage, out_asar, ['bin', 'node_modules/keytar',
                                         'node_modules/node-mac-permissions',
                                         'node_modules/wallpaper'])

        probe = os.path.join(res, '.zh-write-test')
        try:
            with open(probe, 'w') as f:
                f.write('x')
            os.remove(probe)
        except PermissionError:
            die('需要管理员权限：系统不允许当前程序修改 Screen Studio.app')

        step(7, '备份原始文件')
        home = os.path.expanduser('~')
        if os.geteuid() == 0:
            u = console_user()
            if u and os.path.isdir('/Users/' + u):
                home = '/Users/' + u
        backup_dir = os.path.join(home, 'Library', 'Application Support', 'Screen Studio 汉化')
        os.makedirs(backup_dir, exist_ok=True)
        try:
            ver = plistlib.load(open(os.path.join(app, 'Contents', 'Info.plist'), 'rb')) \
                .get('CFBundleShortVersionString', 'unknown')
        except Exception:
            ver = 'unknown'
        backup = os.path.join(backup_dir, 'app.asar.%s.orig' % ver)
        if not os.path.exists(backup):
            shutil.copy2(asar, backup)
            log('   已备份原 app.asar 到 %s' % backup)
        # 只保留最近 2 个版本的备份，避免每升级一次多占 250 MB
        try:
            import glob as _glob
            olds = sorted(_glob.glob(os.path.join(backup_dir, 'app.asar.*.orig')), key=os.path.getmtime, reverse=True)
            for old in olds[2:]:
                os.remove(old)
                tail = old.split('app.asar.')[-1]
                pf = os.path.join(backup_dir, 'Info.plist.' + tail)
                if os.path.exists(pf):
                    os.remove(pf)
        except Exception:
            pass
        plist_backup = os.path.join(backup_dir, 'Info.plist.%s.orig' % ver)
        if not os.path.exists(plist_backup):
            shutil.copy2(os.path.join(app, 'Contents', 'Info.plist'), plist_backup)

        step(8, '关闭并重新安装')
        subprocess.run(['pkill', '-f', 'Screen Studio.app/Contents/MacOS/Screen Studio'],
                       capture_output=True)
        import time
        time.sleep(1.5)

        log('▸ 安装')
        shutil.copy2(out_asar, asar)
        shutil.rmtree(os.path.join(res, 'app.asar.unpacked'), ignore_errors=True)
        shutil.copytree(out_asar + '.unpacked', os.path.join(res, 'app.asar.unpacked'))

        log('▸ 写入本地化声明')
        plist_path = os.path.join(app, 'Contents', 'Info.plist')
        with open(plist_path, 'rb') as f:
            info = plistlib.load(f)
        info.pop('ElectronAsarIntegrity', None)
        info['CFBundleLocalizations'] = ['en', 'zh-Hans']
        with open(plist_path, 'wb') as f:
            plistlib.dump(info, f)

        lproj = os.path.join(res, 'zh-Hans.lproj')
        os.makedirs(lproj, exist_ok=True)
        with open(os.path.join(lproj, 'InfoPlist.strings'), 'w', encoding='utf-8') as f:
            f.write('"CFBundleName" = "Screen Studio";\n')

        log('▸ 重新签名')
        if not sign_app(app):
            die('签名失败')
        # 签名身份变化时，旧权限会失效：清掉旧记录，让系统重新询问
        try:
            ident_file = os.path.join(backup_dir, 'signing-identity.txt')
            current = 'local-cert' if ensure_identity() else 'adhoc'
            previous = open(ident_file).read().strip() if os.path.exists(ident_file) else ''
            if previous != current:
                run(['tccutil', 'reset', 'ScreenCapture', 'com.timpler.screenstudio'])
                run(['tccutil', 'reset', 'Accessibility', 'com.timpler.screenstudio'])
                open(ident_file, 'w').write(current)
                log('   签名身份已变化，已重置屏幕录制/辅助功能授权，需要重新允许一次')
        except Exception:
            pass

        step(9, '启动 Screen Studio')
        open_as_user(app)
        launch_app(app)
        log('完成：界面已恢复简体中文。')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
