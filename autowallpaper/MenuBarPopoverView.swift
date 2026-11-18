//
//  MenuBarPopoverView.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import SwiftUI
import AppKit

/// 菜单栏快捷弹窗界面（对标 YnNJU/aerial-switcher 菜单栏体验并增强日出日落信息）
struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var downloadManager = AssetDownloadManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 顶部标题与总开关
            HStack {
                HStack(spacing: 8) {
                    Image(nsImage: AppViewModel.loadOrRenderAppIcon())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aerial 日出日落壁纸")
                            .font(.headline)
                        Text(statusSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $viewModel.isAutoSwitchEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            // 2. 当前壁纸预览卡片 + 今日日出日落概览
            if let asset = viewModel.currentTargetAsset {
                let isReady = downloadManager.isDownloaded(asset.id)
                let isDownloading = downloadManager.isDownloading(asset.id)

                Color.clear
                    .frame(height: 118)
                    .overlay {
                        if let nsImg = AerialCatalog.shared.previewImage(for: asset.id, maxPixelSize: 420) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFill()
                        } else {
                            LinearGradient(
                                colors: [viewModel.currentPeriod.accentColor.opacity(0.6), .black],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(viewModel.currentPeriod.title)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(viewModel.currentPeriod.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())

                                if viewModel.isPaused {
                                    Text("已锁定")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }

                                if !isReady {
                                    Text(isDownloading ? "系统下载中..." : "未下载")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isDownloading ? Color.blue : Color.gray)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                let nextInfo = viewModel.nextTransitionInfo
                                Text("下次: \(nextInfo.period.shortTitle) \(nextInfo.timeString)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                            }

                            Text(asset.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 3. 所在地日出日落时间条
            HStack(spacing: 10) {
                Label(viewModel.activeCoordinates.label, systemImage: "location.fill")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(.orange)
                    Text(viewModel.todaySolarEvents.sunriseTimeString)
                        .monospacedDigit()
                }
                .font(.caption)

                HStack(spacing: 4) {
                    Image(systemName: "sunset.fill")
                        .foregroundStyle(.pink)
                    Text(viewModel.todaySolarEvents.sunsetTimeString)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )

            // 4. 航拍地点快速选择
            HStack {
                Text("航拍地点")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $viewModel.selectedLocationSetID) {
                    ForEach(viewModel.locationSets) { loc in
                        Text(loc.name).tag(loc.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            // 5. 五个时段快捷切换与锁定
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("时段快捷切换（点击立即预览/锁定）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isPaused {
                        Button("恢复自动轮换") {
                            viewModel.isPaused = false
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(DayPeriod.allCases) { period in
                        let isSelected = viewModel.currentPeriod == period
                        Button {
                            viewModel.applySpecificPeriod(period, lockPeriod: true)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: period.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? .white : period.accentColor)
                                Text(period.shortTitle)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? period.accentColor : Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let msg = viewModel.statusBannerMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(viewModel.isStatusError ? .red : .secondary)
                    .lineLimit(2)
            }

            Divider()

            // 6. 底部操作栏
            HStack(spacing: 8) {
                Button {
                    viewModel.syncWallpaperNow(force: true)
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Label("打开主界面", systemImage: "macwindow")
                        .font(.caption)
                }

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(.caption)
                }

                Spacer()

                Menu {
                    Button("打开应用设置...") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "settings")
                    }
                    Button("恢复系统原壁纸并停用") {
                        viewModel.disableAndRestoreOriginalWallpaper()
                    }
                    Divider()
                    Button("退出应用", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var statusSubtitle: String {
        if !viewModel.isAutoSwitchEnabled {
            return "自动切换已关闭"
        }
        if viewModel.isPaused {
            return "已暂停轮换 · 锁定在\(viewModel.currentPeriod.shortTitle)"
        }
        return "\(viewModel.scheduleMode.title) · 运行中"
    }
}
