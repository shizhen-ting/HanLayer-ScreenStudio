import json, os, struct, sys, shutil

class Asar:
    def __init__(self, path):
        self.path = path
        self.f = open(path, 'rb')
        head = self.f.read(16)
        # locate JSON header
        idx = head.find(b'{"files"')
        if idx < 0:
            self.f.seek(0); head = self.f.read(64); idx = head.find(b'{"files"')
        self.f.seek(idx)
        dec = json.JSONDecoder()
        buf = self.f.read(8 * 1024 * 1024)
        # grow buffer until JSON parses
        while True:
            try:
                text = buf.decode('utf-8', 'replace')
                self.header, end = dec.raw_decode(text)
                break
            except json.JSONDecodeError:
                more = self.f.read(8 * 1024 * 1024)
                if not more: raise
                buf += more
        self.f.seek(4)
        hdr = self.f.read(4)
        self.data_start = 8 + int.from_bytes(hdr, 'little')

    def walk(self, node=None, prefix=''):
        node = node or self.header['files']
        for name, meta in node.items():
            p = prefix + '/' + name if prefix else name
            if 'files' in meta:
                yield from self.walk(meta['files'], p)
            else:
                yield p, meta

    def read(self, rel):
        parts = rel.strip('/').split('/')
        node = self.header['files']
        for p in parts[:-1]:
            node = node[p]['files']
        meta = node[parts[-1]]
        if 'link' in meta:
            link = meta['link'].lstrip('/')
            for p in parts[:-1]:
                if link.startswith(p + '/'):
                    link = link[len(p)+1:]
            base = '/'.join(parts[:-1])
            return self.read(base + '/' + link if base else link)
        if 'offset' not in meta:
            unpacked = os.path.join(self.path + '.unpacked', rel)
            if os.path.exists(unpacked):
                return open(unpacked, 'rb').read()
            return b''
        self.f.seek(self.data_start + int(meta['offset']))
        return self.f.read(int(meta['size']))

    def extract(self, dest, only=None):
        for rel, meta in self.walk():
            if only and not any(rel == o or rel.startswith(o.rstrip('/') + '/') for o in only):
                continue
            out = os.path.join(dest, rel)
            if 'link' in meta:
                continue
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, 'wb') as o:
                o.write(self.read(rel))

if __name__ == '__main__':
    cmd = sys.argv[1]
    a = Asar(sys.argv[2])
    if cmd == 'ls':
        for rel, meta in a.walk():
            print(f"{meta.get('size',''):>12} {rel}")
    elif cmd == 'cat':
        sys.stdout.buffer.write(a.read(sys.argv[3]))
    elif cmd == 'extract':
        a.extract(sys.argv[3], sys.argv[4:] or None)
        print('extracted')
