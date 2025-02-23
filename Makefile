build:
	swift build

test:
	swift test -c release

bench:
	swift package benchmark --target TimezoneFinderBenchmarks
