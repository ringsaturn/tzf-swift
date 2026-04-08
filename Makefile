.PHONY: build test bench fmt pb sync docs docs-subpath

build:
	swift build

test:
	swift test -c release

bench:
	swift package benchmark --target TimezoneFinderBenchmarks

fmt:
	swift format --in-place --recursive Sources Tests Examples Benchmarks

pb:
	buf generate

sync:
	git submodule update
	cp tzf-rel-lite/combined-with-oceans.reduce.bin Sources/Resources/combined-with-oceans.reduce.bin
	cp tzf-rel-lite/combined-with-oceans.reduce.preindex.bin Sources/Resources/combined-with-oceans.reduce.preindex.bin

DOCS_DIR ?= docs
DOCS_TARGET ?= tzf
DOCS_BASE_PATH ?=

docs:
	swift package --allow-writing-to-directory ./$(DOCS_DIR) generate-documentation \
		--target $(DOCS_TARGET) \
		--disable-indexing \
		--transform-for-static-hosting \
		--output-path ./$(DOCS_DIR)

docs-subpath:
	@test -n "$(DOCS_BASE_PATH)" || (echo "DOCS_BASE_PATH is required, example: make docs-subpath DOCS_BASE_PATH=tzf-swift" && exit 1)
	swift package --allow-writing-to-directory ./$(DOCS_DIR) generate-documentation \
		--target $(DOCS_TARGET) \
		--disable-indexing \
		--transform-for-static-hosting \
		--hosting-base-path $(DOCS_BASE_PATH) \
		--output-path ./$(DOCS_DIR)

run-demo:
	swift run demo
