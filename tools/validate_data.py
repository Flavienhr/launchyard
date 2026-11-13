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
    launchers = ids(docs, "launchers", errors)
    recipes = ids(docs, "recipes", errors)
    ids(docs, "suppliers", errors)
    facility_by_id = {
        f["id"]: f for f in docs.get("facilities", {}).get("facilities", [])
        if isinstance(f, dict) and "id" in f
    }

    # Une installation constructible sans max_count serait silencieusement
    # inconstructible (la sim lit max_count avec 0 par défaut).
    for fid, facility in facility_by_id.items():
        if facility.get("buildable") and "max_count" not in facility:
            errors.append(f"facilities.json: {fid} est buildable mais n'a pas de max_count")

    for supplier in docs.get("suppliers", {}).get("suppliers", []):
        for entry in supplier.get("catalog", []):
            if entry.get("component_id") not in components:
                errors.append(
                    f"suppliers.json: {supplier.get('id')} vend un composant inconnu "
                    f"'{entry.get('component_id')}'")

    for recipe in docs.get("recipes", {}).get("recipes", []):
        rid = recipe.get("id")
        target = facility_by_id.get(recipe.get("facility_type"), {})
        for field in ("slots", "productivity_per_slot"):
            if target and field not in target:
                errors.append(f"recipes.json: {rid} vise '{recipe.get('facility_type')}' qui n'a pas de {field}")
        if "launcher_model" in recipe.get("output", {}) and target and "launcher_capacity" not in target:
            errors.append(f"recipes.json: {rid} produit un lanceur dans '{recipe.get('facility_type')}' sans launcher_capacity")
        if recipe.get("facility_type") not in facilities:
            errors.append(
                f"recipes.json: {rid} utilise une installation inconnue "
                f"'{recipe.get('facility_type')}'")
        for component_id in recipe.get("inputs", {}):
            if component_id not in components:
                errors.append(f"recipes.json: {rid} consomme un composant inconnu '{component_id}'")
        output = recipe.get("output", {})
        if "component_id" in output and output["component_id"] not in components:
            errors.append(f"recipes.json: {rid} produit un composant inconnu '{output['component_id']}'")
        if "launcher_model" in output and output["launcher_model"] not in launchers:
            errors.append(f"recipes.json: {rid} produit un lanceur inconnu '{output['launcher_model']}'")

    # Lien recette -> lanceur, dans les deux sens.
    produced_by = {
        r.get("output", {}).get("launcher_model"): r.get("id")
        for r in docs.get("recipes", {}).get("recipes", [])
        if "launcher_model" in r.get("output", {})
    }
    for launcher in docs.get("launchers", {}).get("launchers", []):
        lid = launcher.get("id")
        if launcher.get("recipe_id") not in recipes:
            errors.append(f"launchers.json: {lid} pointe une recette inconnue '{launcher.get('recipe_id')}'")
        elif produced_by.get(lid) != launcher.get("recipe_id"):
            errors.append(
                f"launchers.json: {lid} a pour recette '{launcher.get('recipe_id')}' "
                f"qui ne produit pas ce lanceur")

    # Contrats : bornes cohérentes et réputation dans [min, max].
    # (La validation des ids d'orbite viendra avec orbits.json, issue #13.)
    contracts = docs.get("contracts", {})
    for tpl in contracts.get("templates", []):
        tid = tpl.get("id")
        if tpl.get("mass_min_kg", 0) > tpl.get("mass_max_kg", 0):
            errors.append(f"contracts.json: {tid} mass_min_kg > mass_max_kg")
        if tpl.get("deadline_min_days", 0) > tpl.get("deadline_max_days", 0):
            errors.append(f"contracts.json: {tid} deadline_min_days > deadline_max_days")
    if contracts:
        lo, start_rep, hi = (contracts.get(k, 0) for k in ("reputation_min", "reputation_start", "reputation_max"))
        if not lo <= start_rep <= hi:
            errors.append("contracts.json: reputation_start hors de [reputation_min, reputation_max]")
        if contracts.get("initial_offers", 0) > contracts.get("offer_slots", 0):
            errors.append("contracts.json: initial_offers > offer_slots")
    template_ids = [t.get("id") for t in contracts.get("templates", [])]
    for dup in sorted({t for t in template_ids if template_ids.count(t) > 1}):
        errors.append(f"contracts.json: modèle dupliqué '{dup}'")

    start = docs.get("start", {})
    for facility_id in start.get("facilities", []):
        if facility_id not in facilities:
            errors.append(f"start.json: installation inconnue '{facility_id}'")
    for facility_id, count in start.get("assignments", {}).items():
        if facility_id not in start.get("facilities", []):
            errors.append(f"start.json: affectation sur une installation absente des départs '{facility_id}'")
            continue
        slots = facility_by_id.get(facility_id, {}).get("slots", 0)
        if count > slots:
            errors.append(
                f"start.json: {count} techniciens affectés à '{facility_id}' "
                f"qui n'a que {slots} postes")
    total = sum(start.get("assignments", {}).values())
    if "technicians" in start and total > start["technicians"]:
        errors.append(f"start.json: {total} techniciens affectés pour {start['technicians']} embauchés")


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
