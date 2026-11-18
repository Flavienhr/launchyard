# Godot : celui du PATH, sinon l'app macOS standard. Surcharge possible : make test GODOT=/chemin/godot
GODOT ?= $(shell command -v godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)
PYTHON := .venv/bin/python
PRESET ?= Linux
OUT ?= build/linux/launchyard.x86_64

.PHONY: setup import test validate assets balance export run check playthrough

setup: ## Crée le venv Python des outils
	python3 -m venv .venv
	.venv/bin/pip install -q -r tools/requirements.txt

import: ## Met à jour le cache Godot (classes globales, imports d'assets)
	@$(GODOT) --headless --path . --import >/dev/null 2>&1 || $(GODOT) --headless --path . --import

test: import ## Tests en headless ; échoue aussi sur toute SCRIPT ERROR (le runner ne les compte pas)
	@$(GODOT) --headless --path . -s tests/run.gd > .test_output.log 2>&1; code=$$?; \
	grep -v "^Godot Engine" .test_output.log; \
	if grep -q "SCRIPT ERROR" .test_output.log; then echo "ÉCHEC : SCRIPT ERROR pendant les tests (voir ci-dessus)"; exit 1; fi; \
	exit $$code

validate: ## Valide data/ contre data/schemas/
	@$(PYTHON) tools/validate_data.py

assets: ## Vérifie les SVG sources (Godot les importe nativement)
	@$(PYTHON) tools/lint_assets.py

check: validate assets test ## Tout ce que la CI vérifie

SEED ?= 1
playthrough: import ## Joue une partie scriptée « tout acheter » sur les vraies données
	@$(GODOT) --headless --path . -s tests/playthrough.gd -- $(SEED)

SEEDS ?= 40
DAYS ?= 240
VERBOSE ?=
balance: import ## Bot d'équilibrage : make balance [SEEDS=40] [DAYS=240|360] [VERBOSE=1]
	@$(GODOT) --headless --path . -s tests/balance.gd -- --seeds=$(SEEDS) --days=$(DAYS) $(if $(VERBOSE),--verbose)

export: import ## Export d'un preset : make export PRESET=macOS OUT=build/macos/launchyard.zip
	@mkdir -p $(dir $(OUT))
	$(GODOT) --headless --path . --export-release "$(PRESET)" $(OUT)

run: import ## Lance le jeu
	$(GODOT) --path .
