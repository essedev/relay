.DEFAULT_GOAL := help
SWIFT := swift

.PHONY: help install build run cli test lint format check clean bundle run-app

APP := .build/Relay.app

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

bundle: ## Assembla Relay.app (release, firmato ad-hoc). Serve per le notifiche (bundle id)
	$(SWIFT) build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/relay $(APP)/Contents/MacOS/relay
	cp bundle/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "built $(APP)"

run-app: bundle ## Assembla e avvia Relay.app (notifiche attive: gira dal bundle)
	open $(APP)

clean: ## Pulisce gli artifacts di build
	$(SWIFT) package clean
	rm -rf .build
