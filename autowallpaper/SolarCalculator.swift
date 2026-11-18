//
//  SolarCalculator.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import CoreLocation

/// 每日天文日出日落计算结果
struct SolarEvents: Equatable {
    let date: Date
    let latitude: Double
    let longitude: Double
    let dawnMinutes: Int       // 晨光始 (从00:00算起的分钟数)
    let sunriseMinutes: Int    // 日出时间 (分钟数)
    let solarNoonMinutes: Int  // 正午时间 (分钟数)
    let sunsetMinutes: Int     // 日落时间 (分钟数)
    let duskMinutes: Int       // 昏影终 (分钟数)

    var sunriseTimeString: String {
        TimelineSchedule.formatMinutes(sunriseMinutes)
    }

    var solarNoonTimeString: String {
        TimelineSchedule.formatMinutes(solarNoonMinutes)
    }

    var sunsetTimeString: String {
        TimelineSchedule.formatMinutes(sunsetMinutes)
    }

    var daylightDurationString: String {
        let diff = max(0, sunsetMinutes - sunriseMinutes)
        let hours = diff / 60
        let mins = diff % 60
        return "\(hours)小时\(mins)分"
    }

    /// 根据真实日出日落时间生成5个时段的动态切换时间表
    func toTimelineSchedule(sunriseOffsetMinutes: Int = 0, sunsetOffsetMinutes: Int = 0) -> TimelineSchedule {
        let adjustedSunrise = max(60, min(660, sunriseMinutes + sunriseOffsetMinutes))
        let adjustedSunset = max(adjustedSunrise + 240, min(1380, sunsetMinutes + sunsetOffsetMinutes))
        let daylightSpan = max(180, adjustedSunset - adjustedSunrise)

        // 1. 日出破晓: 日出前25分钟（或晨光始）开始
        let sunriseStart = max(0, adjustedSunrise - 25)
        // 2. 清晨朝霞: 日出后约 65 分钟开始
        let morningStart = min(adjustedSunset - 120, adjustedSunrise + 65)
        // 3. 明媚白昼: 日出后约 30% 白昼时长处开始
        let dayStart = max(morningStart + 30, adjustedSunrise + Int(Double(daylightSpan) * 0.28))
        // 4. 日落黄昏: 日落前 45 分钟（黄金时刻）开始
        let sunsetStart = max(dayStart + 45, adjustedSunset - 45)
        // 5. 静谧夜晚: 日落后 35 分钟（昏影终）开始
        let nightStart = min(1425, max(sunsetStart + 30, adjustedSunset + 35))

        return TimelineSchedule(
            sunriseMinutes: sunriseStart,
            morningMinutes: morningStart,
            dayMinutes: dayStart,
            sunsetMinutes: sunsetStart,
            nightMinutes: nightStart
        )
    }
}

/// 基于 NOAA 太阳位置算法计算任意经纬度与日期的日出、正午、日落时间
enum SolarCalculator {
    static func calculate(
        for date: Date = Date(),
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone = .current
    ) -> SolarEvents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let tzOffsetHours = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

        // 分数年份 gamma (弧度)
        let gamma = (2.0 * Double.pi / 365.0) * (dayOfYear - 1.0)

        // 均时差 (分钟)
        let eqTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2.0 * gamma)
            - 0.040849 * sin(2.0 * gamma)
        )

        // 太阳赤纬角 decl (弧度)
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2.0 * gamma)
            + 0.000907 * sin(2.0 * gamma)
            - 0.002697 * cos(3.0 * gamma)
            + 0.00148 * sin(3.0 * gamma)

        let latRad = latitude * Double.pi / 180.0

        func hourAngleDegrees(zenithDegrees: Double) -> Double {
            let zenithRad = zenithDegrees * Double.pi / 180.0
            let cosHA = (cos(zenithRad) / (cos(latRad) * cos(decl))) - tan(latRad) * tan(decl)
            let clamped = max(-1.0, min(1.0, cosHA))
            return acos(clamped) * 180.0 / Double.pi
        }

        // 标准日出日落天顶角 90.833°，民用曙暮光天顶角 96.0°
        let haOfficial = hourAngleDegrees(zenithDegrees: 90.833)
        let haCivil = hourAngleDegrees(zenithDegrees: 96.0)

        let solarNoonUTC = 720.0 - (4.0 * longitude) - eqTime
        let solarNoonLocal = solarNoonUTC + tzOffsetHours * 60.0

        let sunriseLocal = solarNoonLocal - haOfficial * 4.0
        let sunsetLocal = solarNoonLocal + haOfficial * 4.0
        let dawnLocal = solarNoonLocal - haCivil * 4.0
        let duskLocal = solarNoonLocal + haCivil * 4.0

        func clampMinutes(_ value: Double) -> Int {
            let rounded = Int(value.rounded())
            return max(0, min(1439, rounded))
        }

        return SolarEvents(
            date: date,
            latitude: latitude,
            longitude: longitude,
            dawnMinutes: clampMinutes(dawnLocal),
            sunriseMinutes: clampMinutes(sunriseLocal),
            solarNoonMinutes: clampMinutes(solarNoonLocal),
            sunsetMinutes: clampMinutes(sunsetLocal),
            duskMinutes: clampMinutes(duskLocal)
        )
    }
}
