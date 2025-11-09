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
