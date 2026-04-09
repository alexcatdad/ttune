SHELL := /bin/bash

.PHONY: lint lint-ci format-check smoke test test-ci sandbox-ci rust-ci ci

lint:
	shellcheck ttune lib/*.sh scripts/*.sh
	@if command -v biome >/dev/null 2>&1; then biome check .; else echo "biome not installed; skipping"; fi

lint-ci:
	shellcheck ttune lib/*.sh scripts/*.sh
	shfmt -d ttune lib/*.sh scripts/*.sh
	npx --yes @biomejs/biome check .

format-check:
	shfmt -d ttune lib/*.sh scripts/*.sh
	npx --yes @biomejs/biome check .

smoke:
	chmod +x ttune
	./ttune detect --json >/dev/null
	./ttune version >/dev/null

test: smoke
	@if command -v bats >/dev/null 2>&1; then bats test; else echo "bats not installed; smoke only"; fi

test-ci: smoke
	bats test

sandbox-ci:
	chmod +x scripts/ci_sandbox_e2e.sh
	./scripts/ci_sandbox_e2e.sh

rust-ci:
	cargo check --manifest-path crates/ttune-bench/Cargo.toml

ci: lint-ci test-ci sandbox-ci rust-ci
