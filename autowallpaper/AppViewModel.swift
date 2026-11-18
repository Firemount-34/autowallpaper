//
//  AppViewModel.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import SwiftUI
import AppKit
import ServiceManagement
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    // MARK: - Published States

    @Published var isAutoSwitchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSwitchEnabled, forKey: "isAutoSwitchEnabled")
            if isAutoSwitchEnabled {
                isPaused = false
                syncWallpaperNow(force: true)
            }
        }
    }

    @Published var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: "isPaused")
            if !isPaused && isAutoSwitchEnabled {
                lockedPeriod = nil
                syncWallpaperNow(force: true)
            }
        }
    }

    @Published var lockedPeriod: DayPeriod? {
        didSet {
            UserDefaults.standard.set(lockedPeriod?.rawValue, forKey: "lockedPeriod")
        }
    }

    @Published var selectedLocationSetID: String {
        didSet {
            UserDefaults.standard.set(selectedLocationSetID, forKey: "selectedLocationSetID")
            AssetDownloadManager.shared.refreshSystemDownloadedAssets()
            if isAutoSwitchEnabled {
                syncWallpaperNow(force: true)
            }
        }
    }

    @Published var customLocationSets: [AerialLocationSet] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customLocationSets) {
                UserDefaults.standard.set(encoded, forKey: "customLocationSets")
            }
        }
    }

    @Published var scheduleMode: ScheduleMode {
        didSet {
            UserDefaults.standard.set(scheduleMode.rawValue, forKey: "scheduleMode")
            refreshSolarAndSchedule()
            if isAutoSwitchEnabled && !isPaused {
                syncWallpaperNow(force: true)
            }
        }
    }

    @Published var locationMode: LocationMode {
        didSet {
            UserDefaults.standard.set(locationMode.rawValue, forKey: "locationMode")
            if locationMode == .autoLocation {
                locationService.requestCurrentLocation()
            }
            refreshSolarAndSchedule()
        }
    }

    @Published var selectedPresetCityName: String {
        didSet {
            UserDefaults.standard.set(selectedPresetCityName, forKey: "selectedPresetCityName")
            if let city = PresetCity.allCities.first(where: { $0.name == selectedPresetCityName }) {
                manualLatitude = city.latitude
                manualLongitude = city.longitude
            }
            refreshSolarAndSchedule()
            if isAutoSwitchEnabled && !isPaused {
                syncWallpaperNow(force: false)
            }
        }
    }

    @Published var manualLatitude: Double {
        didSet {
            UserDefaults.standard.set(manualLatitude, forKey: "manualLatitude")
            refreshSolarAndSchedule()
        }
    }

    @Published var manualLongitude: Double {
        didSet {
            UserDefaults.standard.set(manualLongitude, forKey: "manualLongitude")
            refreshSolarAndSchedule()
        }
    }

    @Published var detectedCityName: String? {
        didSet {
            UserDefaults.standard.set(detectedCityName, forKey: "detectedCityName")
        }
    }

    @Published var sunriseOffsetMinutes: Int {
        didSet {
            UserDefaults.standard.set(sunriseOffsetMinutes, forKey: "sunriseOffsetMinutes")
            refreshSolarAndSchedule()
            if isAutoSwitchEnabled && !isPaused {
                syncWallpaperNow(force: false)
            }
        }
    }

    @Published var sunsetOffsetMinutes: Int {
        didSet {
            UserDefaults.standard.set(sunsetOffsetMinutes, forKey: "sunsetOffsetMinutes")
            refreshSolarAndSchedule()
            if isAutoSwitchEnabled && !isPaused {
                syncWallpaperNow(force: false)
            }
        }
    }

    @Published var customTimeline: TimelineSchedule {
        didSet {
            if let encoded = try? JSONEncoder().encode(customTimeline) {
                UserDefaults.standard.set(encoded, forKey: "customTimeline")
            }
            if scheduleMode == .custom && isAutoSwitchEnabled && !isPaused {
                syncWallpaperNow(force: false)
            }
        }
    }

    @Published var customPeriodAssetMapping: [String: [String: String]] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPeriodAssetMapping) {
                UserDefaults.standard.set(encoded, forKey: "customPeriodAssetMapping")
            }
            if isAutoSwitchEnabled {
                syncWallpaperNow(force: true)
            }
        }
    }

    @Published var syncScreenSaver: Bool {
        didSet {
            UserDefaults.standard.set(syncScreenSaver, forKey: "syncScreenSaver")
        }
    }

    @Published var autoDownloadMissingVideos: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadMissingVideos, forKey: "autoDownloadMissingVideos")
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            applyDockVisibilityAndIcon()
        }
    }

    @Published var launchAtLogin: Bool = false

    @Published var now: Date = Date()
    @Published var todaySolarEvents: SolarEvents
    @Published var lastAppliedAssetID: String?
    @Published var lastAppliedPeriod: DayPeriod?
    @Published var lastSwitchTime: Date?
    @Published var statusBannerMessage: String?
    @Published var isStatusError: Bool = false

    /// 当目标时段视频尚未下载时，记录待下载完成后自动应用的 Asset ID，下载期间不打断当前桌面壁纸
    private var pendingApplyAssetID: String?
    private var pendingApplyPeriod: DayPeriod?

    /// 缓存应用图标与状态栏图标，避免每次 SwiftUI 刷新时重新绘制位图
    private static var cachedBaseAppIcon: NSImage?
    private static var cachedStatusIcons: [String: NSImage] = [:]
    private var lastSolarCalcDayOfYear: Int = -1
    private var lastSolarCalcLat: Double = .nan
    private var lastSolarCalcLon: Double = .nan

    let locationService = LocationService()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    // MARK: - Computed Properties

    var locationSets: [AerialLocationSet] {
        customLocationSets + AerialCatalog.shared.locationSets
    }

    var builtInLocationSets: [AerialLocationSet] {
        AerialCatalog.shared.locationSets
    }

    var selectedLocationSet: AerialLocationSet? {
        locationSets.first(where: { $0.id == selectedLocationSetID }) ?? locationSets.first
    }

    var activeCoordinates: (latitude: Double, longitude: Double, label: String) {
        switch locationMode {
        case .presetCity:
            if let city = PresetCity.allCities.first(where: { $0.name == selectedPresetCityName }) {
                return (city.latitude, city.longitude, city.name)
            }
            return (39.9042, 116.4074, "北京")
        case .autoLocation:
            if let coord = locationService.detectedCoordinate {
                let name = locationService.detectedPlaceName ?? detectedCityName ?? "当前定位"
                return (coord.latitude, coord.longitude, name)
            }
            return (manualLatitude, manualLongitude, detectedCityName ?? "定位缓存")
        case .manualCoordinates:
            let latStr = String(format: "%.2f°", manualLatitude)
            let lonStr = String(format: "%.2f°", manualLongitude)
            return (manualLatitude, manualLongitude, "\(latStr), \(lonStr)")
        }
    }

    var effectiveSchedule: TimelineSchedule {
        switch scheduleMode {
        case .solar:
            return todaySolarEvents.toTimelineSchedule(
                sunriseOffsetMinutes: sunriseOffsetMinutes,
                sunsetOffsetMinutes: sunsetOffsetMinutes
            )
        case .custom:
            return customTimeline
        }
    }

    var currentPeriod: DayPeriod {
        if isPaused, let locked = lockedPeriod {
            return locked
        }
        return effectiveSchedule.currentPeriod(at: now)
    }

    var nextTransitionInfo: (period: DayPeriod, date: Date, timeString: String) {
        effectiveSchedule.nextTransition(after: now)
    }

    var currentTargetAsset: AerialAsset? {
        guard let loc = selectedLocationSet,
              let aid = loc.assetID(for: currentPeriod, customMapping: customPeriodAssetMapping) else {
            return nil
        }
        return AerialCatalog.shared.assetsByID[aid]
    }

    var menuBarSymbolName: String {
        if !isAutoSwitchEnabled {
            return "photo.on.rectangle.angled"
        }
        if isPaused {
            return "pause.circle.fill"
        }
        return currentPeriod.symbolName
    }

    /// 根据当前应用图标动态生成并缓存 macOS 顶部状态栏（菜单栏）图标 (18x18 pt)
    var menuBarAppIconImage: NSImage {
        let stateKey = "\(isAutoSwitchEnabled)-\(isPaused)"
        if let cached = Self.cachedStatusIcons[stateKey] {
            return cached
        }

        let baseIcon = Self.loadOrRenderAppIcon()
        let targetSize = NSSize(width: 18, height: 18)
        let statusBarImage = NSImage(size: targetSize)

        statusBarImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let alpha: CGFloat = isAutoSwitchEnabled ? 1.0 : 0.55
        baseIcon.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: baseIcon.size),
            operation: .sourceOver,
            fraction: alpha
        )

        if isAutoSwitchEnabled && isPaused, let ctx = NSGraphicsContext.current?.cgContext {
            let badgeRect = CGRect(x: 12.0, y: 1.0, width: 5.0, height: 5.0)
            ctx.setFillColor(NSColor.systemOrange.cgColor)
            ctx.fillEllipse(in: badgeRect)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(0.8)
            ctx.strokeEllipse(in: badgeRect)
        }

        statusBarImage.unlockFocus()
        statusBarImage.isTemplate = false
        Self.cachedStatusIcons[stateKey] = statusBarImage
        return statusBarImage
    }

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        let savedAutoSwitch = defaults.object(forKey: "isAutoSwitchEnabled") as? Bool ?? false
        let savedPaused = defaults.bool(forKey: "isPaused")
        let savedLockedRaw = defaults.string(forKey: "lockedPeriod")
        let savedLocSetID = defaults.string(forKey: "selectedLocationSetID") ?? "sonoma"
        let savedScheduleMode = ScheduleMode(rawValue: defaults.string(forKey: "scheduleMode") ?? "") ?? .solar
        let savedLocationMode = LocationMode(rawValue: defaults.string(forKey: "locationMode") ?? "") ?? .presetCity
        let savedCityName = defaults.string(forKey: "selectedPresetCityName") ?? "北京"
        let savedLat = defaults.object(forKey: "manualLatitude") as? Double ?? 39.9042
        let savedLon = defaults.object(forKey: "manualLongitude") as? Double ?? 116.4074
        let savedDetectedCity = defaults.string(forKey: "detectedCityName")
        let savedSunriseOffset = defaults.integer(forKey: "sunriseOffsetMinutes")
        let savedSunsetOffset = defaults.integer(forKey: "sunsetOffsetMinutes")
        let savedSyncSaver = defaults.object(forKey: "syncScreenSaver") as? Bool ?? true
        let savedAutoDownload = defaults.object(forKey: "autoDownloadMissingVideos") as? Bool ?? true
        let savedShowDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true

        let decodedTimeline: TimelineSchedule
        if let data = defaults.data(forKey: "customTimeline"),
           let t = try? JSONDecoder().decode(TimelineSchedule.self, from: data) {
            decodedTimeline = t
        } else {
            decodedTimeline = .default
        }

        let decodedMapping: [String: [String: String]]
        if let data = defaults.data(forKey: "customPeriodAssetMapping"),
           let m = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            decodedMapping = m
        } else {
            decodedMapping = [:]
        }

        let decodedCustomGroups: [AerialLocationSet]
        if let data = defaults.data(forKey: "customLocationSets"),
           let groups = try? JSONDecoder().decode([AerialLocationSet].self, from: data) {
            decodedCustomGroups = groups
        } else {
            decodedCustomGroups = []
        }

        self.isAutoSwitchEnabled = savedAutoSwitch
        self.isPaused = savedPaused
        self.lockedPeriod = savedLockedRaw.flatMap { DayPeriod(rawValue: $0) }
        self.selectedLocationSetID = savedLocSetID
        self.customLocationSets = decodedCustomGroups
        self.scheduleMode = savedScheduleMode
        self.locationMode = savedLocationMode
        self.selectedPresetCityName = savedCityName
        self.manualLatitude = savedLat
        self.manualLongitude = savedLon
        self.detectedCityName = savedDetectedCity
        self.sunriseOffsetMinutes = savedSunriseOffset
        self.sunsetOffsetMinutes = savedSunsetOffset
        self.customTimeline = decodedTimeline
        self.customPeriodAssetMapping = decodedMapping
        self.syncScreenSaver = savedSyncSaver
        self.autoDownloadMissingVideos = savedAutoDownload
        self.showDockIcon = savedShowDockIcon

        self.todaySolarEvents = SolarCalculator.calculate(
            for: Date(),
            latitude: savedLat,
            longitude: savedLon
        )

        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        self.lastAppliedAssetID = WallpaperSwitcherService.shared.readCurrentSystemAssetID()

        setupCallbacksAndTimers()
        refreshSolarAndSchedule()

        if isAutoSwitchEnabled {
            syncWallpaperNow(force: false)
        }
    }

    private func setupCallbacksAndTimers() {
        AssetDownloadManager.shared.onAssetDownloaded = { [weak self] downloadedAssetID in
            guard let self = self else { return }
            // 如果刚下载完的视频正是用户等待切换的目标壁纸（或当前启用自动切换所处时段的壁纸），现在安全切换
            if downloadedAssetID == self.pendingApplyAssetID {
                let targetPeriod = self.pendingApplyPeriod ?? self.currentPeriod
                self.pendingApplyAssetID = nil
                self.pendingApplyPeriod = nil
                self.performImmediateWallpaperSwitch(assetID: downloadedAssetID, period: targetPeriod)
            } else if self.isAutoSwitchEnabled,
                      let currentTargetID = self.currentTargetAsset?.id,
                      currentTargetID == downloadedAssetID {
                self.performImmediateWallpaperSwitch(assetID: downloadedAssetID, period: self.currentPeriod)
            }
        }

        locationService.onLocationUpdated = { [weak self] lat, lon, city in
            guard let self = self else { return }
            self.manualLatitude = lat
            self.manualLongitude = lon
            if let city = city {
                self.detectedCityName = city
            }
            self.refreshSolarAndSchedule()
            if self.isAutoSwitchEnabled && !self.isPaused {
                self.syncWallpaperNow(force: false)
            }
        }

        if locationMode == .autoLocation {
            locationService.requestCurrentLocation()
        }

        // 每 60 秒低功耗检查一次时间与时段切换（设置 10 秒 tolerance 支持 macOS 定时器合并省电）
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handlePeriodicTick()
            }
        }
        t.tolerance = 10.0
        timer = t

        // 监听系统睡眠唤醒与会话激活，确保唤醒后立即校准航拍壁纸
        let wsCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSolarAndSchedule()
                if self?.isAutoSwitchEnabled == true && self?.isPaused == false {
                    self?.syncWallpaperNow(force: true)
                }
            }
        }

        let activeObserver = wsCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSolarAndSchedule()
                if self?.isAutoSwitchEnabled == true && self?.isPaused == false {
                    self?.syncWallpaperNow(force: false)
                }
            }
        }

        workspaceObservers = [wakeObserver, activeObserver]
    }

    func refreshSolarAndSchedule() {
        let current = Date()
        now = current
        let coords = activeCoordinates
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: current) ?? 1

        // 仅当跨天或经纬度变化时才重新运行天文三角函数计算
        if dayOfYear != lastSolarCalcDayOfYear
            || abs(coords.latitude - lastSolarCalcLat) > 0.0001
            || abs(coords.longitude - lastSolarCalcLon) > 0.0001 {
            lastSolarCalcDayOfYear = dayOfYear
            lastSolarCalcLat = coords.latitude
            lastSolarCalcLon = coords.longitude
            todaySolarEvents = SolarCalculator.calculate(
                for: current,
                latitude: coords.latitude,
                longitude: coords.longitude
            )
        }
    }

    private func handlePeriodicTick() {
        refreshSolarAndSchedule()
        guard isAutoSwitchEnabled && !isPaused else { return }
        guard AssetDownloadManager.shared.activeDownloads.isEmpty else { return }
        syncWallpaperNow(force: false)
    }

    // MARK: - Actions

    /// 当用户直接在时间轴上拖动刻度滑块时，若当前是“跟随日出日落”模式，自动切换为“自定义24h时间轴”模式并更新
    func updateTimelineFromDirectDrag(_ updatedSchedule: TimelineSchedule) {
        customTimeline = updatedSchedule
        if scheduleMode != .custom {
            scheduleMode = .custom
        }
    }

    /// 检查并应用当前时段对应的航拍壁纸（若目标视频尚未下载，则先后台下载，期间保持当前桌面壁纸不退出）
    func syncWallpaperNow(force: Bool = true) {
        refreshSolarAndSchedule()
        guard let loc = selectedLocationSet else { return }
        let targetPeriod = currentPeriod
        guard let targetAssetID = loc.assetID(for: targetPeriod, customMapping: customPeriodAssetMapping) else {
            return
        }

        if !force,
           lastAppliedAssetID == targetAssetID,
           lastAppliedPeriod == targetPeriod {
            return
        }

        let assetName = AerialCatalog.shared.assetsByID[targetAssetID]?.displayName ?? targetAssetID
        let isReady = AssetDownloadManager.shared.isDownloaded(targetAssetID)

        guard isReady else {
            // 关键保护：目标视频未下载完成前绝不写入 Index.plist 或重启 WallpaperAgent，防止系统因找不到视频而退回默认原壁纸
            pendingApplyAssetID = targetAssetID
            pendingApplyPeriod = targetPeriod
            AssetDownloadManager.shared.downloadAsset(targetAssetID, prioritize: true)
            statusBannerMessage = "正在后台下载「\(targetPeriod.shortTitle)」视频：\(assetName)，下载期间保持当前壁纸不变，完成后自动切换..."
            isStatusError = false
            return
        }

        pendingApplyAssetID = nil
        pendingApplyPeriod = nil
        performImmediateWallpaperSwitch(assetID: targetAssetID, period: targetPeriod)
    }

    /// 手动预览或锁定某个特定时段的壁纸
    func applySpecificPeriod(_ period: DayPeriod, lockPeriod: Bool) {
        if lockPeriod {
            lockedPeriod = period
            isPaused = true
        }
        guard let loc = selectedLocationSet,
              let targetAssetID = loc.assetID(for: period, customMapping: customPeriodAssetMapping) else {
            return
        }

        let assetName = AerialCatalog.shared.assetsByID[targetAssetID]?.displayName ?? targetAssetID
        let isReady = AssetDownloadManager.shared.isDownloaded(targetAssetID)

        guard isReady else {
            // 目标视频未就绪时仅启动后台 HTTP 下载，保持当前桌面壁纸不退出，下载完后自动应用
            pendingApplyAssetID = targetAssetID
            pendingApplyPeriod = period
            AssetDownloadManager.shared.downloadAsset(targetAssetID, prioritize: true)
            statusBannerMessage = "正在后台下载「\(period.shortTitle)」：\(assetName)，当前壁纸保持不变，下载完成后将自动切换"
            isStatusError = false
            return
        }

        pendingApplyAssetID = nil
        pendingApplyPeriod = nil
        performImmediateWallpaperSwitch(assetID: targetAssetID, period: period, isLocked: lockPeriod)
    }

    /// 仅当目标视频已确认在系统 `4KSDR240FPS` 目录就绪时，才真正修改 `Index.plist` 并重启 `WallpaperAgent`
    private func performImmediateWallpaperSwitch(assetID: String, period: DayPeriod, isLocked: Bool = false) {
        do {
            try WallpaperSwitcherService.shared.applyAerialWallpaper(
                assetID: assetID,
                syncScreenSaver: syncScreenSaver
            )
            lastAppliedAssetID = assetID
            lastAppliedPeriod = period
            lastSwitchTime = Date()
            let assetName = AerialCatalog.shared.assetsByID[assetID]?.displayName ?? assetID
            statusBannerMessage = isLocked
                ? "已锁定为「\(period.shortTitle)」时段：\(assetName)"
                : "已切换至「\(period.shortTitle)」壁纸：\(assetName)"
            isStatusError = false
        } catch {
            statusBannerMessage = error.localizedDescription
            isStatusError = true
        }
    }

    /// 为当前地点的特定时段更换航拍视频镜头
    func setCustomAsset(_ assetID: String, for period: DayPeriod, in locationSetID: String) {
        if let idx = customLocationSets.firstIndex(where: { $0.id == locationSetID }) {
            var group = customLocationSets[idx]
            group.defaultPeriodAssets[period] = assetID
            if !group.availableAssetIDs.contains(assetID) {
                group.availableAssetIDs.append(assetID)
            }
            customLocationSets[idx] = group
        }
        var locMap = customPeriodAssetMapping[locationSetID] ?? [:]
        locMap[period.rawValue] = assetID
        customPeriodAssetMapping[locationSetID] = locMap
    }

    /// 重置当前地点的时段镜头分配为默认值
    func resetCustomAssets(for locationSetID: String) {
        customPeriodAssetMapping.removeValue(forKey: locationSetID)
    }

    // MARK: - 自定义分组管理 (新建 / 编辑 / 删除)

    func createCustomGroup(name: String, summary: String, periodAssets: [DayPeriod: String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "自定义分组 \(customLocationSets.count + 1)" : trimmedName
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = trimmedSummary.isEmpty ? "用户自定义跨地点混搭航拍分组" : trimmedSummary

        let uniqueIDs = Array(Set(periodAssets.values))
        let newGroup = AerialLocationSet(
            id: "custom-\(UUID().uuidString)",
            subcategoryID: nil,
            name: finalName,
            englishName: finalName,
            categoryName: "自定义分组",
            summary: finalSummary,
            defaultPeriodAssets: periodAssets,
            availableAssetIDs: uniqueIDs,
            isCustomGroup: true
        )

        customLocationSets.insert(newGroup, at: 0)
        selectedLocationSetID = newGroup.id
        statusBannerMessage = "已新建并启用自定义分组「\(finalName)」"
        isStatusError = false
    }

    func updateCustomGroup(id: String, name: String, summary: String, periodAssets: [DayPeriod: String]) {
        guard let idx = customLocationSets.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? customLocationSets[idx].name : trimmedName
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSummary = trimmedSummary.isEmpty ? "用户自定义跨地点混搭航拍分组" : trimmedSummary

        var group = customLocationSets[idx]
        group.name = finalName
        group.englishName = finalName
        group.summary = finalSummary
        group.defaultPeriodAssets = periodAssets
        group.availableAssetIDs = Array(Set(periodAssets.values))

        customLocationSets[idx] = group
        customPeriodAssetMapping.removeValue(forKey: id)
        statusBannerMessage = "已更新自定义分组「\(finalName)」"
        isStatusError = false

        if selectedLocationSetID == id && isAutoSwitchEnabled {
            syncWallpaperNow(force: true)
        }
    }

    func deleteCustomGroup(id: String) {
        guard let idx = customLocationSets.firstIndex(where: { $0.id == id }) else { return }
        let deletedName = customLocationSets[idx].name
        customLocationSets.remove(at: idx)
        customPeriodAssetMapping.removeValue(forKey: id)

        if selectedLocationSetID == id {
            selectedLocationSetID = locationSets.first?.id ?? "sonoma"
        }
        statusBannerMessage = "已删除自定义分组「\(deletedName)」"
        isStatusError = false
    }

    // MARK: - 删除已下载壁纸视频文件

    func deleteDownloadedVideo(assetID: String) {
        let assetName = AerialCatalog.shared.assetsByID[assetID]?.displayName ?? assetID
        let result = AssetDownloadManager.shared.deleteDownloadedAssets([assetID])
        switch result {
        case .success(let detail):
            statusBannerMessage = "「\(assetName)」：\(detail)"
            isStatusError = false
        case .failure(let error):
            statusBannerMessage = "删除「\(assetName)」失败：\(error.localizedDescription)"
            isStatusError = true
        }
    }

    func deleteAllDownloadedVideos(in locationSet: AerialLocationSet) {
        var idsToDelete: [String] = []
        for period in DayPeriod.allCases {
            if let aid = locationSet.assetID(for: period, customMapping: customPeriodAssetMapping),
               AssetDownloadManager.shared.isDownloaded(aid),
               !idsToDelete.contains(aid) {
                idsToDelete.append(aid)
            }
        }
        guard !idsToDelete.isEmpty else {
            statusBannerMessage = "「\(locationSet.name)」当前没有已下载的视频文件。"
            isStatusError = false
            return
        }

        let result = AssetDownloadManager.shared.deleteDownloadedAssets(idsToDelete)
        switch result {
        case .success(let detail):
            statusBannerMessage = "「\(locationSet.name)」：\(detail)"
            isStatusError = false
        case .failure(let error):
            statusBannerMessage = "删除失败：\(error.localizedDescription)"
            isStatusError = true
        }
    }

    /// 将自定义 24 小时时间轴一键对齐到今日日出日落时间
    func alignCustomTimelineWithTodaySolar() {
        customTimeline = todaySolarEvents.toTimelineSchedule(
            sunriseOffsetMinutes: sunriseOffsetMinutes,
            sunsetOffsetMinutes: sunsetOffsetMinutes
        )
        statusBannerMessage = "已将 24 小时时间轴对齐至今日 \(activeCoordinates.label) 日出日落时间"
        isStatusError = false
    }

    /// 关闭自动切换并恢复接管前的系统原始壁纸
    func disableAndRestoreOriginalWallpaper() {
        isAutoSwitchEnabled = false
        isPaused = false
        lockedPeriod = nil
        AssetDownloadManager.shared.cancelAllDownloads()
        do {
            let restored = try WallpaperSwitcherService.shared.restoreBackup()
            if restored {
                statusBannerMessage = "已关闭自动切换，并成功恢复您原有的系统壁纸配置。"
            } else {
                statusBannerMessage = "已关闭自动切换（未检测到历史备份文件）。"
            }
            isStatusError = false
        } catch {
            statusBannerMessage = "恢复原始壁纸失败：\(error.localizedDescription)"
            isStatusError = true
        }
    }

    /// 强制刷新程序坞 (Dock) 图标显示状态与自定义图像（绕过 macOS LaunchServices 图标缓存）
    func applyDockVisibilityAndIcon() {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)

        if showDockIcon {
            let iconImage = Self.loadOrRenderAppIcon()
            NSApplication.shared.applicationIconImage = iconImage
            NSApplication.shared.dockTile.display()
        }
    }

    static func loadOrRenderAppIcon() -> NSImage {
        if let cached = cachedBaseAppIcon {
            return cached
        }
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: icnsURL) {
            cachedBaseAppIcon = img
            return img
        }
        if let namedImg = NSImage(named: "AppIcon") {
            cachedBaseAppIcon = namedImg
            return namedImg
        }
        let fallback = renderVectorAppIcon(pixelSize: 512)
        cachedBaseAppIcon = fallback
        return fallback
    }

    /// 内置 CoreGraphics 矢量图标渲染兜底，确保任何编译缓存状态下 Dock 均能立即显示图标
    static func renderVectorAppIcon(pixelSize: Int) -> NSImage {
        let s = CGFloat(pixelSize)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let margin = s * 0.09
            let iconRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
            let cornerRadius = iconRect.width * 0.225
            let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            ctx.saveGState()
            ctx.addPath(squirclePath)
            ctx.clip()

            let skyColors: [CGFloat] = [
                0.06, 0.08, 0.24, 1.0,
                0.24, 0.18, 0.48, 1.0,
                0.88, 0.32, 0.38, 1.0,
                0.99, 0.65, 0.24, 1.0
            ]
            if let skyGrad = CGGradient(colorSpace: colorSpace, colorComponents: skyColors, locations: [0.0, 0.35, 0.68, 1.0], count: 4) {
                ctx.drawLinearGradient(
                    skyGrad,
                    start: CGPoint(x: iconRect.maxX, y: iconRect.maxY),
                    end: CGPoint(x: iconRect.minX, y: iconRect.minY + iconRect.height * 0.22),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            let sunCenter = CGPoint(x: s * 0.44, y: s * 0.50)
            let sunRadius = s * 0.135
            ctx.setFillColor(CGColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))

            let frontMtn = CGMutablePath()
            frontMtn.move(to: CGPoint(x: iconRect.minX, y: iconRect.minY))
            frontMtn.addLine(to: CGPoint(x: iconRect.minX, y: s * 0.34))
            frontMtn.addLine(to: CGPoint(x: s * 0.23, y: s * 0.45))
            frontMtn.addLine(to: CGPoint(x: s * 0.43, y: s * 0.31))
            frontMtn.addLine(to: CGPoint(x: s * 0.62, y: s * 0.44))
            frontMtn.addLine(to: CGPoint(x: s * 0.80, y: s * 0.35))
            frontMtn.addLine(to: CGPoint(x: iconRect.maxX, y: s * 0.40))
            frontMtn.addLine(to: CGPoint(x: iconRect.maxX, y: iconRect.minY))
            frontMtn.closeSubpath()

            ctx.addPath(frontMtn)
            ctx.setFillColor(CGColor(red: 0.08, green: 0.07, blue: 0.20, alpha: 1.0))
            ctx.fillPath()
            ctx.restoreGState()
        }
        image.unlockFocus()
        return image
    }

    /// 切换开机自启状态
    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            statusBannerMessage = "设置开机自启失败：\(error.localizedDescription)"
            isStatusError = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
