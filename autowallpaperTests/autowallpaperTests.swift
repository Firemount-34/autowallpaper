//
//  autowallpaperTests.swift
//  autowallpaperTests
//
//  Created by wangcan on 2026/11/18.
//

import XCTest
@testable import autowallpaper

final class autowallpaperTests: XCTestCase {
    func testSolarCalculationForBeijing() {
        let tz = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let events = SolarCalculator.calculate(
            for: Date(),
            latitude: 39.9042,
            longitude: 116.4074,
            timeZone: tz
        )

        XCTAssertTrue(events.sunriseMinutes > 240 && events.sunriseMinutes < 540, "北京日出时间应在合理范围内")
        XCTAssertTrue(events.sunsetMinutes > 960 && events.sunsetMinutes < 1260, "北京日落时间应在合理范围内")
        XCTAssertTrue(events.solarNoonMinutes > events.sunriseMinutes && events.solarNoonMinutes < events.sunsetMinutes)

        let schedule = events.toTimelineSchedule()
        XCTAssertLessThan(schedule.sunriseMinutes, schedule.morningMinutes)
        XCTAssertLessThan(schedule.morningMinutes, schedule.dayMinutes)
        XCTAssertLessThan(schedule.dayMinutes, schedule.sunsetMinutes)
        XCTAssertLessThan(schedule.sunsetMinutes, schedule.nightMinutes)
    }

    func testAerialCatalogLoaded() {
        let catalog = AerialCatalog.shared
        XCTAssertFalse(catalog.allAssets.isEmpty, "系统航拍列表不应为空")
        XCTAssertFalse(catalog.locationSets.isEmpty, "精选地点组不应为空")
    }
}
