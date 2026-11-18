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

    # Chaque entrée de la recette d'un lanceur doit être vendue par au moins un
    # fournisseur : sinon le coût d'un kit (assurance, stratégie « tout acheter »)
    # serait faux sans que rien ne le signale.
    sold = {e.get("component_id") for s in docs.get("suppliers", {}).get("suppliers", [])
            for e in s.get("catalog", [])}
    recipe_by_id = {r.get("id"): r for r in docs.get("recipes", {}).get("recipes", [])}
    for launcher in docs.get("launchers", {}).get("launchers", []):
        for component_id in recipe_by_id.get(launcher.get("recipe_id"), {}).get("inputs", {}):
            if component_id not in sold:
                errors.append(f"launchers.json: {launcher.get('id')} : '{component_id}' n'est vendu par aucun fournisseur")

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
    contracts = docs.get("contracts", {})

    # Orbites : lanceurs, sites et contrats ne référencent que des ids connus.
    orbits = ids(docs, "orbits", errors)
    for launcher in docs.get("launchers", {}).get("launchers", []):
        for orbit_id in launcher.get("payload_kg", {}):
            if orbit_id not in orbits:
                errors.append(
                    f"launchers.json: {launcher.get('id')} a une capacité vers une orbite inconnue '{orbit_id}'")
    for site in docs.get("sites", {}).get("sites", []):
        sid = site.get("id")
        for orbit_id in site.get("payload_bonus_pct", {}):
            if orbit_id not in orbits:
                errors.append(f"sites.json: {sid} a un bonus vers une orbite inconnue '{orbit_id}'")
        if len(site.get("scrub_chance_by_season", [])) != len(site.get("season_names", [])):
            errors.append(f"sites.json: {sid} a un nombre de saisons différent de scrub_chance_by_season")
        for bounds in site.get("azimuth_ranges", []):
            if len(bounds) == 2 and bounds[0] > bounds[1]:
                errors.append(f"sites.json: {sid} a un intervalle d'azimut inversé {bounds}")

    for tpl in contracts.get("templates", []):
        tid = tpl.get("id")
        if "orbit" in tpl and tpl["orbit"] not in orbits:
            errors.append(f"contracts.json: {tid} vise une orbite inconnue '{tpl['orbit']}'")
        if tpl.get("mass_min_kg", 0) > tpl.get("mass_max_kg", 0):
            errors.append(f"contracts.json: {tid} mass_min_kg > mass_max_kg")
        # La sim arrondit la masse au multiple de mass_step_kg le plus proche, sans
        # recadrage : les bornes doivent donc être des multiples du pas.
        step = contracts.get("mass_step_kg", 1)
        for key in ("mass_min_kg", "mass_max_kg"):
            if tpl.get(key, 0) % step:
                errors.append(f"contracts.json: {tid} {key} n'est pas un multiple de mass_step_kg ({step})")
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

    # Faillite (spec 004) : l'alerte doit précéder la fin de partie.
    rules = docs.get("rules", {})
    if rules and rules.get("bankruptcy_warning_days", 0) >= rules.get("bankruptcy_grace_days", 0):
        errors.append("rules.json: bankruptcy_warning_days doit être < bankruptcy_grace_days")

    start = docs.get("start", {})
    site_ids = {s.get("id") for s in docs.get("sites", {}).get("sites", [])}
    if "site" in start and start["site"] not in site_ids:
        errors.append(f"start.json: site inconnu '{start['site']}'")
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

    # Prérequis de construction (spec 006, R3) : types référencés, puis absence de cycle.
    for fid, facility in facility_by_id.items():
        for req in facility.get("requires_facilities", []):
            if req not in facility_by_id:
                errors.append(f"facilities.json: {fid} requiert une installation inconnue '{req}'")

    def find_cycle(fid: str, path: list[str]) -> list[str] | None:
        for req in facility_by_id.get(fid, {}).get("requires_facilities", []):
            if req in path:
                return path[path.index(req):] + [req]
            if req in facility_by_id:
                found = find_cycle(req, path + [req])
                if found:
                    return found
        return None

    for fid in facility_by_id:
        cycle = find_cycle(fid, [fid])
        if cycle:
            errors.append(f"facilities.json: cycle de prérequis {' -> '.join(cycle)}")
            break

    # Rebut (spec 006, R4) : le plancher ne peut pas dépasser le taux de départ.
    for recipe in docs.get("recipes", {}).get("recipes", []):
        start_rate = recipe.get("scrap_rate_start", 0)
        floor_rate = recipe.get("scrap_rate_floor", 0)
        if floor_rate > start_rate:
            errors.append(
                f"recipes.json: {recipe.get('id')} a scrap_rate_floor ({floor_rate}) "
                f"> scrap_rate_start ({start_rate})")

    # Chaîne de production (spec 006, Données) : un composant non achetable consommé
    # par une recette doit être produit par au moins une recette, sinon la chaîne est morte.
    all_recipes = docs.get("recipes", {}).get("recipes", [])
    sold_ids = {e.get("component_id") for s in docs.get("suppliers", {}).get("suppliers", [])
                for e in s.get("catalog", [])}
    produced_ids = {r.get("output", {}).get("component_id") for r in all_recipes}
    consumed_ids = {c for r in all_recipes for c in r.get("inputs", {})}
    for component_id in sorted(consumed_ids - sold_ids):
        if component_id not in produced_ids:
            errors.append(
                f"recipes.json: '{component_id}' n'est vendu par aucun fournisseur "
                f"et n'est produit par aucune recette")


def check_market(docs: dict, errors: list[str]) -> None:
    """Marché et contrats d'approvisionnement (spec 007, Données et Schémas)."""
    components = ids(docs, "components", errors)
    market = docs.get("market", {})
    if market:
        if not market["index_min"] <= market["index_base"] <= market["index_max"]:
            errors.append("market.json: index_min <= index_base <= index_max non respecté")
        if market["shortage_min_periods"] > market["shortage_max_periods"]:
            errors.append("market.json: shortage_min_periods > shortage_max_periods")
        seen: set[str] = set()
        sold = {e.get("component_id")
                for s in docs.get("suppliers", {}).get("suppliers", [])
                for e in s.get("catalog", [])}
        for entry in market.get("components", []):
            cid = entry.get("id")
            if cid in seen:
                errors.append(f"market.json: composant dupliqué '{cid}'")
            seen.add(cid)
            if cid not in components:
                errors.append(f"market.json: composant inconnu '{cid}'")
            if cid not in sold:
                errors.append(f"market.json: '{cid}' n'est vendu par aucun fournisseur")

    for supplier in docs.get("suppliers", {}).get("suppliers", []):
        for entry in supplier.get("catalog", []):
            terms = entry.get("contract_terms")
            if terms and terms["min_quantity"] > terms["max_quantity"]:
                errors.append(
                    f"suppliers.json: {supplier.get('id')} / {entry.get('component_id')} : "
                    f"contract_terms min_quantity > max_quantity")

    supply = docs.get("supply_contracts", {})
    if supply:
        if supply["min_deliveries"] > supply["max_deliveries"]:
            errors.append("supply_contracts.json: min_deliveries > max_deliveries")
        tiers = supply.get("volume_discount_tiers", [])
        values = [t["min_value"] for t in tiers]
        if values != sorted(set(values)):
            errors.append("supply_contracts.json: volume_discount_tiers non triés par min_value croissant")


def overlaps(a: dict, b: dict) -> bool:
    """Deux rectangles {x, y, w, h} se recouvrent-ils (au moins une case commune) ?"""
    return a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] \
        and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]


def cells(rect: dict) -> set[tuple[int, int]]:
    return {(x, y) for x in range(rect["x"], rect["x"] + rect["w"])
            for y in range(rect["y"], rect["y"] + rect["h"])}


def check_spatial(docs: dict, errors: list[str]) -> None:
    """Carte, parcelles, emprises et positions de départ (spec 008, Schémas et validateur)."""
    facility_by_id = {
        f["id"]: f for f in docs.get("facilities", {}).get("facilities", [])
        if isinstance(f, dict) and "id" in f
    }
    maps: dict[str, dict] = {
        s["id"]: s["map"] for s in docs.get("sites", {}).get("sites", []) if "map" in s
    }

    for sid, site_map in maps.items():
        width, height = site_map["width"], site_map["height"]
        lots = site_map["lots"]
        lot_ids = [lot["id"] for lot in lots]
        for dup in sorted({i for i in lot_ids if lot_ids.count(i) > 1}):
            errors.append(f"sites.json: {sid} : parcelle dupliquée '{dup}'")
        for rect in lots + site_map["terrain"]:
            if rect["x"] + rect["w"] > width or rect["y"] + rect["h"] > height:
                errors.append(f"sites.json: {sid} : '{rect.get('id', rect.get('kind'))}' sort de la carte")
        for i, a in enumerate(lots):
            for b in lots[i + 1:]:
                if overlaps(a, b):
                    errors.append(f"sites.json: {sid} : parcelles '{a['id']}' et '{b['id']}' se recouvrent")
            for t in site_map["terrain"]:
                if overlaps(a, t):
                    errors.append(f"sites.json: {sid} : parcelle '{a['id']}' recouvre le terrain '{t['kind']}'")

    # Une carte rend l'emprise obligatoire pour chaque type d'installation.
    if maps:
        for fid, facility in facility_by_id.items():
            if "footprint" not in facility:
                errors.append(f"facilities.json: {fid} n'a pas de footprint (site avec carte)")

    start = docs.get("start", {})
    site_id = start.get("site")
    owned = start.get("owned_lots", [])
    positions = start.get("facility_positions", [])
    if "facility_positions" in start and sorted(p["facility_type"] for p in positions) != sorted(start.get("facilities", [])):
        errors.append("start.json: facility_positions ne correspond pas à facilities")

    if site_id not in maps:
        if owned:
            errors.append(f"start.json: owned_lots sans carte pour le site '{site_id}'")
        return

    site_map = maps[site_id]
    lot_by_id = {lot["id"]: lot for lot in site_map["lots"]}
    for lot_id in owned:
        if lot_id not in lot_by_id:
            errors.append(f"start.json: parcelle inconnue '{lot_id}'")
    owned_cells: set[tuple[int, int]] = set()
    for lot_id in owned:
        if lot_id in lot_by_id:
            owned_cells |= cells(lot_by_id[lot_id])

    for start_fid in start.get("facilities", []):
        if start_fid not in [p["facility_type"] for p in positions]:
            errors.append(f"start.json: installation de départ '{start_fid}' sans position")

    placed: list[tuple[str, dict]] = []
    for pos in positions:
        ftype = pos["facility_type"]
        footprint = facility_by_id.get(ftype, {}).get("footprint")
        if footprint is None:
            errors.append(f"start.json: installation '{ftype}' sans footprint")
            continue
        w, h = (footprint[1], footprint[0]) if pos["rotation"] == 1 else (footprint[0], footprint[1])
        rect = {"x": pos["x"], "y": pos["y"], "w": w, "h": h}
        if not cells(rect) <= owned_cells:
            errors.append(f"start.json: '{ftype}' en ({pos['x']}, {pos['y']}) hors des parcelles possédées")
        for other_type, other in placed:
            if overlaps(rect, other):
                errors.append(f"start.json: '{ftype}' chevauche '{other_type}'")
        placed.append((ftype, rect))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--verbose", action="store_true", help="liste les fichiers validés")
    args = parser.parse_args()

    errors: list[str] = []
    docs = check_schemas(errors)
    check_references(docs, errors)
    check_market(docs, errors)
    check_spatial(docs, errors)

    if args.verbose:
        for name in docs:
            print(f"  lu : {name}.json")
    for error in errors:
        print(f"ERREUR {error}")
    print(f"validate: {len(docs)} fichiers, {len(errors)} erreurs")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
