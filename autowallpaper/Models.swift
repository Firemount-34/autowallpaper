//
//  Models.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import SwiftUI

/// 一天中的五个航拍壁纸切换时段
enum DayPeriod: String, CaseIterable, Codable, Identifiable {
    case sunrise = "sunrise"
    case morning = "morning"
    case day = "day"
    case sunset = "sunset"
    case night = "night"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunrise: return "日出破晓"
        case .morning: return "清晨朝霞"
        case .day: return "明媚白昼"
        case .sunset: return "日落黄昏"
        case .night: return "静谧夜晚"
        }
    }

    var shortTitle: String {
        switch self {
        case .sunrise: return "日出"
        case .morning: return "清晨"
        case .day: return "白天"
        case .sunset: return "日落"
        case .night: return "夜晚"
        }
    }

    var symbolName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .morning: return "sun.min.fill"
        case .day: return "sun.max.fill"
        case .sunset: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .sunrise: return Color(red: 0.98, green: 0.56, blue: 0.28)
        case .morning: return Color(red: 0.96, green: 0.76, blue: 0.25)
        case .day: return Color(red: 0.24, green: 0.68, blue: 0.96)
        case .sunset: return Color(red: 0.92, green: 0.36, blue: 0.44)
        case .night: return Color(red: 0.42, green: 0.40, blue: 0.88)
        }
    }
}

/// 切换时间表模式
enum ScheduleMode: String, CaseIterable, Codable, Identifiable {
    case solar = "solar"       // 根据所在地日出日落时间自动计算
    case custom = "custom"     // 24小时自定义时间轴（类似 aerial-switcher）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solar: return "跟随日出日落"
        case .custom: return "自定义24h时间轴"
        }
    }

    var subtitle: String {
        switch self {
        case .solar: return "根据当前地理位置的真实天文日出、正午、日落时间动态划分时段"
        case .custom: return "自由拖拽调整各时段起始时间（以15分钟为刻度）"
        }
    }
}

/// 地理位置获取方式
enum LocationMode: String, CaseIterable, Codable, Identifiable {
    case presetCity = "presetCity"
    case autoLocation = "autoLocation"
    case manualCoordinates = "manualCoordinates"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presetCity: return "选择城市"
        case .autoLocation: return "系统定位"
        case .manualCoordinates: return "手动经纬度"
        }
    }
}

/// 预设城市信息
struct PresetCity: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double

    var displayName: String {
        "\(name) (\(region))"
    }

    static let allCities: [PresetCity] = [
        PresetCity(name: "北京", region: "华北", latitude: 39.9042, longitude: 116.4074),
        PresetCity(name: "上海", region: "华东", latitude: 31.2304, longitude: 121.4737),
        PresetCity(name: "广州", region: "华南", latitude: 23.1291, longitude: 113.2644),
        PresetCity(name: "深圳", region: "华南", latitude: 22.5431, longitude: 114.0579),
        PresetCity(name: "杭州", region: "华东", latitude: 30.2741, longitude: 120.1551),
        PresetCity(name: "南京", region: "华东", latitude: 32.0603, longitude: 118.7969),
        PresetCity(name: "苏州", region: "华东", latitude: 31.2989, longitude: 120.5853),
        PresetCity(name: "成都", region: "西南", latitude: 30.5728, longitude: 104.0668),
        PresetCity(name: "重庆", region: "西南", latitude: 29.5630, longitude: 106.5516),
        PresetCity(name: "武汉", region: "华中", latitude: 30.5928, longitude: 114.3055),
        PresetCity(name: "西安", region: "西北", latitude: 34.3416, longitude: 108.9398),
        PresetCity(name: "长沙", region: "华中", latitude: 28.2282, longitude: 112.9388),
        PresetCity(name: "天津", region: "华北", latitude: 39.3434, longitude: 117.3616),
        PresetCity(name: "青岛", region: "华东", latitude: 36.0671, longitude: 120.3826),
        PresetCity(name: "厦门", region: "华东", latitude: 24.4798, longitude: 118.0894),
        PresetCity(name: "昆明", region: "西南", latitude: 25.0389, longitude: 102.7183),
        PresetCity(name: "大连", region: "东北", latitude: 38.9140, longitude: 121.6147),
        PresetCity(name: "沈阳", region: "东北", latitude: 41.8057, longitude: 123.4315),
        PresetCity(name: "哈尔滨", region: "东北", latitude: 45.8038, longitude: 126.5349),
        PresetCity(name: "乌鲁木齐", region: "西北", latitude: 43.8256, longitude: 87.6168),
        PresetCity(name: "拉萨", region: "西南", latitude: 29.6525, longitude: 91.1721),
        PresetCity(name: "三亚", region: "华南", latitude: 18.2528, longitude: 109.5119),
        PresetCity(name: "香港", region: "港澳台", latitude: 22.3193, longitude: 114.1694),
        PresetCity(name: "台北", region: "港澳台", latitude: 25.0330, longitude: 121.5654),
        PresetCity(name: "东京", region: "日本", latitude: 35.6762, longitude: 139.6503),
        PresetCity(name: "新加坡", region: "东南亚", latitude: 1.3521, longitude: 103.8198),
        PresetCity(name: "悉尼", region: "大洋洲", latitude: -33.8688, longitude: 151.2093),
        PresetCity(name: "伦敦", region: "欧洲", latitude: 51.5074, longitude: -0.1278),
        PresetCity(name: "旧金山", region: "北美", latitude: 37.7749, longitude: -122.4194),
        PresetCity(name: "纽约", region: "北美", latitude: 40.7128, longitude: -74.0060)
    ]
}

/// 单个 macOS 原生航拍视频资源
struct AerialAsset: Identifiable, Hashable, Codable {
    let id: String
    let shotID: String
    let localizedNameKey: String
    let zhName: String
    let enName: String
    let subcategories: [String]
    let categories: [String]
    let videoURL: String?
    let previewImageURL: String?

    var displayName: String {
        if !zhName.isEmpty && zhName != localizedNameKey {
            return zhName
        }
        if !enName.isEmpty && enName != localizedNameKey {
            return enName
        }
        return shotID
    }

    var localPreviewPath: String {
        "/Library/Application Support/com.apple.idleassetsd/snapshots/asset-preview-\(id).jpg"
    }
}

/// 航拍壁纸地点组/自定义分组（包含不同时段的多个视频资源）
struct AerialLocationSet: Identifiable, Hashable, Codable {
    let id: String
    let subcategoryID: String?
    var name: String
    var englishName: String
    var categoryName: String
    var summary: String
    /// 默认各时段对应的 Asset ID
    var defaultPeriodAssets: [DayPeriod: String]
    /// 该地点下所有可选的航拍视频 Asset ID 列表
    var availableAssetIDs: [String]
    /// 是否为用户新建的自定义分组
    var isCustomGroup: Bool = false

    func assetID(for period: DayPeriod, customMapping: [String: [String: String]]) -> String? {
        if let customForLocation = customMapping[id],
           let customID = customForLocation[period.rawValue],
           !customID.isEmpty {
            return customID
        }
        return defaultPeriodAssets[period]
    }
}

/// 24小时时间轴配置（每个时段的开始分钟数 0...1439）
struct TimelineSchedule: Codable, Equatable {
    var sunriseMinutes: Int  // 默认例如 06:00 (360)
    var morningMinutes: Int  // 默认例如 07:30 (450)
    var dayMinutes: Int      // 默认例如 10:30 (630)
    var sunsetMinutes: Int   // 默认例如 17:00 (1020)
    var nightMinutes: Int    // 默认例如 18:30 (1110)

    static let `default` = TimelineSchedule(
        sunriseMinutes: 6 * 60,
        morningMinutes: 7 * 60 + 30,
        dayMinutes: 10 * 60 + 30,
        sunsetMinutes: 17 * 60,
        nightMinutes: 18 * 60 + 30
    )

    func startMinutes(for period: DayPeriod) -> Int {
        switch period {
        case .sunrise: return sunriseMinutes
        case .morning: return morningMinutes
        case .day: return dayMinutes
        case .sunset: return sunsetMinutes
        case .night: return nightMinutes
        }
    }

    mutating func setStartMinutes(_ minutes: Int, for period: DayPeriod) {
        let clamped = max(0, min(1425, (minutes / 15) * 15))
        switch period {
        case .sunrise:
            sunriseMinutes = max(0, min(clamped, morningMinutes - 15))
        case .morning:
            morningMinutes = max(sunriseMinutes + 15, min(clamped, dayMinutes - 15))
        case .day:
            dayMinutes = max(morningMinutes + 15, min(clamped, sunsetMinutes - 15))
        case .sunset:
            sunsetMinutes = max(dayMinutes + 15, min(clamped, nightMinutes - 15))
        case .night:
            nightMinutes = max(sunsetMinutes + 15, min(clamped, 1425))
        }
    }

    /// 根据当前日期判断所处时段
    func currentPeriod(at date: Date = Date(), calendar: Calendar = .current) -> DayPeriod {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let currentMins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        if currentMins < sunriseMinutes {
            return .night
        } else if currentMins < morningMinutes {
            return .sunrise
        } else if currentMins < dayMinutes {
            return .morning
        } else if currentMins < sunsetMinutes {
            return .day
        } else if currentMins < nightMinutes {
            return .sunset
        } else {
            return .night
        }
    }

    /// 计算下一次切换的时段与具体时间
    func nextTransition(after date: Date = Date(), calendar: Calendar = .current) -> (period: DayPeriod, date: Date, timeString: String) {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let currentMins = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let checkpoints: [(DayPeriod, Int)] = [
            (.sunrise, sunriseMinutes),
            (.morning, morningMinutes),
            (.day, dayMinutes),
            (.sunset, sunsetMinutes),
            (.night, nightMinutes)
        ]

        let startOfToday = calendar.startOfDay(for: date)

        for (period, mins) in checkpoints {
            if mins > currentMins {
                let targetDate = calendar.date(byAdding: .minute, value: mins, to: startOfToday) ?? date
                return (period, targetDate, Self.formatMinutes(mins))
            }
        }

        // 已过今日最后一个节点，下一次为明日日出
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let targetDate = calendar.date(byAdding: .minute, value: sunriseMinutes, to: tomorrow) ?? date
        return (.sunrise, targetDate, "明日 \(Self.formatMinutes(sunriseMinutes))")
    }

    /// 获取某个时段的起止时间描述文字列
    func timeRangeText(for period: DayPeriod) -> String {
        let start = startMinutes(for: period)
        let end: Int
        switch period {
        case .sunrise: end = morningMinutes
        case .morning: end = dayMinutes
        case .day: end = sunsetMinutes
        case .sunset: end = nightMinutes
        case .night: end = sunriseMinutes
        }
        return "\(Self.formatMinutes(start)) - \(Self.formatMinutes(end))"
    }

    static func formatMinutes(_ totalMinutes: Int) -> String {
        let normalized = ((totalMinutes % 1440) + 1440) % 1440
        let h = normalized / 60
        let m = normalized % 60
        return String(format: "%02d:%02d", h, m)
    }
}
