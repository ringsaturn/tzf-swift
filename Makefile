.PHONY: build test bench fmt pb sync docs docs-subpath run-demo clean

SWIFT_SCRATCH_PATH ?= $(HOME)/Library/Caches/tzf-swift/swiftpm
BENCHMARKS_SCRATCH_PATH ?= $(HOME)/Library/Caches/tzf-swift/benchmarks-swiftpm
NO_INDEX_STORE ?= 0

SWIFTPM_BUILD_FLAGS := --scratch-path $(SWIFT_SCRATCH_PATH)
BENCHMARKS_BUILD_FLAGS := --scratch-path $(BENCHMARKS_SCRATCH_PATH)

ifeq ($(NO_INDEX_STORE),1)
SWIFTPM_BUILD_FLAGS += --disable-index-store
BENCHMARKS_BUILD_FLAGS += --disable-index-store
endif

build:
	swift build $(SWIFTPM_BUILD_FLAGS)

test:
	swift test -c release $(SWIFTPM_BUILD_FLAGS)

bench:
	swift package --package-path Benchmarks $(BENCHMARKS_BUILD_FLAGS) benchmark --target TimezoneFinderBenchmarks

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
	swift package $(SWIFTPM_BUILD_FLAGS) --allow-writing-to-directory ./$(DOCS_DIR) generate-documentation \
		--target $(DOCS_TARGET) \
		--disable-indexing \
		--transform-for-static-hosting \
		--output-path ./$(DOCS_DIR)

docs-subpath:
	@test -n "$(DOCS_BASE_PATH)" || (echo "DOCS_BASE_PATH is required, example: make docs-subpath DOCS_BASE_PATH=tzf-swift" && exit 1)
	swift package $(SWIFTPM_BUILD_FLAGS) --allow-writing-to-directory ./$(DOCS_DIR) generate-documentation \
		--target $(DOCS_TARGET) \
		--disable-indexing \
		--transform-for-static-hosting \
		--hosting-base-path $(DOCS_BASE_PATH) \
		--output-path ./$(DOCS_DIR)

run-demo:
	swift run $(SWIFTPM_BUILD_FLAGS) demo

clean:
	rm -rf .build Benchmarks/.build $(SWIFT_SCRATCH_PATH) $(BENCHMARKS_SCRATCH_PATH)
