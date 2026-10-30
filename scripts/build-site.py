#!/usr/bin/env python3
"""The website in every language OctoMac speaks.

website/index.html is the UK English page and the only one to edit. This script finds its text (runs of words between
block-level tags, plus alt text, labels and the page description), keeps translations of it in
website/i18n/<language>.json, and builds a page per language with that language's screenshots and a language picker.

  scripts/build-site.py build OUT       # the whole site into OUT, ready to publish
  scripts/build-site.py check           # every language has every piece of text (CI runs this)
  scripts/build-site.py export DIR      # text still to translate, in the same layout as scripts/translations.py
  scripts/build-site.py import DIR      # translations back from DIR/translations/<language>.json

Text in an element marked translate="no" (and in <code>, <pre>, <script>, <style> and <svg>) is left alone.
"""
import html
import json
import re
import shutil
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "website" / "index.html"
I18N = ROOT / "website" / "i18n"
SITE_URL = "https://octomac-app.github.io/"

# Each language: its folder on the site (UK English is the top level), its name in its own language, and its flag.
LANGUAGES = [
    ("en-GB", "", "English (UK)", "gb"),
    ("en", "en-us", "English (US)", "us"),
    ("cy", "cy", "Cymraeg", "gb-wls"),
    ("cs", "cs", "Čeština", "cz"),
    ("da", "da", "Dansk", "dk"),
    ("de", "de", "Deutsch", "de"),
    ("es", "es", "Español", "es"),
    ("fi", "fi", "Suomi", "fi"),
    ("fr", "fr", "Français", "fr"),
    ("it", "it", "Italiano", "it"),
    ("nb", "nb", "Norsk bokmål", "no"),
    ("nl", "nl", "Nederlands", "nl"),
    ("pl", "pl", "Polski", "pl"),
    ("pt-PT", "pt", "Português", "pt"),
    ("sv", "sv", "Svenska", "se"),
]
SOURCE = "en-GB"

INLINE = {"a", "strong", "em", "b", "i", "span", "small", "br", "kbd", "sup", "sub"}
OPAQUE = {"script", "style", "svg", "code", "pre"}
VOID = {"meta", "link", "img", "br", "hr", "input", "source", "wbr"}
ATTRIBUTES = {"alt", "aria-label", "title", "placeholder", "data-latest", "data-released", "data-copied", "data-copy-label"}
META = {"description", "og:title", "og:description"}


class Scanner(HTMLParser):
    """Finds the page's text: runs of words and inline tags between block tags, and translatable attributes. Each is
    recorded as a (start, end, text) span of the original page, so it can be swapped for a translation in place."""

    def __init__(self, page):
        super().__init__(convert_charrefs=False)
        self.page = page
        self.lines = [0]
        for line in page.splitlines(keepends=True):
            self.lines.append(self.lines[-1] + len(line))
        self.spans = []
        self.skip = []       # tags whose content is left alone
        self.run = None      # start of the current run of inline content
        self.run_end = None
        self.open_inline = 0

    def position(self):
        line, column = self.getpos()
        return self.lines[line - 1] + column

    def tag_end(self, start):
        return start + len(self.get_starttag_text())

    def end_run(self):
        if self.run is not None and self.open_inline == 0:
            raw = self.page[self.run:self.run_end]
            text = raw.strip()
            if re.search(r"[^\W\d_]", re.sub(r"<[^>]+>", "", text)):
                start = self.run + len(raw) - len(raw.lstrip())
                # Text wrapped in a lone <span> is translated without it.
                wrapped = re.fullmatch(r"<span>((?:(?!<span).)*)</span>", text, re.S)
                if wrapped:
                    start, text = start + len("<span>"), wrapped.group(1)
                self.spans.append((start, start + len(text), text))
        self.run = None
        self.open_inline = 0

    def extend(self, start, end):
        if self.run is None:
            self.run = start
        self.run_end = end

    def attributes(self, tag, attrs, start):
        source = self.get_starttag_text()
        for name, value in attrs:
            wanted = name in ATTRIBUTES or (tag == "meta" and name == "content" and
                                             (dict(attrs).get("name") in META or dict(attrs).get("property") in META))
            if not wanted or not value or not re.search(r"[^\W\d_]", value):
                continue
            match = re.search(r'\s' + re.escape(name) + r'="([^"]*)"', source)
            if match:
                self.spans.append((start + match.start(1), start + match.end(1), match.group(1)))

    def handle_starttag(self, tag, attrs):
        start = self.position()
        if self.skip:
            if tag not in VOID:
                self.skip.append(tag)
            return
        if dict(attrs).get("translate") == "no" or tag in OPAQUE:
            self.end_run()
            if tag not in VOID:
                self.skip.append(tag)
            return
        self.attributes(tag, attrs, start)
        inline = tag in INLINE and "class" not in dict(attrs) and "id" not in dict(attrs)
        if inline and self.run is not None or inline and tag != "br":
            self.extend(start, self.tag_end(start))
            if tag not in VOID:
                self.open_inline += 1
        else:
            self.end_run()

    def handle_startendtag(self, tag, attrs):
        start = self.position()
        if self.skip:
            return
        self.attributes(tag, attrs, start)
        if tag != "br" or self.run is None:
            self.end_run()

    def handle_endtag(self, tag):
        start = self.position()
        if self.skip:
            self.skip.pop()
            return
        if self.open_inline > 0 and tag in INLINE:
            self.open_inline -= 1
            self.extend(self.run, start + len(f"</{tag}>"))
        else:
            self.end_run()

    def handle_data(self, data):
        if self.skip:
            return
        start = self.position()
        if data.strip() or self.run is not None:
            self.extend(start, start + len(data))

    def handle_entityref(self, name):
        self.handle_data(f"&{name};")

    def handle_charref(self, name):
        self.handle_data(f"&#{name};")


def scan(page):
    scanner = Scanner(page)
    scanner.feed(page)
    scanner.close()
    return sorted(scanner.spans)


def texts(page):
    """Every piece of text to translate, in page order, once each."""
    seen, result = set(), []
    for _, _, text in scan(page):
        if text not in seen:
            seen.add(text)
            result.append(text)
    return result


def load(code):
    path = I18N / f"{code}.json"
    return json.loads(path.read_text()) if path.exists() else {}


def picker(current, depth):
    """The language menu, with each language named in its own language."""
    up = "../" * depth
    items = []
    for code, folder, name, flag in LANGUAGES:
        href = up + (folder + "/" if folder else "")
        selected = ' aria-current="true"' if code == current else ""
        items.append(f'<a href="{href or "./"}" hreflang="{code}" lang="{code}"{selected}>'
                     f'<img src="{up}site/flags/{flag}.svg" alt="" width="20" height="15">{name}</a>')
    _, _, name, flag = next(language for language in LANGUAGES if language[0] == current)
    return (f'<details class="languages" translate="no">'
            f'<summary aria-label="Language: {name}"><img src="{up}site/flags/{flag}.svg" alt="" width="20" height="15">'
            f'<span>{name}</span><svg viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></summary>'
            f'<div class="menu">{"".join(items)}</div></details>')


def alternates(depth):
    links = [f'<link rel="alternate" hreflang="{code}" href="{SITE_URL}{folder + "/" if folder else ""}">'
             for code, folder, _, _ in LANGUAGES]
    links.append(f'<link rel="alternate" hreflang="x-default" href="{SITE_URL}">')
    return "\n".join(links)


def build_page(page, code, folder, translations):
    out = []
    last = 0
    for start, end, text in scan(page):
        out.append(page[last:start])
        out.append(translations.get(text, text) if code != SOURCE else text)
        last = end
    out.append(page[last:])
    result = "".join(out)

    depth = 1 if folder else 0
    url = SITE_URL + (folder + "/" if folder else "")
    result = result.replace('<html lang="en-GB">', f'<html lang="{code}">', 1)
    result = re.sub(r'<link rel="canonical" href="[^"]*">', f'<link rel="canonical" href="{url}">\n{alternates(depth)}', result, count=1)
    result = re.sub(r'<meta property="og:url" content="[^"]*">', f'<meta property="og:url" content="{url}">', result, count=1)
    result = result.replace("<!-- languages -->", picker(code, depth))
    if folder:
        result = re.sub(r'(src|href)="site/', r'\1="../site/', result)
        # Screenshots in this language.
        result = re.sub(r'src="screenshots/([\w-]+)\.png"', rf'src="../shots/{folder}/\1.jpg"', result)
    return result


def build(out):
    out = Path(out)
    page = PAGE.read_text()
    for code, folder, _, _ in LANGUAGES:
        target = out / folder if folder else out
        target.mkdir(parents=True, exist_ok=True)
        (target / "index.html").write_text(build_page(page, code, folder, load(code)))
    for item in (ROOT / "website").iterdir():
        if item.name in ("index.html", "i18n") or item.name.startswith("."):
            continue
        destination = out / item.name
        if item.is_dir():
            shutil.copytree(item, destination, dirs_exist_ok=True)
        else:
            shutil.copy2(item, destination)


def missing(code):
    have = load(code)
    return [text for text in texts(PAGE.read_text()) if not have.get(text)]


def check():
    problems = 0
    for code, folder, _, _ in LANGUAGES:
        if code == SOURCE:
            continue
        gaps = missing(code)
        if gaps:
            problems += 1
            print(f"{code}: {len(gaps)} pieces of text need translating, starting with {gaps[0][:60]!r}")
        for text in load(code).values():
            if "\u2014" in text:
                problems += 1
                print(f"{code}: a translation has a long dash: {text[:60]!r}")
        shots = ROOT / "website" / "shots" / folder
        for image in re.findall(r'src="screenshots/([\w-]+)\.png"', PAGE.read_text()):
            if not (shots / f"{image}.jpg").exists():
                problems += 1
                print(f"{code}: no screenshot shots/{folder}/{image}.jpg")
    if problems:
        sys.exit(1)
    print(f"The website's {len(texts(PAGE.read_text()))} pieces of text are translated into {len(LANGUAGES)} languages.")


def export(directory):
    directory = Path(directory)
    (directory / "translations").mkdir(parents=True, exist_ok=True)
    wanted = sorted({text for code, _, _, _ in LANGUAGES if code != SOURCE for text in missing(code)},
                    key=texts(PAGE.read_text()).index)
    (directory / "source.json").write_text(json.dumps(
        [{"key": text, "source": text, "comment": "Website text. Keep any HTML tags exactly as they are, translating only the words."}
         for text in wanted], ensure_ascii=False, indent=1))
    print(f"{len(wanted)} pieces of text need translating; wrote {directory / 'source.json'}")


def import_(directory):
    current = set(texts(PAGE.read_text()))
    for code, _, _, _ in LANGUAGES:
        path = Path(directory) / "translations" / f"{code}.json"
        if code == SOURCE or not path.exists():
            continue
        merged = load(code)
        merged.update({key: value for key, value in json.loads(path.read_text()).items() if key in current})
        # Drop text the page no longer has.
        merged = {key: value for key, value in merged.items() if key in current}
        I18N.mkdir(exist_ok=True)
        (I18N / f"{code}.json").write_text(json.dumps(dict(sorted(merged.items())), ensure_ascii=False, indent=1) + "\n")
        print(f"{code}: {len(merged)} pieces of text")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "build" and len(sys.argv) == 3:
        build(sys.argv[2])
    elif command == "check":
        check()
    elif command == "export" and len(sys.argv) == 3:
        export(sys.argv[2])
    elif command == "import" and len(sys.argv) == 3:
        import_(sys.argv[2])
    elif command == "list":
        for text in texts(PAGE.read_text()):
            print(repr(text))
    else:
        sys.exit(__doc__)
