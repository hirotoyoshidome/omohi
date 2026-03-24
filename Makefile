ZIG ?= zig
BUILD ?= $(ZIG) build
FMT ?= $(ZIG) fmt

# If you have multiple packages or want options:
#   make test OPTIMIZE=ReleaseSafe
OPTIMIZE ?= Debug

.PHONY: help test fmt fmt-check lint build docs docs-check check clean

help:
	@echo "Targets:"
	@echo "  make test       - run tests (zig build test)"
	@echo "  make fmt        - format source files (zig fmt .)"
	@echo "  make fmt-check  - check formatting (zig fmt --check .)"
	@echo "  make lint       - lightweight lint (fmt-check + compile)"
	@echo "  make build      - compile (zig build)"
	@echo "  make docs       - generate CLI markdown and man docs (zig build docs)"
	@echo "  make docs-check - fail if generated CLI docs are dirty"
	@echo "  make check      - fmt-check + lint + test + docs-check"
	@echo "  make clean      - clean build artifacts"

test:
	$(BUILD) test -Doptimize=$(OPTIMIZE) --summary all

fmt:
	$(FMT) .

fmt-check:
	$(FMT) --check .

# Zig doesn't have a canonical linter.
# Here "lint" means: formatting is clean + code compiles.
lint: fmt-check build

build:
	$(BUILD) -Doptimize=$(OPTIMIZE)

docs:
	$(BUILD) docs -Doptimize=$(OPTIMIZE)

docs-check: docs
	git diff --exit-code -- docs/cli.md docs/man/omohi.1

check: fmt-check lint test docs-check

clean:
	rm -rf zig-cache .zig-cache zig-out
