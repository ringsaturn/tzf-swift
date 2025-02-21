import Foundation
import Testing
@testable import tzf

// PreindexFinder Tests
@Test func validCoordinates() async throws {
    // Load test data
    let testDataPath = Bundle.module.path(
        forResource: "combined-with-oceans.reduce.preindex", ofType: "pb")!
    let data = try! Data(contentsOf: URL(fileURLWithPath: testDataPath))
    let finder = try! PreindexFinder(data: data)

    // Test for Beijing
    let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
    #expect(timezone == "Asia/Shanghai")

    // Test for multiple results
    let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
    #expect(timezones.count == 2)
}

@Test func invalidCoordinates() async throws {
    // Load test data
    let url = Bundle.module.url(
        forResource: "combined-with-oceans.reduce.preindex", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! PreindexFinder(data: data)

    // Test invalid longitude
    #expect(throws: TZFError.invalidCoordinates) {
        try finder.getTimezone(lng: 181.0, lat: 0.0)
    }

    // Test invalid latitude
    #expect(throws: TZFError.invalidCoordinates) {
        try finder.getTimezone(lng: 0.0, lat: 91.0)
    }
}

@Test func dataVersion() async throws {
    // Load test data
    let url = Bundle.module.url(
        forResource: "combined-with-oceans.reduce.preindex", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! PreindexFinder(data: data)

    #expect(!finder.dataVersion().isEmpty)
}

// Finder Tests
@Test func finderValidCoordinates() async throws {
    // Load test data
    let url = Bundle.module.url(forResource: "combined-with-oceans.reduce", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! Finder(data: data)

    // Test for Beijing
    let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
    #expect(timezone == "Asia/Shanghai")

    // Test for multiple results
    let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
    #expect(!timezones.isEmpty)
}

@Test func finderInvalidCoordinates() async throws {
    // Load test data
    let url = Bundle.module.url(forResource: "combined-with-oceans.reduce", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! Finder(data: data)

    // Test invalid longitude
    #expect(throws: FinderError.noTimezoneFound) {
        try finder.getTimezone(lng: 181.0, lat: 0.0)
    }

    // Test invalid latitude
    #expect(throws: FinderError.noTimezoneFound) {
        try finder.getTimezone(lng: 0.0, lat: 91.0)
    }
}

@Test func finderDataVersion() async throws {
    // Load test data
    let url = Bundle.module.url(forResource: "combined-with-oceans.reduce", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! Finder(data: data)

    #expect(!finder.dataVersion().isEmpty)
}

@Test func finderEdgeCases() async throws {
    // Load test data
    let url = Bundle.module.url(forResource: "combined-with-oceans.reduce", withExtension: "pb")!
    let data = try! Data(contentsOf: url)
    let finder = try! Finder(data: data)

    // Test International Date Line
    let timezone1 = try finder.getTimezone(lng: 180.0, lat: 0.0)
    #expect(!timezone1.isEmpty)

    let timezone2 = try finder.getTimezone(lng: -180.0, lat: 0.0)
    #expect(!timezone2.isEmpty)

    let timezone3 = try finder.getTimezone(lng: 0.0, lat: -90.0)
    #expect(timezone3 == "Antarctica/McMurdo")

    let timezone4 = try finder.getTimezone(lng: 0.0, lat: 0.0)
    #expect(timezone4 == "Etc/GMT")
}

@Test func defaultFinderValidCoordinates() async throws {
    // Load test data
    let preindexUrl = Bundle.module.url(
        forResource: "combined-with-oceans.reduce.preindex", withExtension: "pb")!
    let preindexData = try! Data(contentsOf: preindexUrl)
    let reduceUrl = Bundle.module.url(
        forResource: "combined-with-oceans.reduce", withExtension: "pb")!
    let reduceData = try! Data(contentsOf: reduceUrl)
    let finder = try! DefaultFinder(preindexData: preindexData, reduceData: reduceData)

    // Test for Beijing
    let timezone = try finder.getTimezone(lng: 116.3833, lat: 39.9167)
    #expect(timezone == "Asia/Shanghai")

    // Test for multiple results
    let timezones = try finder.getTimezones(lng: 87.5703, lat: 43.8146)
    #expect(!timezones.isEmpty)
}
