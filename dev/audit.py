import re, sys, glob, os
# Accepts the repository root; the mod itself lives in Contents/mods/BlindSoundHunters.
root = os.path.join(sys.argv[1], "Contents", "mods", "BlindSoundHunters")
ok = True
def fail(m):
    global ok; ok = False; print("FAIL:", m)

tok_re = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\d+\.?\d*(?:[eE][-+]?\d+)?|[A-Za-z_]\w*|\.\.\.|\.\.|==|~=|<=|>=|//|<<|>>|::|\S', re.S)
for f in sorted(glob.glob(root + "/42/media/lua/**/*.lua", recursive=True)):
    src = open(f, encoding="utf-8").read()
    toks = [t for t in tok_re.findall(src) if False] # placeholder
    toks = [m.group(0) for m in tok_re.finditer(src) if not m.group(0).startswith("--")]
    stack = []; bad = False
    for i, t in enumerate(toks):
        if t in ("goto", "//", "<<", ">>", "&", "|", "::"): fail(f"{f}: forbidden token {t}")
        if t == "~" and (i+1 >= len(toks) or toks[i+1] != "="): fail(f"{f}: bitwise ~")
        if t in ("function", "if", "do", "repeat"): stack.append(t)
        elif t in ("while", "for"): stack.append(t)
        elif t == "do" : pass
        if t in ("(", "{", "["): stack.append(t)
        if t in (")", "}", "]"):
            want = {")":"(", "}":"{", "]":"["}[t]
            if not stack or stack[-1] != want: fail(f"{f}: unbalanced {t} at token {i}"); bad=True; break
            stack.pop()
        if t == "end":
            # pop nearest block opener; 'while/for ... do' count as one block
            if not stack or stack[-1] not in ("function","if","do","while","for"): fail(f"{f}: stray end at token {i}"); bad=True; break
            top = stack.pop()
            if top == "do" and stack and stack[-1] in ("while","for"): stack.pop()
        if t == "until":
            if not stack or stack[-1] != "repeat": fail(f"{f}: stray until"); bad=True; break
            stack.pop()
    if not bad and stack: fail(f"{f}: unclosed {stack[-5:]}")
    for lib in ("table.unpack", "os.execute", "io.popen", "debug.", "string.pack", "utf8."):
        if lib in src: fail(f"{f}: uses {lib}")
    print("ok " if not bad else "BAD", os.path.relpath(f, root))

# i18n sync
opts = open(root + "/42/media/sandbox-options.txt", encoding="utf-8").read()
need = set()
for blk in re.findall(r'option\s+BlindSoundHunters\.\w+\s*\{(.*?)\}', opts, re.S):
    tr = re.search(r'translation\s*=\s*(\w+)', blk).group(1)
    need |= {f"Sandbox_{tr}", f"Sandbox_{tr}_tooltip"}
    m = re.search(r'valueTranslation\s*=\s*(\w+)', blk)
    if m:
        n = int(re.search(r'numValues\s*=\s*(\d+)', blk).group(1))
        need |= {f"Sandbox_{m.group(1)}_option{k}" for k in range(1, n+1)}
for p in set(re.findall(r'page\s*=\s*(\w+)', opts)): need.add(f"Sandbox_{p}")
keysets = {}
# B42.22+: Translator reads <modDir>/media/lua/shared/Translate/<LANG>/<Name>.json (strict JSON)
import json
for old in glob.glob(f"{root}/42/media/lua/shared/Translate/*/*.txt"):
    fail(f"legacy .txt translation is ignored by B42.22+: {os.path.relpath(old, root)}")
for lang in ("EN", "PTBR"):
    path = f"{root}/42/media/lua/shared/Translate/{lang}/Sandbox.json"
    raw = open(path, "rb").read()
    if raw.startswith(b"\xef\xbb\xbf"): fail(f"{lang}: BOM present")
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError as e:
        fail(f"{lang}: invalid JSON: {e}"); data = {}
    if not all(isinstance(v, str) for v in data.values()): fail(f"{lang}: non-string value")
    keys = set(data)
    keysets[lang] = keys
    miss = need - keys; extra = keys - need
    if miss: fail(f"{lang} missing {sorted(miss)}")
    if extra: fail(f"{lang} extra {sorted(extra)}")
if keysets["EN"] != keysets["PTBR"]: fail("EN/PTBR key mismatch")
print("i18n keys required:", len(need))
print("RESULT:", "PASS" if ok else "FAIL")
