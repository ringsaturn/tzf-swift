// Benchmark boilerplate generated by Benchmark

import Benchmark
import Cities
import SwiftTimeZoneLookup
import tzf

let benchmarks: @Sendable () -> Void = {
  Benchmark(
    "DefaultFinder.getTimezone.random.1_million", configuration: .init(metrics: BenchmarkMetric.all)
  ) { benchmark in
    let cities = try Cities()
    let finder = try DefaultFinder()
    for _ in benchmark.scaledIterations {
      for _ in 0..<1_000_000 {
        let randomCity = cities.getRandomCity()!
        let lng = Double(randomCity.lng) ?? 0.0
        let lat = Double(randomCity.lat) ?? 0.0
        _ = try finder.getTimezone(lng: lng, lat: lat)
      }
    }
  }

  Benchmark(
    "OtherPackageToCompare.SwiftTimeZoneLookup.simple.random.10_thousand", configuration: .init(metrics: BenchmarkMetric.all)
  ) { benchmark in
    let cities = try Cities()
    let database = try SwiftTimeZoneLookup()
    for _ in benchmark.scaledIterations {
      for _ in 0..<10000 {
        let randomCity = cities.getRandomCity()!
        let lng = Float(randomCity.lng) ?? 0.0
        let lat = Float(randomCity.lat) ?? 0.0
        _ = database.simple(latitude: lat, longitude: lng)
      }
    }
  }

  Benchmark(
    "OtherPackageToCompare.SwiftTimeZoneLookup.lookup.random.10_thousand", configuration: .init(metrics: BenchmarkMetric.all)
  ) { benchmark in
    let cities = try Cities()
    let database = try SwiftTimeZoneLookup()
    for _ in benchmark.scaledIterations {
      for _ in 0..<10000 {
        let randomCity = cities.getRandomCity()!
        let lng = Float(randomCity.lng) ?? 0.0
        let lat = Float(randomCity.lat) ?? 0.0
        _ = database.lookup(latitude: lat, longitude: lng)
      }
    }
  }
}
