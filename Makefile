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

test: import ## Tests de la sim en headless
	@$(GODOT) --headless --path . -s tests/run.gd

validate: ## Valide data/ contre data/schemas/
	@$(PYTHON) tools/validate_data.py

assets: ## Vérifie les SVG sources (Godot les importe nativement)
	@$(PYTHON) tools/lint_assets.py

check: validate assets test ## Tout ce que la CI vérifie

SEED ?= 1
playthrough: import ## Joue une partie scriptée « tout acheter » sur les vraies données
	@$(GODOT) --headless --path . -s tests/playthrough.gd -- $(SEED)

balance: ## Simulation d'équilibrage (phase 2)
	@echo "TODO phase 2 : simuler N parties en headless et produire un rapport" && exit 1

export: import ## Export d'un preset : make export PRESET=macOS OUT=build/macos/launchyard.zip
	@mkdir -p $(dir $(OUT))
	$(GODOT) --headless --path . --export-release "$(PRESET)" $(OUT)

run: import ## Lance le jeu
	$(GODOT) --path .
