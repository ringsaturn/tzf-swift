build:
	swift build

test:
	swift test -c release

bench:
	swift package benchmark --target TimezoneFinderBenchmarks

fmt:
	swift format --in-place --recursive Sources Tests Examples Benchmarks

sync:
	git submodule update --init --recursive
	cp tzf-rel-lite/combined-with-oceans.reduce.pb Sources/Resources/combined-with-oceans.reduce.pb
	cp tzf-rel-lite/combined-with-oceans.reduce.preindex.pb Sources/Resources/combined-with-oceans.reduce.preindex.pb
