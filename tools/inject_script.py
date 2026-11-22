"""Insert (or replace) a named script section in an RMXP Scripts.rxdata, right before 'Main'.

usage: inject_script.py <Scripts.rxdata in> <out> <section name> <file.rb> [<section name> <file.rb> ...]
       inject_script.py --roundtrip <Scripts.rxdata>     (sanity check: load+dump must be byte-identical)
"""
import sys, zlib, io, random
from rubymarshal.reader import load
from rubymarshal.writer import write
from rubymarshal.classes import RubyString


def name_of(entry):
    n = entry[1]
    if isinstance(n, bytes):
        return n.decode("utf-8", "replace")
    return str(n.text if hasattr(n, "text") else n)


def dump(obj):
    buf = io.BytesIO()
    write(buf, obj)
    return buf.getvalue()


def main():
    if sys.argv[1] == "--roundtrip":
        raw = open(sys.argv[2], "rb").read()
        data = load(io.BytesIO(raw))
        again = dump(data)
        print("identical" if again == raw else f"DIFFERENT ({len(raw)} vs {len(again)})")
        return
    src, dst = sys.argv[1], sys.argv[2]
    pairs = list(zip(sys.argv[3::2], sys.argv[4::2]))
    data = load(open(src, "rb"))
    template_name = data[0][1]
    for section, rb in pairs:
        code = open(rb, "rb").read()
        data = [e for e in data if name_of(e) != section]
        main_idx = next(i for i, e in enumerate(data) if name_of(e) == "Main")
        name_obj = RubyString(section, attributes=getattr(template_name, "attributes", {"E": True})) \
            if isinstance(template_name, RubyString) else section.encode("utf-8")
        entry = [random.randint(10_000_000, 99_999_999), name_obj, zlib.compress(code)]
        data.insert(main_idx, entry)
        print(f"inserted '{section}' at index {main_idx}")
    open(dst, "wb").write(dump(data))
    # verify
    check = load(open(dst, "rb"))
    names = [name_of(e) for e in check]
    for section, rb in pairs:
        i = names.index(section)
        assert zlib.decompress(check[i][2] if isinstance(check[i][2], bytes) else check[i][2].text) == open(rb, "rb").read()
    print("verified", len(check), "sections; last 4:", names[-4:])


if __name__ == "__main__":
    main()
