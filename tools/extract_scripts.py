"""Extract RPG Maker XP / Essentials script archives (Scripts.rxdata, PluginScripts.rxdata) to .rb files."""
import sys, os, re, zlib
from rubymarshal.reader import load


def b(x):
    if isinstance(x, bytes):
        return x
    if hasattr(x, "text"):
        return x.text.encode("utf-8") if isinstance(x.text, str) else x.text
    if isinstance(x, str):
        return x.encode("utf-8")
    return bytes(x)


def safe(name):
    return re.sub(r'[\\/:*?"<>|]', "_", name).strip() or "unnamed"


def extract_scripts(path, out):
    os.makedirs(out, exist_ok=True)
    with open(path, "rb") as f:
        data = load(f)
    for i, entry in enumerate(data):
        _id, name, code = entry
        name = b(name).decode("utf-8", "replace")
        src = zlib.decompress(b(code))
        with open(os.path.join(out, f"{i:04d}_{safe(name)}.rb"), "wb") as g:
            g.write(src)
    print(path, len(data), "scripts")


def extract_plugins(path, out):
    os.makedirs(out, exist_ok=True)
    with open(path, "rb") as f:
        data = load(f)
    # v19 format: [[name, meta_hash, [[filename, zlib_code], ...]], ...]
    for i, plugin in enumerate(data):
        pname, meta, files = b(plugin[0]).decode("utf-8", "replace"), plugin[1], plugin[2]
        pdir = os.path.join(out, f"{i:02d}_{safe(pname or 'plugin')}")
        os.makedirs(pdir, exist_ok=True)
        with open(os.path.join(pdir, "_meta.txt"), "w", encoding="utf-8") as g:
            g.write(repr(meta))
        for fname, code in files:
            fname = b(fname).decode("utf-8", "replace")
            with open(os.path.join(pdir, safe(fname.replace("/", "__"))), "wb") as g:
                g.write(zlib.decompress(b(code)))
    print(path, len(data), "plugins")


if __name__ == "__main__":
    kind, src, dst = sys.argv[1:4]
    (extract_plugins if kind == "plugins" else extract_scripts)(src, dst)
