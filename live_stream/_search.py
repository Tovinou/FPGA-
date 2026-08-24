import pathlib, glob, re

root = "c:/Jensen/projects/fpga/live_stream"
matches = []

for f in sorted(glob.glob(str(pathlib.Path(root)/"**/*"), recursive=True)):
    try:
        p = pathlib.Path(f)
        if any(p.name.startswith(x) for x in [".git", ".svn", ".DS_Store"]): continue
        if str(p).endswith((".pyc", ".so", ".dll")): continue
        content = p.read_text(encoding="utf-8", errors="ignore")
        for m in re.finditer(r"test_pattern|TEST_PATTERN_WIDTH|TEST_PATTERN_HEIGHT", content, re.IGNORECASE):
            matches.append((str(p), m.start(), m.group()))
    except Exception as e:
        pass

for p, idx, txt in sorted(matches)[:30]:
    print(f"{p}:{idx} {txt}")
