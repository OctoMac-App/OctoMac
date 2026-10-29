#!/usr/bin/env python3
"""Keeps OctoMac's translations complete.

    scripts/translations.py export DIR   # write DIR/source.json: every string with no translation in some language
    scripts/translations.py import DIR   # merge DIR/translations/<code>.json into the String Catalog
    scripts/translations.py check        # fail if any string is missing a language, or a translation is broken

The String Catalog is Support/Localization/Localizable.xcstrings; scripts/extract-strings.sh fills it from the code.
A translation file maps each key to a string, or to plural forms ({"one": ..., "other": ...}) for a string with one
counted number. Everything in the app is translated into every language, or the check fails.
"""
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Support/Localization/Localizable.xcstrings"
LANGUAGES = ["en-GB", "en", "cs", "da", "de", "es", "fi", "fr", "it", "nb", "nl", "pl", "pt-PT", "sv"]
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@|lf|f|u)")
LONG_DASH = re.compile("[\u2014\u2013]")
# Names that stay the same in every language.
NAMES = ["OctoMac", "OctoPrint", "GitHub"]


def load():
    return json.loads(CATALOG.read_text())


def save(catalog):
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def placeholders(text):
    """The placeholders in order of the values they take: [(position, type)]."""
    found, auto = [], 0
    for match in PLACEHOLDER.finditer(text.replace("%%", "")):
        auto += 1
        position = int(match.group(1)) if match.group(1) else auto
        found.append((position, "lld" if match.group(2) in ("lld", "ld", "d", "u") else match.group(2)))
    return sorted(found)


def translatable(catalog):
    return {key: entry for key, entry in catalog["strings"].items()
            if entry.get("shouldTranslate", True) and entry.get("extractionState") != "stale" and key.strip()}


def texts(localization):
    """Every text in one language's entry: the plain value, or each plural form."""
    unit = localization.get("stringUnit")
    if unit:
        return [unit["value"]]
    plural = localization.get("variations", {}).get("plural", {})
    return [form["stringUnit"]["value"] for form in plural.values()]


def export(folder):
    catalog = load()
    rows = []
    for key, entry in sorted(translatable(catalog).items()):
        localizations = entry.get("localizations", {})
        if all(language in localizations for language in LANGUAGES):
            continue
        source = localizations.get("en-GB", {}).get("stringUnit", {}).get("value", key)
        rows.append({"key": key, "source": source, "comment": entry.get("comment", "")})
    Path(folder).mkdir(parents=True, exist_ok=True)
    Path(folder, "source.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    print(f"{len(rows)} strings need translating; wrote {folder}/source.json")


def import_(folder):
    catalog = load()
    strings = catalog["strings"]
    for language in LANGUAGES:
        path = Path(folder, "translations", f"{language}.json")
        if not path.exists():
            continue
        translated = json.loads(path.read_text())
        for key, value in translated.items():
            if key not in strings:
                continue
            localizations = strings[key].setdefault("localizations", {})
            if isinstance(value, dict):
                localizations[language] = {"variations": {"plural": {
                    form: {"stringUnit": {"state": "translated", "value": text}} for form, text in value.items()}}}
            else:
                localizations[language] = {"stringUnit": {"state": "translated", "value": value}}
        print(f"{language}: {len(translated)} strings")
    catalog["sourceLanguage"] = "en-GB"
    save(catalog)


def check():
    problems = []
    for key, entry in sorted(translatable(load()).items()):
        localizations = entry.get("localizations", {})
        expected = placeholders(key)
        for language in LANGUAGES:
            if language not in localizations:
                problems.append(f"{language}: not translated: {key!r}")
                continue
            for text in texts(localizations[language]):
                if LONG_DASH.search(text):
                    problems.append(f"{language}: long dash in {key!r}")
                got = placeholders(text)
                # Plural forms may leave out the number ("one file"), but never add or change one.
                if got != expected and not (set(got) <= set(expected) and "variations" in localizations[language]):
                    problems.append(f"{language}: placeholders {got} should be {expected} in {key!r}")
                for name in NAMES:
                    if name in key and name not in text:
                        problems.append(f"{language}: {name} missing from translation of {key!r}")
    for problem in problems[:60]:
        print(problem)
    if len(problems) > 60:
        print(f"…and {len(problems) - 60} more")
    counts = {}
    for problem in problems:
        language = problem.split(":")[0]
        counts[language] = counts.get(language, 0) + 1
    if counts:
        print("By language:", ", ".join(f"{language} {count}" for language, count in sorted(counts.items())))
    if problems:
        sys.exit(f"{len(problems)} translation problems")
    print(f"All {len(translatable(load()))} strings are translated into {len(LANGUAGES)} languages.")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "export":
        export(sys.argv[2])
    elif command == "import":
        import_(sys.argv[2])
    else:
        check()
