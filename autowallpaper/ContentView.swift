//
//  ContentView.swift
//  autowallpaper
//
//  Created by wangcan on 2026/11/18.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel = AppViewModel.shared
    @ObservedObject var downloadManager = AssetDownloadManager.shared
    @Environment(\.openWindow) private var openWindow

    @State private var isShowingNewGroupSheet = false
    @State private var editingCustomGroup: AerialLocationSet?

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 235, ideal: 260, max: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusBannerSection
                    heroLocationHeader
                    solarAndTimelineSection
                    periodCardsSection
                }
                .padding(20)
            }
            .frame(minWidth: 540)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("应用设置", systemImage: "gearshape")
                }
                .help("打开应用设置（Dock 栏显示、开机自启、资源占用等）")
            }
        }
        .sheet(isPresented: $isShowingNewGroupSheet) {
            CustomGroupSheetView(viewModel: viewModel, editingGroup: nil)
        }
        .sheet(item: $editingCustomGroup) { groupToEdit in
            CustomGroupSheetView(viewModel: viewModel, editingGroup: groupToEdit)
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // 顶部总控卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.currentPeriod.symbolName)
                        .font(.title2)
                        .foregroundStyle(viewModel.currentPeriod.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动日出日落切换")
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.isAutoSwitchEnabled ? (viewModel.isPaused ? "已锁定当前时段" : "正在按时间自动轮换") : "未启用接管")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Toggle("", isOn: $viewModel.isAutoSwitchEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日日出")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(viewModel.todaySolarEvents.sunriseTimeString, systemImage: "sunrise.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日日落")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(viewModel.todaySolarEvents.sunsetTimeString, systemImage: "sunset.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.pink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("下次切换")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        let next = viewModel.nextTransitionInfo
                        Text("\(next.period.shortTitle) \(next.timeString)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                // 新建自定义分组与打开设置按钮行
                HStack(spacing: 8) {
                    Button {
                        isShowingNewGroupSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("新建分组")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        openWindow(id: "settings")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                            Text("设置")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            // 航拍地点列表（包含用户自定义分组 + 系统精选地点）
            List(selection: $viewModel.selectedLocationSetID) {
                if !viewModel.customLocationSets.isEmpty {
                    Section("我的自定义分组") {
                        ForEach(viewModel.customLocationSets) { customLoc in
                            locationRow(customLoc)
                                .tag(customLoc.id)
                                .contextMenu {
                                    Button {
                                        editingCustomGroup = customLoc
                                    } label: {
                                        Label("编辑该自定义分组", systemImage: "pencil")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        viewModel.deleteCustomGroup(id: customLoc.id)
                                    } label: {
                                        Label("删除该自定义分组", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section("精选自然景观") {
                    ForEach(viewModel.builtInLocationSets.filter { $0.categoryName.contains("自然") }) { loc in
                        locationRow(loc)
                            .tag(loc.id)
                    }
                }
                Section("精选城市景观") {
                    ForEach(viewModel.builtInLocationSets.filter { !$0.categoryName.contains("自然") }) { loc in
                        locationRow(loc)
                            .tag(loc.id)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func locationRow(_ loc: AerialLocationSet) -> some View {
        let repAssetID = loc.assetID(for: viewModel.currentPeriod, customMapping: viewModel.customPeriodAssetMapping)
            ?? loc.defaultPeriodAssets[.day] ?? ""

        let readyCount = DayPeriod.allCases.filter { period in
            if let aid = loc.assetID(for: period, customMapping: viewModel.customPeriodAssetMapping) {
                return downloadManager.isDownloaded(aid)
            }
            return false
        }.count

        HStack(spacing: 10) {
            Color.clear
                .frame(width: 48, height: 30)
                .overlay {
                    if let nsImg = AerialCatalog.shared.previewImage(for: repAssetID, maxPixelSize: 120) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.25))
                            .overlay(Image(systemName: "photo").font(.caption))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(loc.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if loc.isCustomGroup {
                        Text("自定义")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text("已就绪 \(readyCount)/\(DayPeriod.allCases.count) 个时段")
                    .font(.caption2)
                    .foregroundStyle(readyCount == DayPeriod.allCases.count ? .green : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Sections

    @ViewBuilder
    private var statusBannerSection: some View {
        if let err = downloadManager.lastErrorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button {
                    downloadManager.lastErrorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
        } else if let message = viewModel.statusBannerMessage {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isStatusError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(viewModel.isStatusError ? .red : .green)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button {
                    viewModel.statusBannerMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((viewModel.isStatusError ? Color.red : Color.green).opacity(0.12))
            )
        }
    }

    @ViewBuilder
    private var heroLocationHeader: some View {
        if let loc = viewModel.selectedLocationSet {
            let currentAsset = viewModel.currentTargetAsset
            VStack(alignment: .leading, spacing: 14) {
                // 顶部时段与镜头状态胶囊 + 自定义分组编辑/删除入口
                HStack(spacing: 8) {
                    Label(viewModel.currentPeriod.title, systemImage: viewModel.currentPeriod.symbolName)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(viewModel.currentPeriod.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .fixedSize()

                    if let currentAsset {
                        Text("当前镜头：\(currentAsset.displayName)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    if viewModel.isPaused {
                        Label("已锁定时段", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .fixedSize()
                    }

                    Spacer()

                    if loc.isCustomGroup {
                        Button {
                            editingCustomGroup = loc
                        } label: {
                            Label("编辑分组", systemImage: "pencil")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()

                        Button(role: .destructive) {
                            viewModel.deleteCustomGroup(id: loc.id)
                        } label: {
                            Label("删除分组", systemImage: "trash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .fixedSize()
                    }
                }

                Spacer(minLength: 16)

                // 自适应宽窄窗口的标题与操作按钮布局
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 16) {
                        heroTitleBlock(loc)
                        Spacer(minLength: 12)
                        heroActionButtons(loc)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        heroTitleBlock(loc)
                        heroActionButtons(loc)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 185, alignment: .bottomLeading)
            .background {
                ZStack {
                    if let aid = currentAsset?.id,
                       let nsImg = AerialCatalog.shared.previewImage(for: aid, maxPixelSize: 720) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [viewModel.currentPeriod.accentColor.opacity(0.7), .black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    LinearGradient(
                        colors: [.black.opacity(0.25), .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
    }

    @ViewBuilder
    private func heroTitleBlock(_ loc: AerialLocationSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(loc.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func heroActionButtons(_ loc: AerialLocationSet) -> some View {
        let hasAnyDownloaded = DayPeriod.allCases.contains { period in
            if let aid = loc.assetID(for: period, customMapping: viewModel.customPeriodAssetMapping) {
                return downloadManager.isDownloaded(aid)
            }
            return false
        }

        HStack(spacing: 8) {
            Button {
                viewModel.isAutoSwitchEnabled = true
                viewModel.isPaused = false
                viewModel.syncWallpaperNow(force: true)
            } label: {
                Label("立即应用当前时段", systemImage: "sparkles.tv")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.currentPeriod.accentColor)
            .fixedSize()

            if viewModel.isPaused {
                Button("恢复自动轮换") {
                    viewModel.isPaused = false
                }
                .buttonStyle(.bordered)
                .fixedSize()
            } else {
                Button("锁定当前画面") {
                    viewModel.lockedPeriod = viewModel.currentPeriod
                    viewModel.isPaused = true
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }

            if !downloadManager.activeDownloads.isEmpty {
                Button("停止后台下载 (\(downloadManager.activeDownloads.count))") {
                    downloadManager.cancelAllDownloads()
                }
                .buttonStyle(.bordered)
                .fixedSize()
            } else {
                Button("下载缺失视频") {
                    downloadManager.downloadMissingAssets(
                        for: loc,
                        customMapping: viewModel.customPeriodAssetMapping,
                        prioritizing: viewModel.currentPeriod
                    )
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }

            if hasAnyDownloaded {
                Button(role: .destructive) {
                    viewModel.deleteAllDownloadedVideos(in: loc)
                } label: {
                    Label("删除本组已下载视频", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
        }
    }

    // MARK: - Solar & Timeline Section

    private var solarAndTimelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题与模式切换（自适应宽度）
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    solarHeaderTitle
                    Spacer()
                    scheduleModePicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    solarHeaderTitle
                    scheduleModePicker
                }
            }

            // 第一行：地理位置选择控件
            HStack(spacing: 12) {
                Picker("位置来源", selection: $viewModel.locationMode) {
                    ForEach(LocationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 175)
                .fixedSize()

                switch viewModel.locationMode {
                case .presetCity:
                    Picker("城市", selection: $viewModel.selectedPresetCityName) {
                        ForEach(PresetCity.allCities) { city in
                            Text(city.displayName).tag(city.name)
                        }
                    }
                    .frame(width: 175)
                    .fixedSize()

                case .autoLocation:
                    HStack(spacing: 8) {
                        Button {
                            viewModel.locationService.requestCurrentLocation()
                        } label: {
                            Label(
                                viewModel.locationService.isLocating ? "正在定位..." : "刷新系统定位",
                                systemImage: "location.circle.fill"
                            )
                        }
                        .fixedSize()

                        Text(viewModel.activeCoordinates.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                case .manualCoordinates:
                    HStack(spacing: 6) {
                        Text("纬度:")
                            .font(.caption)
                            .fixedSize()
                        TextField("纬度", value: $viewModel.manualLatitude, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Text("经度:")
                            .font(.caption)
                            .fixedSize()
                        TextField("经度", value: $viewModel.manualLongitude, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }
                }

                Spacer()
            }

            // 第二行：今日日出、正午、日落、白昼时长指标卡
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 125, maximum: 220), spacing: 10)],
                spacing: 10
            ) {
                solarMetricBadge(
                    title: "今日日出",
                    value: viewModel.todaySolarEvents.sunriseTimeString,
                    icon: "sunrise.fill",
                    color: .orange
                )
                solarMetricBadge(
                    title: "太阳正午",
                    value: viewModel.todaySolarEvents.solarNoonTimeString,
                    icon: "sun.max.fill",
                    color: .yellow
                )
                solarMetricBadge(
                    title: "今日日落",
                    value: viewModel.todaySolarEvents.sunsetTimeString,
                    icon: "sunset.fill",
                    color: .pink
                )
                solarMetricBadge(
                    title: "白昼时长",
                    value: viewModel.todaySolarEvents.daylightDurationString,
                    icon: "clock.fill",
                    color: .cyan
                )
            }

            if let locErr = viewModel.locationService.errorMessage, viewModel.locationMode == .autoLocation {
                Text(locErr)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // 24小时时间轴视图（全部 5 个时段滑块均可直接拖拽，拖拽后自动切为自定义模式）
            TimelineBarView(
                schedule: viewModel.effectiveSchedule,
                currentDate: viewModel.now,
                solarEvents: viewModel.todaySolarEvents,
                onScheduleDragged: { updatedSchedule in
                    viewModel.updateTimelineFromDirectDrag(updatedSchedule)
                }
            )

            // 底部微调与提示栏
            if viewModel.scheduleMode == .solar {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        sunriseOffsetControl
                        sunsetOffsetControl
                        Spacer()
                        offsetResetButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            sunriseOffsetControl
                            sunsetOffsetControl
                        }
                        HStack {
                            Text("提示：直接拖动上方时间轴上的任一白色刻度滑块，即可自动转为自定义时间轴模式。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            offsetResetButton
                        }
                    }
                }
            } else {
                HStack {
                    Text("已处于自定义时间轴模式：直接拖动上方日出/清晨/白天/日落/夜晚刻度即可按 15 分钟为单位调整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.alignCustomTimelineWithTodaySolar()
                    } label: {
                        Label("按今日日出日落一键对齐", systemImage: "sun.and.horizon.fill")
                            .font(.caption)
                    }
                    .fixedSize()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var solarHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("所在地日出日落与 24h 时间轴")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text("可直接左右拖动时间轴上的任意时段刻度滑块（拖动后将自动切换至自定义时间轴模式）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var scheduleModePicker: some View {
        Picker("模式", selection: $viewModel.scheduleMode) {
            ForEach(ScheduleMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 250)
        .fixedSize()
    }

    private var sunriseOffsetControl: some View {
        HStack(spacing: 8) {
            Text("日出偏移: \(viewModel.sunriseOffsetMinutes >= 0 ? "+\(viewModel.sunriseOffsetMinutes)" : "\(viewModel.sunriseOffsetMinutes)")m")
                .font(.caption.monospacedDigit())
                .frame(width: 95, alignment: .leading)
                .fixedSize()
            Slider(
                value: Binding(
                    get: { Double(viewModel.sunriseOffsetMinutes) },
                    set: { viewModel.sunriseOffsetMinutes = Int($0.rounded()) }
                ),
                in: -60...60,
                step: 5
            )
            .frame(width: 120)
        }
    }

    private var sunsetOffsetControl: some View {
        HStack(spacing: 8) {
            Text("日落偏移: \(viewModel.sunsetOffsetMinutes >= 0 ? "+\(viewModel.sunsetOffsetMinutes)" : "\(viewModel.sunsetOffsetMinutes)")m")
                .font(.caption.monospacedDigit())
                .frame(width: 95, alignment: .leading)
                .fixedSize()
            Slider(
                value: Binding(
                    get: { Double(viewModel.sunsetOffsetMinutes) },
                    set: { viewModel.sunsetOffsetMinutes = Int($0.rounded()) }
                ),
                in: -60...60,
                step: 5
            )
            .frame(width: 120)
        }
    }

    @ViewBuilder
    private var offsetResetButton: some View {
        if viewModel.sunriseOffsetMinutes != 0 || viewModel.sunsetOffsetMinutes != 0 {
            Button("重置偏移") {
                viewModel.sunriseOffsetMinutes = 0
                viewModel.sunsetOffsetMinutes = 0
            }
            .font(.caption)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func solarMetricBadge(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - 5 Period Cards Section

    @ViewBuilder
    private var periodCardsSection: some View {
        if let loc = viewModel.selectedLocationSet {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("各时段对应航拍画面")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text("（支持单独下载或删除已缓存视频以释放空间）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()

                    Button {
                        isShowingNewGroupSheet = true
                    } label: {
                        Label("新建自定义分组", systemImage: "folder.badge.plus")
                            .font(.caption)
                    }
                    .fixedSize()

                    if !loc.isCustomGroup && viewModel.customPeriodAssetMapping[loc.id] != nil {
                        Button("恢复默认镜头分配") {
                            viewModel.resetCustomAssets(for: loc.id)
                        }
                        .font(.caption)
                        .fixedSize()
                    }
                }

                // 自适应网格：宽屏时一行 5 列，窗口缩小时自动换行为 3+2 或 2+2+1
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 162, maximum: 260), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(DayPeriod.allCases) { period in
                        periodCard(for: period, locationSet: loc)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func periodCard(for period: DayPeriod, locationSet: AerialLocationSet) -> some View {
        let selectedAssetID = locationSet.assetID(for: period, customMapping: viewModel.customPeriodAssetMapping) ?? ""
        let asset = AerialCatalog.shared.assetsByID[selectedAssetID]
        let isActivePeriod = viewModel.currentPeriod == period
        let isDownloaded = downloadManager.isDownloaded(selectedAssetID)
        let isDownloading = downloadManager.isDownloading(selectedAssetID)
        let progress = downloadManager.estimatedProgress(for: selectedAssetID)
        let videoSizeText = downloadManager.formattedSize(for: selectedAssetID)

        VStack(alignment: .leading, spacing: 8) {
            // 严格受控宽高的预览图容器
            Color.clear
                .frame(height: 96)
                .overlay {
                    if let nsImg = AerialCatalog.shared.previewImage(for: selectedAssetID, maxPixelSize: 320) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(period.accentColor.opacity(0.3))
                    }
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Label(period.shortTitle, systemImage: period.symbolName)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(period.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .fixedSize()

                        Spacer(minLength: 2)

                        if isActivePeriod {
                            Text("当前")
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .fixedSize()
                        }
                    }
                    .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // 起止时间与本地体积信息
            HStack {
                Text(viewModel.effectiveSchedule.timeRangeText(for: period))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if isDownloaded, let videoSizeText {
                    Text(videoSizeText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // 镜头选择菜单
            Menu {
                Section("当前分组镜头 (\(locationSet.name))") {
                    ForEach(locationSet.availableAssetIDs, id: \.self) { aid in
                        if let candidate = AerialCatalog.shared.assetsByID[aid] {
                            Button {
                                viewModel.setCustomAsset(aid, for: period, in: locationSet.id)
                            } label: {
                                HStack {
                                    Text(candidate.displayName)
                                    if aid == selectedAssetID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                Section("全部系统航拍镜头 (\(AerialCatalog.shared.allAssets.count))") {
                    ForEach(AerialCatalog.shared.allAssets) { candidate in
                        Button(candidate.displayName) {
                            viewModel.setCustomAsset(candidate.id, for: period, in: locationSet.id)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(asset?.displayName ?? "选择镜头")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )

            // 下载状态、删除视频选项与试用按钮
            HStack(spacing: 5) {
                if isDownloaded {
                    Label("已就绪", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .fixedSize()

                    Button(role: .destructive) {
                        viewModel.deleteDownloadedVideo(assetID: selectedAssetID)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("删除该时段的本地已下载视频文件以释放磁盘空间")
                } else if isDownloading {
                    HStack(spacing: 4) {
                        ProgressView(value: progress)
                            .frame(width: 34)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .fixedSize()
                    }
                } else {
                    Button {
                        downloadManager.downloadAsset(selectedAssetID, prioritize: true)
                    } label: {
                        Label("下载视频", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .fixedSize()
                }

                Spacer(minLength: 2)

                Button {
                    viewModel.applySpecificPeriod(period, lockPeriod: false)
                } label: {
                    Text("试用")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .fixedSize()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActivePeriod ? period.accentColor : Color.primary.opacity(0.08), lineWidth: isActivePeriod ? 2 : 1)
        )
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
