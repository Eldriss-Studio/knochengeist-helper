"""Builds the Godot manual index the helper downloads: one passage per section of the manual's
pages (godot-docs, one branch per minor version), as plain words with the code kept, each with its
link. The class reference (classes/) is left out: the helper builds that from the person's Godot.

  python3 manual_index.py <godot-docs folder> <version, e.g. 4.7> <out folder>

The Godot manual is by Juan Linietsky, Ariel Manzur and the Godot community, CC BY 3.0."""
import gzip, json, re, sys
from pathlib import Path

CREDIT = "Godot Engine documentation by Juan Linietsky, Ariel Manzur and the Godot community, CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Split into sections, with markup removed."
UNDERLINE = re.compile(r"^([=\-~^\"'`#*+<>_:.])\1{2,}\s*$")
KEPT = 1500            # characters of a section's text
SKIPPED = {"classes", "_build", "_extensions", "_static", "_templates", "_tools", "img"}


def _sections(text: str) -> list[tuple[str, list[str]]]:
    """The page as (heading, lines) pairs; the lines before the first heading go with ''."""
    lines = text.splitlines()
    out: list[tuple[str, list[str]]] = [("", [])]
    i = 0
    while i < len(lines):
        line = lines[i]
        over = UNDERLINE.match(line) and i + 2 < len(lines) and UNDERLINE.match(lines[i + 2]) and lines[i + 1].strip()
        if over:
            out.append((lines[i + 1].strip(), []))
            i += 3
            continue
        if line.strip() and i + 1 < len(lines) and UNDERLINE.match(lines[i + 1]) and len(lines[i + 1].strip()) >= len(line.strip()):
            out.append((line.strip(), []))
            i += 2
            continue
        out[-1][1].append(line)
        i += 1
    return out


def _labels(pages: dict[str, str]) -> dict[str, str]:
    """`.. _doc_x:` labels, each to the title of the heading that follows it."""
    found: dict[str, str] = {}
    for text in pages.values():
        lines = text.splitlines()
        for i, line in enumerate(lines):
            label = re.match(r"^\.\. _([\w\-]+):\s*$", line)
            if not label:
                continue
            for j in range(i + 1, min(i + 6, len(lines) - 1)):
                if lines[j].strip() and not lines[j].startswith(".. ") and not UNDERLINE.match(lines[j]):
                    found[label.group(1)] = lines[j].strip()
                    break
    return found


def _plain(lines: list[str], labels: dict[str, str]) -> str:
    kept: list[str] = []
    skipping = -1                  # the indent of a block being left out (a comment, a table of contents)
    for line in lines:
        bare = line.strip()
        indent = len(line) - len(line.lstrip())
        if skipping >= 0:
            if not bare or indent > skipping:
                continue
            skipping = -1
        if re.match(r"^\.\. _[\w\-]+:\s*$", bare) or re.match(r"^:[\w\-]+:(\s|$)", bare):
            continue                   # a link target, or the page's own settings
        if re.match(r"^\.\. (toctree|image|figure|raw|only|rst-class|highlight|include|seealso|video|tabs)::", bare) or (bare.startswith(".. ") and "::" not in bare) or bare == ".." or re.match(r"^\.\. \|[^|]+\|", bare):
            skipping = indent          # left out with everything indented under it
            if re.match(r"^\.\. (seealso|tabs)::", bare):
                skipping = -1          # their contents are kept
            continue
        if re.match(r"^\.\. [\w\-]+::", bare):
            rest = re.sub(r"^\.\. [\w\-]+::\s*", "", bare)
            if re.match(r"^\.\. (code-tab|code-block|code)::", bare):
                rest = ""              # the language name
            if rest:
                kept.append(" " * indent + rest)
            continue
        kept.append(line.rstrip())
    text = "\n".join(kept)
    text = re.sub(r":ref:`([^`<]+?)\s*<[^`>]+>`", r"\1", text)
    text = re.sub(r":ref:`([^`]+)`", lambda m: labels.get(m.group(1), m.group(1).replace("doc_", "").replace("_", " ")), text)
    text = re.sub(r":\w+:`([^`<]+?)\s*<[^`>]+>`", r"\1", text)
    text = re.sub(r":\w+:`([^`]+)`", r"\1", text)
    text = re.sub(r"`([^`<]+?)\s*<[^`>]+>`_+", r"\1", text)
    text = re.sub(r"\|[\w\-]+\|", "", text)     # a picture's place in the text
    text = text.replace("``", "").replace("**", "")
    text = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"\1", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return re.sub(r"[ \t]+\n", "\n", text).strip()


def _anchor(heading: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", heading.lower()).strip("-")


def build(docs: Path, version: str, out: Path) -> Path:
    pages = {p.relative_to(docs).as_posix(): p.read_text(encoding="utf-8", errors="replace") for p in sorted(docs.rglob("*.rst")) if not (SKIPPED & set(p.relative_to(docs).parts))}
    labels = _labels(pages)
    passages = []
    for path, text in pages.items():
        url = f"https://docs.godotengine.org/en/{version}/{path[:-4]}.html"
        sections = _sections(text)
        page_title = next((heading for heading, _ in sections if heading), path)
        for n, (heading, lines) in enumerate(sections):
            body = _plain(lines, labels)
            if not body:
                continue
            first = heading == page_title and n == next(i for i, (h, _) in enumerate(sections) if h)
            passages.append({
                "title": page_title if first or not heading else f"{page_title} > {heading}",
                "text": body[:KEPT],
                "url": url if first or not heading else f"{url}#{_anchor(heading)}",
            })
    out.mkdir(parents=True, exist_ok=True)
    made = out / f"manual-{version}.json.gz"
    made.write_bytes(gzip.compress(json.dumps({"version": version, "pages": len(pages), "credit": CREDIT, "passages": passages}, ensure_ascii=False).encode()))
    return made


if __name__ == "__main__":
    print(build(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])))
