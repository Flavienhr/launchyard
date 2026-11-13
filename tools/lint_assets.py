#!/usr/bin/env python3
"""Vérifie les SVG de assets/src/ contre les règles de assets/CLAUDE.md et STYLE.md.

Godot importe les SVG nativement (rastérisation à l'import) : pas de rendu PNG
nécessaire. Ce script garantit seulement que les sources restent propres.
"""
from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "src"
STYLE = SRC / "STYLE.md"
NS = "{http://www.w3.org/2000/svg}"
NAME = re.compile(r"^[a-z]+_[a-z0-9_]+\.svg$")
HEX = re.compile(r"#[0-9a-fA-F]{6}\b")


def palette() -> set[str]:
    return {c.lower() for c in HEX.findall(STYLE.read_text(encoding="utf-8"))}


def lint(path: Path, colors: set[str]) -> list[str]:
    problems: list[str] = []
    rel = path.relative_to(ROOT)
    if not NAME.match(path.name):
        problems.append(f"{rel}: nom attendu categorie_nom.svg")
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        return [f"{rel}: XML invalide ({exc})"]
    view_box = root.get("viewBox", "").split()
    if len(view_box) != 4 or view_box[2] != view_box[3] or float(view_box[2]) % 32:
        problems.append(f"{rel}: viewBox carré multiple de 32 requis (actuel : '{root.get('viewBox')}')")
    for tag in ("text", "image", "script", "foreignObject"):
        if next(root.iter(NS + tag), None) is not None:
            problems.append(f"{rel}: balise <{tag}> interdite")
    for color in {c.lower() for c in HEX.findall(path.read_text(encoding="utf-8"))} - colors:
        problems.append(f"{rel}: couleur {color} hors palette (voir STYLE.md)")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.parse_args()
    colors = palette()
    files = sorted(SRC.rglob("*.svg"))
    problems = [p for f in files for p in lint(f, colors)]
    for problem in problems:
        print(f"ERREUR {problem}")
    print(f"assets: {len(files)} SVG, {len(problems)} erreurs")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
