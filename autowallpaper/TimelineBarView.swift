//
//  TimelineBarView.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import SwiftUI
import AppKit

/// 可视化 24 小时日出日落时间轴组件（支持直接拖拽全部 5 个时段刻度滑块，拖拽时自动切换为自定义时间轴模式）
struct TimelineBarView: View {
    let schedule: TimelineSchedule
    let currentDate: Date
    let solarEvents: SolarEvents
    let onScheduleDragged: (TimelineSchedule) -> Void

    @State private var draggingPeriod: DayPeriod?
    @State private var hoveredPeriod: DayPeriod?

    private let barHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let totalWidth = max(1, geo.size.width)
                let centerY = (barHeight + 28) / 2

                ZStack(alignment: .leading) {
                    // 1. 分段彩色背景条
                    HStack(spacing: 0) {
                        segmentRect(
                            period: .night,
                            startMins: 0,
                            endMins: schedule.sunriseMinutes,
                            totalWidth: totalWidth
                        )
                        segmentRect(
                            period: .sunrise,
                            startMins: schedule.sunriseMinutes,
                            endMins: schedule.morningMinutes,
                            totalWidth: totalWidth
                        )
                        segmentRect(
                            period: .morning,
                            startMins: schedule.morningMinutes,
                            endMins: schedule.dayMinutes,
                            totalWidth: totalWidth
                        )
                        segmentRect(
                            period: .day,
                            startMins: schedule.dayMinutes,
                            endMins: schedule.sunsetMinutes,
                            totalWidth: totalWidth
                        )
                        segmentRect(
                            period: .sunset,
                            startMins: schedule.sunsetMinutes,
                            endMins: schedule.nightMinutes,
                            totalWidth: totalWidth
                        )
                        segmentRect(
                            period: .night,
                            startMins: schedule.nightMinutes,
                            endMins: 1440,
                            totalWidth: totalWidth
                        )
                    }
                    .frame(height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .position(x: totalWidth / 2, y: centerY)

                    // 2. 当前时间竖线指针
                    let nowX = xPosition(for: currentMinutes, width: totalWidth)
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: barHeight)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .position(x: nowX, y: centerY - 2)
                    .allowsHitTesting(false)

                    // 3. 5 个时段分界刻度滑块渲染
                    ForEach(DayPeriod.allCases) { period in
                        let mins = schedule.startMinutes(for: period)
                        let handleX = xPosition(for: mins, width: totalWidth)
                        let isDragging = (draggingPeriod == period)
                        let isHovered = (hoveredPeriod == period)

                        handleView(
                            for: period,
                            minutes: mins,
                            isDragging: isDragging,
                            isHovered: isHovered
                        )
                        .position(x: handleX, y: centerY)
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                // 统一根据鼠标 X 坐标定位距离最近的刻度手柄，彻底避免 SwiftUI .position() 全屏遮挡导致只能拖最后一个滑块的问题
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let nearest = nearestPeriodHandle(at: location.x, totalWidth: totalWidth, maxDistance: 18) {
                            if hoveredPeriod != nearest {
                                hoveredPeriod = nearest
                                NSCursor.resizeLeftRight.set()
                            }
                        } else if hoveredPeriod != nil {
                            hoveredPeriod = nil
                            NSCursor.arrow.set()
                        }
                    case .ended:
                        hoveredPeriod = nil
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if draggingPeriod == nil {
                                // 按下瞬间锁定距离起点最近的那个时段滑块（日出/清晨/白天/日落/夜晚均可精准命中）
                                draggingPeriod = nearestPeriodHandle(
                                    at: value.startLocation.x,
                                    totalWidth: totalWidth,
                                    maxDistance: .infinity
                                )
                            }
                            guard let targetPeriod = draggingPeriod else { return }
                            let ratio = max(0, min(1, value.location.x / totalWidth))
                            let newMins = Int((ratio * 1440.0).rounded())
                            var updated = schedule
                            updated.setStartMinutes(newMins, for: targetPeriod)
                            if updated != schedule {
                                onScheduleDragged(updated)
                            }
                        }
                        .onEnded { _ in
                            draggingPeriod = nil
                        }
                )
            }
            .frame(height: barHeight + 28)

            // 刻度尺标签
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            // 各时段起止时间徽章行
            HStack(spacing: 8) {
                ForEach(DayPeriod.allCases) { period in
                    let isCurrent = schedule.currentPeriod(at: currentDate) == period
                    let isHighlighted = (draggingPeriod == period) || (hoveredPeriod == period) || isCurrent
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: period.symbolName)
                                .font(.caption2)
                                .foregroundStyle(period.accentColor)
                            Text(period.shortTitle)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        Text(TimelineSchedule.formatMinutes(schedule.startMinutes(for: period)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(draggingPeriod == period ? period.accentColor : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHighlighted ? period.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isHighlighted ? period.accentColor : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    /// 查找距离给定 X 坐标最近的时段滑块
    private func nearestPeriodHandle(at x: CGFloat, totalWidth: CGFloat, maxDistance: CGFloat) -> DayPeriod? {
        var bestPeriod: DayPeriod?
        var bestDist: CGFloat = maxDistance

        for period in DayPeriod.allCases {
            let hx = xPosition(for: schedule.startMinutes(for: period), width: totalWidth)
            let dist = abs(hx - x)
            if dist <= bestDist {
                bestDist = dist
                bestPeriod = period
            }
        }
        return bestPeriod
    }

    private var currentMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: currentDate)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func xPosition(for minutes: Int, width: CGFloat) -> CGFloat {
        let clamped = max(0, min(1440, minutes))
        return CGFloat(clamped) / 1440.0 * width
    }

    @ViewBuilder
    private func segmentRect(period: DayPeriod, startMins: Int, endMins: Int, totalWidth: CGFloat) -> some View {
        let duration = max(0, endMins - startMins)
        let segWidth = CGFloat(duration) / 1440.0 * totalWidth
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [period.accentColor.opacity(0.85), period.accentColor.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: segWidth)
    }

    @ViewBuilder
    private func handleView(
        for period: DayPeriod,
        minutes: Int,
        isDragging: Bool,
        isHovered: Bool
    ) -> some View {
        ZStack {
            // 滑块手柄本体
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white)
                .frame(width: (isDragging || isHovered) ? 14 : 10, height: barHeight + 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(period.accentColor, lineWidth: (isDragging || isHovered) ? 2.5 : 2)
                )
                .overlay(
                    Capsule()
                        .fill(period.accentColor.opacity(0.85))
                        .frame(width: 2, height: 14)
                )
                .shadow(color: .black.opacity(0.3), radius: isDragging ? 4 : 2)

            // 拖拽或悬停时顶部浮动时间气泡
            if isDragging || isHovered {
                Text("\(period.shortTitle) \(TimelineSchedule.formatMinutes(minutes))")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(period.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .fixedSize()
                    .offset(y: -(barHeight / 2 + 16))
            }
        }
    }
}
