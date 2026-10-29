#!/usr/bin/env bash
# Updates Support/Localization/Localizable.xcstrings with every translatable string in the code, using the Swift
# compiler's own extraction (the same as Xcode's "Use Compiler to Extract Swift Strings").
#
#   scripts/extract-strings.sh            # update the String Catalog
#   scripts/extract-strings.sh --check    # fail if the code has text the String Catalog doesn't (used by CI)
#   scripts/extract-strings.sh --audit    # also list English-looking strings that aren't marked for translation
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CATALOG=Support/Localization/Localizable.xcstrings
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stringsdata" "$(dirname "$CATALOG")"

swift build --build-path "$WORK/build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/stringsdata" >/dev/null
[[ -f "$CATALOG" ]] || echo '{"sourceLanguage":"en-GB","strings":{},"version":"1.0"}' > "$CATALOG"

if [[ "${1:-}" == "--check" ]]; then
  cp "$CATALOG" "$WORK/catalog.xcstrings"
  xcrun xcstringstool sync "$WORK/catalog.xcstrings" --stringsdata "$WORK"/stringsdata/*.stringsdata
  NEW="$(comm -13 <(xcrun xcstringstool print "$CATALOG" | sort) <(xcrun xcstringstool print "$WORK/catalog.xcstrings" | sort))"
  if [[ -n "$NEW" ]]; then
    echo "The code has text that isn't in the String Catalog yet. Run scripts/extract-strings.sh, then translate it:" >&2
    echo "$NEW" | head -40 >&2
    exit 1
  fi
  echo "The String Catalog has every string in the code."
  exit 0
fi

xcrun xcstringstool sync "$CATALOG" --stringsdata "$WORK"/stringsdata/*.stringsdata
# Text that's gone from the code goes from the catalog too, translations and all.
python3 - "$CATALOG" <<'PY'
import json, sys
path = sys.argv[1]
catalog = json.load(open(path))
stale = [key for key, entry in catalog["strings"].items() if entry.get("extractionState") == "stale"]
for key in stale:
    del catalog["strings"][key]
open(path, "w").write(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
if stale:
    print(f"Removed {len(stale)} strings no longer in the code")
PY
echo "$(xcrun xcstringstool print "$CATALOG" | grep -c .) strings in $CATALOG"

if [[ "${1:-}" == "--audit" ]]; then
  xcrun xcstringstool print "$CATALOG" > "$WORK/keys.txt"
  python3 - "$WORK/keys.txt" <<'PY'
import re, sys, pathlib
keys = set(l.rstrip("\n") for l in open(sys.argv[1]))
# Interpolations become %@ / %lld in keys; compare text with them blanked out.
def blank_interpolations(text):
    out, i = [], 0
    while i < len(text):
        if text.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[i], 0)
                i += 1
            out.append("~")
        else:
            out.append(text[i])
            i += 1
    return "".join(out)
norm = lambda s: re.sub(r"%(\d\$)?(lld|ld|d|@|lf|f|u)", "~", blank_interpolations(s)).replace("%%", "%")
known = set(norm(k) for k in keys)
skip = re.compile(r"forKey|systemName|systemImage|identifier|UserDefaults|AppStorage|\.appending|URL\(|#selector|Notification\.Name|case \"|logger|print\(|fatalError|precondition|assert|Text\(verbatim|verbatim:|\"(G|M)\d|comment:")
for path in sorted(pathlib.Path("Sources").rglob("*.swift")):
    for n, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split("//")[0] if "\"" not in line.split("//")[0][-1:] else line
        if skip.search(code) or code.strip().startswith("//"): continue
        if "<" in code and "=\\\"" in code: continue  # SVG markup
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
            text = lit.strip()
            # English words, at least two letters, a space or a capital: worth a look.
            if not re.search(r"[A-Za-z]{2}", text) or not (" " in text or re.match(r"[A-Z][a-z]", text)): continue
            if norm(lit) in known: continue
            print(f"{path}:{n}: {lit}")
PY
fi
