//
//  ResourceMonitor.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/19.
//

import Foundation
import Darwin
import Combine

/// 按需采集当前应用进程的内存占用 (phys_footprint)、CPU 占用率、应用包体积与航拍缓存体积
/// 仅在「设置」界面打开时启用定时采样，后台运行时零 CPU 开销
@MainActor
final class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()

    @Published private(set) var memoryMB: Double = 0.0
    @Published private(set) var cpuPercentage: Double = 0.0
    @Published private(set) var appBundleSizeMB: Double = 0.0
    @Published private(set) var aerialCacheSizeGB: Double = 0.0

    private var timer: Timer?

    var formattedMemory: String {
        String(format: "%.1f MB", memoryMB)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuPercentage)
    }

    var formattedAppSize: String {
        String(format: "%.2f MB", appBundleSizeMB)
    }

    var formattedAerialCacheSize: String {
        if aerialCacheSizeGB >= 1.0 {
            return String(format: "%.2f GB", aerialCacheSizeGB)
        } else {
            return String(format: "%.0f MB", aerialCacheSizeGB * 1024.0)
        }
    }

    private init() {
        appBundleSizeMB = Self.calculateDirectorySizeMB(url: Bundle.main.bundleURL)
        refreshMetrics()
    }

    func startMonitoring() {
        refreshMetrics()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refreshMetrics() {
        memoryMB = Self.currentPhysicalFootprintMB()
        cpuPercentage = Self.currentProcessCPUPercentage()
        if appBundleSizeMB <= 0.01 {
            appBundleSizeMB = Self.calculateDirectorySizeMB(url: Bundle.main.bundleURL)
        }
        aerialCacheSizeGB = Double(AssetDownloadManager.shared.totalCachedBytes) / (1024.0 * 1024.0 * 1024.0)
    }

    /// 使用 Mach TASK_VM_INFO 读取与 macOS「活动监视器」一致的物理内存占用 (phys_footprint)
    nonisolated static func currentPhysicalFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    /// 使用 Mach task_threads + THREAD_BASIC_INFO 汇总当前进程所有线程的实时 CPU 占用率
    nonisolated static func currentProcessCPUPercentage() -> Double {
        var threadsList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let kerr = task_threads(mach_task_self_, &threadsList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadsList else { return 0.0 }

        defer {
            let deallocSize = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), deallocSize)
        }

        var totalCPU: Double = 0.0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let thKerr = withUnsafeMutablePointer(to: &threadInfo) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) { intPtr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &threadInfoCount)
                }
            }
            if thKerr == KERN_SUCCESS && (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                totalCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            }
        }
        return totalCPU
    }

    /// 递归计算指定目录/App Bundle 的磁盘占用大小 (MB)
    nonisolated static func calculateDirectorySizeMB(url: URL) -> Double {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0.0
        }

        var totalBytes: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                totalBytes += UInt64(size)
            }
        }
        return Double(totalBytes) / (1024.0 * 1024.0)
    }
}
