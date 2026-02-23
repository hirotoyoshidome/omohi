# Makefile for Zig projects
# Usage:
#   make test
#   make fmt
#   make lint
#   make check   (fmt-check + lint + test)

ZIG ?= zig
BUILD ?= $(ZIG) build
FMT ?= $(ZIG) fmt

# If you have multiple packages or want options:
#   make test OPTIMIZE=ReleaseSafe
OPTIMIZE ?= Debug

.PHONY: help test fmt fmt-check lint build check clean

help:
	@echo "Targets:"
	@echo "  make test       - run tests (zig build test)"
	@echo "  make fmt        - format source files (zig fmt .)"
	@echo "  make fmt-check  - check formatting (zig fmt --check .)"
	# @echo "  make lint       - lightweight lint (fmt-check + compile)"
	# @echo "  make build      - compile (zig build)"
	# @echo "  make check      - fmt-check + lint + test"
	# @echo "  make clean      - clean build artifacts (zig build clean)"

test:
	$(ZIG) test src/tests.zig -Doptimize=$(OPTIMIZE)

fmt:
	$(FMT) .

fmt-check:
	$(FMT) --check .

# # Zig doesn't have a canonical linter.
# # Here "lint" means: formatting is clean + code compiles.
# lint: fmt-check build

# build:
# 	$(BUILD) -Doptimize=$(OPTIMIZE)

# check: fmt-check lint test

# clean:
# 	$(BUILD) clean
