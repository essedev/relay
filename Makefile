.DEFAULT_GOAL := help
SWIFT := swift

# Versione = source of truth in ./VERSION (semver). Iniettata nel bundle al build.
VERSION := $(shell cat VERSION)
# Identita di firma per codesign. '-' = ad-hoc (default). Per un self-signed stabile
# (identita costante tra le build: niente 'Apri comunque' ricorrente, notifiche non decadono)
# usare il cert dedicato: SIGN_IDENTITY="Relay Self-Signed" (lo prepara scripts/setup-signing.sh;
# `make release` fa tutto da solo). L'identita e' risolta dalla search list dei keychain.
SIGN_IDENTITY ?= -

# Strumenti di lint pinnati (binari dai release GitHub, in .build/tools): CI e locale usano la
# STESSA versione, mentre `brew install` prende sempre l'ultima e ogni nuova regola rompe il lint
# senza che il codice cambi. Bumpa qui e rilancia `make tools` (lo stamp versionato forza il
# riscarico).
SWIFTFORMAT_VERSION := 0.61.1
SWIFTLINT_VERSION := 0.65.0
TOOLS_DIR := .build/tools
SWIFTFORMAT := $(TOOLS_DIR)/swiftformat
SWIFTLINT := $(TOOLS_DIR)/swiftlint
TOOLS_STAMP := $(TOOLS_DIR)/.installed-sf$(SWIFTFORMAT_VERSION)-sl$(SWIFTLINT_VERSION)

.PHONY: help install build run cli test tools lint format check clean bundle run-app dmg install-app icon release

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

tools: $(TOOLS_STAMP) ## Scarica gli strumenti di lint pinnati (.build/tools)

$(TOOLS_STAMP):
	@rm -rf $(TOOLS_DIR) && mkdir -p $(TOOLS_DIR)
	@echo "scarico swiftformat $(SWIFTFORMAT_VERSION) e swiftlint $(SWIFTLINT_VERSION)"
	@curl -fsSL https://github.com/nicklockwood/SwiftFormat/releases/download/$(SWIFTFORMAT_VERSION)/swiftformat.zip -o $(TOOLS_DIR)/sf.zip
	@unzip -oq $(TOOLS_DIR)/sf.zip -d $(TOOLS_DIR) && rm -f $(TOOLS_DIR)/sf.zip
	@curl -fsSL https://github.com/realm/SwiftLint/releases/download/$(SWIFTLINT_VERSION)/portable_swiftlint.zip -o $(TOOLS_DIR)/sl.zip
	@unzip -oq $(TOOLS_DIR)/sl.zip -d $(TOOLS_DIR) && rm -f $(TOOLS_DIR)/sl.zip
	@chmod +x $(SWIFTFORMAT) $(SWIFTLINT)
	@xattr -c $(SWIFTFORMAT) $(SWIFTLINT) 2>/dev/null || true
	@touch $(TOOLS_STAMP)

format: tools ## Formatta il codice (SwiftFormat pinnato, scrive)
	$(SWIFTFORMAT) .

lint: tools ## Lint (SwiftFormat --lint + SwiftLint --strict, versioni pinnate)
	$(SWIFTFORMAT) --lint .
	$(SWIFTLINT) lint --strict

check: lint build test ## Giro completo qualità (definition of done)

bundle: ## Assembla Relay.app (release, firma $(SIGN_IDENTITY), versione da ./VERSION)
	$(SWIFT) build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/relay $(APP)/Contents/MacOS/relay
	cp .build/release/relay-cli $(APP)/Contents/MacOS/relay-cli
	cp bundle/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP)/Contents/Info.plist
	cp bundle/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	# Il binario annidato va firmato prima del bundle esterno.
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)/Contents/MacOS/relay-cli
	codesign --force --sign "$(SIGN_IDENTITY)" $(APP)
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
	./scripts/release.sh

clean: ## Pulisce gli artifacts di build
	$(SWIFT) package clean
	rm -rf .build
