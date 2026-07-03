.DEFAULT_GOAL := help
SWIFT := swift

# Versione = source of truth in ./VERSION (semver). Iniettata nel bundle al build.
VERSION := $(shell cat VERSION)
# Identita di firma per codesign. '-' = ad-hoc (default). Per un self-signed stabile
# (identita costante tra le build: niente 'Apri comunque' ricorrente, notifiche non decadono)
# passare il nome del certificato: make bundle SIGN_IDENTITY="Relay Self-Signed".
SIGN_IDENTITY ?= -

.PHONY: help install build run cli test lint format check clean bundle run-app dmg install-app icon release

APP := .build/Relay.app
DMG := .build/Relay-$(VERSION).dmg

help: ## Mostra questo aiuto
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

install: ## Risolve le dipendenze
	$(SWIFT) package resolve

build: ## Build debug
	$(SWIFT) build

run: ## Avvia l'app
	$(SWIFT) run relay

cli: ## Avvia la CLI (uso: make cli ARGS="hooks status")
	$(SWIFT) run relay-cli $(ARGS)

test: ## Esegue i test
	$(SWIFT) test

format: ## Formatta il codice (SwiftFormat, scrive)
	@command -v swiftformat >/dev/null 2>&1 || { echo "swiftformat mancante: brew install swiftformat"; exit 1; }
	swiftformat .

lint: ## Lint (SwiftFormat --lint + SwiftLint --strict)
	@command -v swiftformat >/dev/null 2>&1 || { echo "swiftformat mancante: brew install swiftformat"; exit 1; }
	@command -v swiftlint  >/dev/null 2>&1 || { echo "swiftlint mancante: brew install swiftlint"; exit 1; }
	swiftformat --lint .
	swiftlint lint --strict

check: lint build test ## Giro completo qualità (definition of done)

bundle: ## Assembla Relay.app (release, firma $(SIGN_IDENTITY), versione da ./VERSION)
	$(SWIFT) build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/relay $(APP)/Contents/MacOS/relay
	cp bundle/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP)/Contents/Info.plist
	cp bundle/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign $(SIGN_IDENTITY) $(APP)
	@echo "built $(APP) (v$(VERSION), sign=$(SIGN_IDENTITY))"

run-app: bundle ## Assembla e avvia Relay.app (notifiche attive: gira dal bundle)
	open $(APP)

icon: ## Rigenera bundle/AppIcon.icns dal generatore Core Graphics
	@tmp=$$(mktemp -d); \
	$(SWIFT) bundle/make-icon.swift $$tmp/icon-1024.png; \
	iconset=$$tmp/AppIcon.iconset; mkdir -p $$iconset; \
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s $$tmp/icon-1024.png --out $$iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) $$tmp/icon-1024.png --out $$iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done; \
	iconutil -c icns $$iconset -o bundle/AppIcon.icns; \
	echo "rigenerata bundle/AppIcon.icns"

dmg: bundle ## Crea .build/Relay-$(VERSION).dmg (installer: senza Developer ID, primo avvio con 'Apri comunque')
	rm -rf .build/dmg && mkdir -p .build/dmg
	cp -R $(APP) .build/dmg/Relay.app
	ln -s /Applications .build/dmg/Applications
	rm -f $(DMG)
	hdiutil create -volname Relay -srcfolder .build/dmg -ov -format UDZO $(DMG)
	rm -rf .build/dmg
	@echo "built $(DMG)"

install-app: bundle ## Installa Relay.app in /Applications (uso locale)
	rm -rf /Applications/Relay.app
	cp -R $(APP) /Applications/Relay.app
	@echo "installed /Applications/Relay.app"

release: ## Pubblica la release corrente (VERSION): dmg -> GitHub Release -> aggiorna il tap brew
	SIGN_IDENTITY="$(SIGN_IDENTITY)" ./scripts/release.sh

clean: ## Pulisce gli artifacts di build
	$(SWIFT) package clean
	rm -rf .build
