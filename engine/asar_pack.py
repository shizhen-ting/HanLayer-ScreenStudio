import json, os, struct, sys, shutil

def align(n, a):
    return n + ((a - (n % a)) % a)

def build(root, unpacked_dirs):
    files = {}
    for name in sorted(os.listdir(root)):
        if name == 'app.asar.unpacked':
            continue
        files[name] = walk(os.path.join(root, name), name, unpacked_dirs)
    return {'files': files}

def is_unpacked(rel, unpacked_dirs):
    return any(rel == d or rel.startswith(d + '/') for d in unpacked_dirs)

def walk(path, rel, unpacked_dirs):
    if os.path.isdir(path):
        node = {'files': {}}
        for name in sorted(os.listdir(path)):
            p = os.path.join(path, name)
            node['files'][name] = walk(p, rel + '/' + name, unpacked_dirs)
        return node
    size = os.path.getsize(path)
    entry = {'size': size}
    if is_unpacked(rel, unpacked_dirs):
        entry['unpacked'] = True
    return entry

def pack(root, out, unpacked_dirs):
    header = build(root, unpacked_dirs)
    # assign offsets for packed files only
    order = []
    def collect(node, base=''):
        for name, meta in node['files'].items():
            p = base + '/' + name if base else name
            if 'files' in meta:
                collect(meta, p)
            else:
                order.append((p, meta))
    collect(header)
    offset = 0
    for p, meta in order:
        if meta.get('unpacked'):
            continue
        meta['offset'] = str(offset)
        offset += meta['size']
    js = json.dumps(header, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    payload_len = align(4 + len(js), 64)
    buf = bytearray(payload_len)
    struct.pack_into('<I', buf, 0, len(js))
    buf[4:4 + len(js)] = js
    header_buf = struct.pack('<I', payload_len) + bytes(buf)
    with open(out, 'wb') as o:
        o.write(struct.pack('<II', 4, len(header_buf)))
        o.write(header_buf)
        for p, meta in order:
            if meta.get('unpacked'):
                continue
            with open(os.path.join(root, p), 'rb') as f:
                shutil.copyfileobj(f, o, 1 << 20)
    # unpacked dir
    up = out + '.unpacked'
    for p, meta in order:
        if not meta.get('unpacked'):
            continue
        dst = os.path.join(up, p)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(root, p), dst)

if __name__ == '__main__':
    root, out = sys.argv[1], sys.argv[2]
    dirs = sys.argv[3:]
    pack(root, out, dirs)
    print('packed', out, os.path.getsize(out))
