#!/usr/bin/env python3
"""Valide data/*.json : schéma JSON + références croisées + unicité des ids.

Sortie courte par défaut (une ligne si tout va bien), détail avec --verbose.
Code de sortie 1 si au moins une erreur.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SCHEMAS = DATA / "schemas"


def load(path: Path, errors: list[str]) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"{path.name}: JSON invalide ligne {exc.lineno} ({exc.msg})")
        return None


def check_schemas(errors: list[str]) -> dict[str, dict]:
    docs: dict[str, dict] = {}
    for path in sorted(DATA.glob("*.json")):
        schema_path = SCHEMAS / f"{path.stem}.schema.json"
        if not schema_path.exists():
            errors.append(f"{path.name}: aucun schéma ({schema_path.relative_to(ROOT)})")
            continue
        doc = load(path, errors)
        schema = load(schema_path, errors)
        if doc is None or schema is None:
            continue
        for err in Draft202012Validator(schema).iter_errors(doc):
            where = "/".join(str(p) for p in err.absolute_path) or "(racine)"
            errors.append(f"{path.name}: {where}: {err.message}")
        docs[path.stem] = doc
    return docs


def ids(docs: dict, key: str, errors: list[str]) -> set[str]:
    seen: set[str] = set()
    for item in docs.get(key, {}).get(key, []):
        if not isinstance(item, dict) or "id" not in item:
            continue
        if item["id"] in seen:
            errors.append(f"{key}.json: id dupliqué '{item['id']}'")
        seen.add(item["id"])
    return seen


def check_references(docs: dict, errors: list[str]) -> None:
    components = ids(docs, "components", errors)
    facilities = ids(docs, "facilities", errors)
    ids(docs, "suppliers", errors)
    for supplier in docs.get("suppliers", {}).get("suppliers", []):
        for entry in supplier.get("catalog", []):
            if entry.get("component_id") not in components:
                errors.append(
                    f"suppliers.json: {supplier.get('id')} vend un composant inconnu "
                    f"'{entry.get('component_id')}'")
    for facility_id in docs.get("start", {}).get("facilities", []):
        if facility_id not in facilities:
            errors.append(f"start.json: installation inconnue '{facility_id}'")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--verbose", action="store_true", help="liste les fichiers validés")
    args = parser.parse_args()

    errors: list[str] = []
    docs = check_schemas(errors)
    check_references(docs, errors)

    if args.verbose:
        for name in docs:
            print(f"  lu : {name}.json")
    for error in errors:
        print(f"ERREUR {error}")
    print(f"validate: {len(docs)} fichiers, {len(errors)} erreurs")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
