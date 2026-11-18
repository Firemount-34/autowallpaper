//
//  CustomGroupSheetView.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/19.
//

import SwiftUI
import AppKit

/// 新建或编辑自定义航拍壁纸分组的弹窗视图
struct CustomGroupSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var downloadManager = AssetDownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    /// 若为 nil 表示新建分组，否则为编辑已有自定义分组
    let editingGroup: AerialLocationSet?

    @State private var groupName: String = ""
    @State private var groupSummary: String = ""
    @State private var selectedPeriod: DayPeriod = .sunrise
    @State private var periodAssets: [DayPeriod: String] = [:]
    @State private var searchText: String = ""
    @State private var onlyShowDownloaded: Bool = false

    init(viewModel: AppViewModel, editingGroup: AerialLocationSet? = nil) {
        self.viewModel = viewModel
        self.editingGroup = editingGroup

        if let group = editingGroup {
            _groupName = State(initialValue: group.name)
            _groupSummary = State(initialValue: group.summary)
            var initialMap: [DayPeriod: String] = [:]
            for p in DayPeriod.allCases {
                initialMap[p] = group.assetID(for: p, customMapping: viewModel.customPeriodAssetMapping)
                    ?? group.defaultPeriodAssets[p]
                    ?? ""
            }
            _periodAssets = State(initialValue: initialMap)
        } else {
            let base = viewModel.selectedLocationSet ?? AerialCatalog.shared.locationSets.first
            _groupName = State(initialValue: "我的专属航拍 \(viewModel.customLocationSets.count + 1)")
            _groupSummary = State(initialValue: "跨地点自由混搭日出日落航拍壁纸")
            var initialMap: [DayPeriod: String] = [:]
            let fallbackID = AerialCatalog.shared.allAssets.first?.id ?? ""
            for p in DayPeriod.allCases {
                initialMap[p] = base?.assetID(for: p, customMapping: viewModel.customPeriodAssetMapping)
                    ?? base?.defaultPeriodAssets[p]
                    ?? fallbackID
            }
            _periodAssets = State(initialValue: initialMap)
        }
    }

    private var filteredAssets: [AerialAsset] {
        AerialCatalog.shared.allAssets.filter { asset in
            if onlyShowDownloaded && !downloadManager.isDownloaded(asset.id) {
                return false
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty { return true }
            return asset.zhName.localizedCaseInsensitiveContains(query)
                || asset.enName.localizedCaseInsensitiveContains(query)
                || asset.shotID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. 顶部标题栏
            HStack {
                Label(
                    editingGroup == nil ? "新建自定义航拍分组" : "编辑自定义分组",
                    systemImage: "folder.badge.plus"
                )
                .font(.title3.weight(.bold))

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(editingGroup == nil ? "创建并启用分组" : "保存修改") {
                    saveGroup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            // 2. 分组名称与描述表单
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分组名称")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：山海昼夜混搭", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("分组简介")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("可选备注说明", text: $groupSummary)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("快速模板")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(viewModel.builtInLocationSets) { preset in
                            Button("复制「\(preset.name)」的镜头配置") {
                                for p in DayPeriod.allCases {
                                    if let aid = preset.defaultPeriodAssets[p] {
                                        periodAssets[p] = aid
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("从预设地点填充", systemImage: "square.on.square")
                    }
                    .fixedSize()
                }
            }

            // 3. 五个时段当前已选画面选项卡（点击切换下方图库正在分配的时段）
            VStack(alignment: .leading, spacing: 8) {
                Text("第 1 步：点击选择要配置的时段（可为 5 个时段分别挑选任意航拍画面）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(DayPeriod.allCases) { period in
                        let aid = periodAssets[period] ?? ""
                        let asset = AerialCatalog.shared.assetsByID[aid]
                        let isSelected = (selectedPeriod == period)
                        let isReady = downloadManager.isDownloaded(aid)

                        Button {
                            selectedPeriod = period
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Color.clear
                                    .frame(height: 64)
                                    .overlay {
                                        if let nsImg = AerialCatalog.shared.previewImage(for: aid, maxPixelSize: 220) {
                                            Image(nsImage: nsImg)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Rectangle()
                                                .fill(period.accentColor.opacity(0.3))
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        HStack(spacing: 3) {
                                            Image(systemName: period.symbolName)
                                            Text(period.shortTitle)
                                        }
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(period.accentColor)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                        .padding(4)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if isReady {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                                .background(Circle().fill(.black.opacity(0.6)))
                                                .padding(4)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Text(asset?.displayName ?? "未选择")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? period.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? period.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 4. 下方全量航拍图库选择器
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Text("第 2 步：为")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Label(selectedPeriod.title, systemImage: selectedPeriod.symbolName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selectedPeriod.accentColor)
                        Text("点选航拍镜头（共 \(filteredAssets.count) 个可选）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("仅看已下载", isOn: $onlyShowDownloaded)
                        .font(.caption)
                        .toggleStyle(.checkbox)

                    TextField("搜索航拍名称（如：长城、红杉、索诺马、夜景）", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(filteredAssets) { asset in
                            let currentChosenID = periodAssets[selectedPeriod]
                            let isChosen = (currentChosenID == asset.id)
                            let isDownloaded = downloadManager.isDownloaded(asset.id)
                            let sizeLabel = downloadManager.formattedSize(for: asset.id)

                            Button {
                                periodAssets[selectedPeriod] = asset.id
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Color.clear
                                        .frame(height: 76)
                                        .overlay {
                                            if let nsImg = AerialCatalog.shared.previewImage(for: asset.id, maxPixelSize: 220) {
                                                Image(nsImage: nsImg)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.secondary.opacity(0.2))
                                            }
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if isChosen {
                                                Label("已选", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(selectedPeriod.accentColor)
                                                    .foregroundStyle(.white)
                                                    .clipShape(Capsule())
                                                    .padding(5)
                                            }
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            if isDownloaded {
                                                Text(sizeLabel.map { "已下载 · \($0)" } ?? "已下载")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.black.opacity(0.7))
                                                    .foregroundStyle(.green)
                                                    .clipShape(Capsule())
                                                    .padding(5)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    Text(asset.displayName)
                                        .font(.caption.weight(isChosen ? .bold : .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isChosen ? selectedPeriod.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isChosen ? selectedPeriod.accentColor : Color.primary.opacity(0.08), lineWidth: isChosen ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 230, maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.05))
                )
            }
        }
        .padding(20)
        .frame(width: 780, height: 610)
    }

    private func saveGroup() {
        if let editing = editingGroup {
            viewModel.updateCustomGroup(
                id: editing.id,
                name: groupName,
                summary: groupSummary,
                periodAssets: periodAssets
            )
        } else {
            viewModel.createCustomGroup(
                name: groupName,
                summary: groupSummary,
                periodAssets: periodAssets
            )
        }
        dismiss()
    }
}
