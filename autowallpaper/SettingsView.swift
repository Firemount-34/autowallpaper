//
//  SettingsView.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/19.
//

import SwiftUI
import AppKit

/// 独立的「应用设置」界面：包含 Dock 栏图标显示、开机自启、屏保同步、资源与缓存监控及恢复原壁纸
struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var resourceMonitor = ResourceMonitor.shared
    @ObservedObject var downloadManager = AssetDownloadManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 顶部应用信息横幅
                HStack(spacing: 14) {
                    Image(nsImage: AppViewModel.loadOrRenderAppIcon())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aerial 日出日落自动壁纸")
                            .font(.title3.weight(.bold))
                        Text("根据所在地天文日出日落时间或自定义时间轴，自动切换 macOS 原生航拍壁纸")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // 1. 常规与系统集成设置
                VStack(alignment: .leading, spacing: 14) {
                    Label("常规与启动设置", systemImage: "gearshape.2.fill")
                        .font(.headline)

                    Divider()

                    Toggle(isOn: $viewModel.showDockIcon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("在程序坞 (Dock) 中显示应用图标")
                                .font(.body.weight(.medium))
                            Text("关闭后应用将仅作为顶部状态栏（菜单栏）小工具在后台静默运行")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(
                        isOn: Binding(
                            get: { viewModel.launchAtLogin },
                            set: { viewModel.toggleLaunchAtLogin($0) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("登录 macOS 时自动启动")
                                .font(.body.weight(.medium))
                            Text("开机进入桌面后自动在后台按日出日落时间校准航拍壁纸")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $viewModel.syncScreenSaver) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("同时将航拍壁纸同步至屏幕保护程序 (Screen Saver)")
                                .font(.body.weight(.medium))
                            Text("切换桌面壁纸时，同步更新系统闲置屏保为同一时段的航拍画面")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                // 2. 内存、CPU 与磁盘占用监控
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("资源占用与缓存监控", systemImage: "gauge.with.dots.needle.33percent")
                            .font(.headline)
                        Spacer()
                        Button {
                            resourceMonitor.refreshMetrics()
                        } label: {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        metricCard(
                            title: "当前内存占用 (phys_footprint)",
                            value: resourceMonitor.formattedMemory,
                            icon: "memorychip",
                            color: .blue
                        )
                        metricCard(
                            title: "当前进程 CPU 占用率",
                            value: resourceMonitor.formattedCPU,
                            icon: "cpu",
                            color: .green
                        )
                        metricCard(
                            title: "应用包大小 (App Bundle)",
                            value: resourceMonitor.formattedAppSize,
                            icon: "app.badge.checkmark",
                            color: .purple
                        )
                        metricCard(
                            title: "系统已缓存航拍视频 (4KSDR240FPS)",
                            value: "\(resourceMonitor.formattedAerialCacheSize) (\(downloadManager.downloadedAssetIDs.count) 个视频)",
                            icon: "internaldrive",
                            color: .orange
                        )
                    }

                    HStack {
                        Text("航拍视频存储路径：/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            let url = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS")
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("在访达中打开缓存目录", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
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

                // 3. 壁纸配置重置与恢复
                VStack(alignment: .leading, spacing: 12) {
                    Label("壁纸接管与恢复", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.headline)

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("恢复接管前的系统原壁纸")
                                .font(.body.weight(.medium))
                            Text(
                                WallpaperSwitcherService.shared.hasBackup
                                    ? "已检测到您在启用本应用前的原始壁纸配置备份，可随时一键还原。"
                                    : "当前暂无原始壁纸备份文件，点击将停止自动切换。"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.disableAndRestoreOriginalWallpaper()
                        } label: {
                            Label("关闭并恢复系统原壁纸", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
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
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 560)
        .onAppear {
            resourceMonitor.startMonitoring()
        }
        .onDisappear {
            resourceMonitor.stopMonitoring()
        }
    }

    @ViewBuilder
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.callout.weight(.bold).monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
