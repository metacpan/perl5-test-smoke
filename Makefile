# CoreSmoke 2.0 — common build / run / test targets.
#
#   make             # show help
#   make build       # install brew + cpan dependencies
#   make test        # run the test suite
#   make dev         # start morbo (dev server with auto-reload)
#   make start       # start hypnotoad (production-like)
#   make import SRC=csdb.psql   # import a legacy pg_dump into data/smoke.db
#
# On macOS, `build` ensures required brew packages are installed before
# invoking cpan to install missing Perl modules from cpanfile.

SHELL       := /bin/bash
PERL        ?= perl
PROVE       ?= prove
HYPNOTOAD   ?= hypnotoad
MORBO       ?= morbo
PERLCRITIC  ?= perlcritic
COVER       ?= cover

UNAME_S     := $(shell uname -s)
BREW_PKGS   := xz

APP         := script/smoke
DB_PATH     ?= data/smoke.db
DEV_DB_PATH ?= data/development.db
REPORTS_DIR ?= data/reports
SRC         ?=

# Every target in this Makefile is for local-dev use (developer machine,
# repo checkout). The Docker image runs script/smoke prefork directly
# from CMD and is unaffected. Tests override MOJO_MODE=test inside
# TestApp.pm before constructing Test::Mojo.
export MOJO_MODE := development

.DEFAULT_GOAL := help

.PHONY: help build deps brew-deps cpan-deps \
        test critic cover \
        dev start stop reload \
        migrate \
        import import-fresh dev-db dev-db-fresh \
        clean clean-cover distclean check-src

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help:
	@echo "CoreSmoke 2.0 — make targets"
	@echo ""
	@echo "  build         Install brew packages (macOS) and cpan modules from cpanfile"
	@echo "  deps          Alias for build"
	@echo "  brew-deps     Install only the macOS brew packages"
	@echo "  cpan-deps     Install only the cpan modules from cpanfile"
	@echo ""
	@echo "  dev           Run the app under morbo (auto-reload, dev mode)"
	@echo "  start         Start hypnotoad (production-like, port 3000)"
	@echo "  stop          Stop hypnotoad"
	@echo "  reload        Hot-reload hypnotoad (re-exec workers)"
	@echo "  migrate       Create / upgrade data/development.db schema"
	@echo ""
	@echo "  test          Run the full test suite (prove -lr t/)"
	@echo "  critic        Run perlcritic at severity 5 over lib/ and script/"
	@echo "  cover         Run tests under Devel::Cover and emit a report"
	@echo ""
	@echo "  import        Import a legacy pg_dump into the prod DB"
	@echo "                  (data/smoke.db):  make import SRC=csdb.psql"
	@echo "  import-fresh  Same as import but wipes data/smoke.db first"
	@echo "  dev-db        Import a legacy pg_dump into the development DB"
	@echo "                  (data/development.db):  make dev-db SRC=csdb.psql"
	@echo "  dev-db-fresh  Same as dev-db but wipes data/development.db first"
	@echo ""
	@echo "  clean         Remove cover_db and other build artifacts"
	@echo "  distclean     clean + remove data/ (DESTROYS the local DB)"

# ---------------------------------------------------------------------------
# Dependency installation
# ---------------------------------------------------------------------------

build: brew-deps cpan-deps
	@echo "[build] complete"

deps: build

brew-deps:
ifeq ($(UNAME_S),Darwin)
	@command -v brew >/dev/null 2>&1 \
	    || { echo "[brew-deps] homebrew not found — install from https://brew.sh"; exit 1; }
	@for pkg in $(BREW_PKGS); do \
	    if brew list --formula "$$pkg" >/dev/null 2>&1; then \
	        echo "[brew-deps] $$pkg already installed"; \
	    else \
	        echo "[brew-deps] installing $$pkg"; \
	        brew install "$$pkg" || exit 1; \
	    fi; \
	done
else
	@echo "[brew-deps] non-darwin host ($(UNAME_S)); skipping"
endif

cpan-deps:
	@$(PERL) script/install-deps

# ---------------------------------------------------------------------------
# Run targets
# ---------------------------------------------------------------------------

dev:
	exec $(MORBO) $(APP)

start:
	$(HYPNOTOAD) $(APP)

stop:
	$(HYPNOTOAD) -s $(APP)

reload:
	$(HYPNOTOAD) $(APP)

# Create / upgrade the development DB schema in place. Honors
# $SMOKE_DB_PATH if set; otherwise defaults to data/development.db.
# Idempotent: running it on an already-current DB is a no-op.
migrate:
	./script/migrate

# ---------------------------------------------------------------------------
# Test, lint, coverage
# ---------------------------------------------------------------------------

test:
	$(PROVE) -lr t/

critic:
	$(PERLCRITIC) --severity 5 lib/ script/

cover:
	$(COVER) -delete
	HARNESS_PERL_SWITCHES=-MDevel::Cover=-silent,1,+ignore,^t/ $(PROVE) -lr t/
	$(COVER)

# ---------------------------------------------------------------------------
# Legacy data import
# ---------------------------------------------------------------------------

check-src:
	@if [ -z "$(SRC)" ]; then \
	    echo "usage: make $(MAKECMDGOALS) SRC=path/to/dump.psql"; exit 2; \
	fi
	@if [ ! -r "$(SRC)" ]; then \
	    echo "cannot read SRC=$(SRC)"; exit 2; \
	fi

import: check-src
	./script/import-from-pgdump --source "$(SRC)" --target "$(DB_PATH)"

import-fresh: check-src
	./script/import-from-pgdump --source "$(SRC)" --target "$(DB_PATH)" --fresh

# Same as `import`/`import-fresh` but writes to the development DB
# (data/development.db) -- the one `make start` and `make dev` open
# while running in development mode. Use these on a fresh checkout
# to seed your dev environment from a legacy pg_dump.
dev-db: check-src
	./script/import-from-pgdump --source "$(SRC)" --target "$(DEV_DB_PATH)"

dev-db-fresh: check-src
	./script/import-from-pgdump --source "$(SRC)" --target "$(DEV_DB_PATH)" --fresh

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean: clean-cover
	@find . -name '*.swp' -delete

clean-cover:
	rm -rf cover_db

distclean: clean
	@echo "[distclean] removing $(DB_PATH)* and $(REPORTS_DIR)/"
	rm -f $(DB_PATH) $(DB_PATH)-wal $(DB_PATH)-shm
	rm -rf $(REPORTS_DIR)
