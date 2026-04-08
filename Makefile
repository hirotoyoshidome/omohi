ZIG ?= zig
BUILD ?= $(ZIG) build
FMT ?= $(ZIG) fmt

# If you have multiple packages or want options:
#   make test OPTIMIZE=ReleaseSafe
OPTIMIZE ?= Debug

.PHONY: help test test-smoke test-e2e-matrix test-contract test-reliability test-completion perf-baseline fmt fmt-check lint build docs docs-check check clean

help:
	@echo "Targets:"
	@echo "  make test       - run tests (zig build test)"
	@echo "  make test-smoke - run the post-merge smoke CLI scenario"
	@echo "  make test-e2e-matrix - run the full scheduled CLI matrix"
	@echo "  make test-contract - run CLI exit-code and parser contract checks"
	@echo "  make test-reliability - run CLI reliability checks for LOCK and staged corruption"
	@echo "  make test-completion - run shell completion checks"
	@echo "  make perf-baseline - run scheduled-size performance baseline scenarios"
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

test-smoke: build
	./.github/scripts/omohi_smoke.sh ./zig-out/bin/omohi

test-e2e-matrix: build
	./.github/scripts/omohi_e2e_matrix.sh ./zig-out/bin/omohi

test-contract: build
	./.github/scripts/omohi_contract.sh ./zig-out/bin/omohi

test-reliability: build
	./.github/scripts/omohi_reliability.sh ./zig-out/bin/omohi

test-completion:
	./.github/scripts/omohi_completion.sh

perf-baseline: build
	./.github/scripts/omohi_perf_baseline.sh ./zig-out/bin/omohi

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

check: fmt-check lint test test-contract test-reliability test-completion docs-check

clean:
	rm -rf zig-cache .zig-cache zig-out
