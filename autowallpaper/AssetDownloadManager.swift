//
//  AssetDownloadManager.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import Combine

/// 处理苹果航拍服务器 (sylvan.apple.com) 证书信任与 URLSession 节流进度回调（避免高频刷新主线程）
private final class AerialURLSessionDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((String, Double) -> Void)?
    var onFinishedToTempFile: ((String, URL) -> Void)?
    var onFailed: ((String, Error) -> Void)?

    private var taskAssetMap: [Int: String] = [:]
    private var lastReportedProgress: [Int: Double] = [:]
    private var lastReportTimestamp: [Int: TimeInterval] = [:]
    private let lock = NSLock()

    func register(taskIdentifier: Int, assetID: String) {
        lock.lock()
        taskAssetMap[taskIdentifier] = assetID
        lastReportedProgress[taskIdentifier] = 0.0
        lastReportTimestamp[taskIdentifier] = 0.0
        lock.unlock()
    }

    func cancelAndRemove(assetID: String, in session: URLSession) {
        lock.lock()
        let matchingTaskIDs = taskAssetMap.filter { $0.value == assetID }.map { $0.key }
        for tid in matchingTaskIDs {
            taskAssetMap.removeValue(forKey: tid)
            lastReportedProgress.removeValue(forKey: tid)
            lastReportTimestamp.removeValue(forKey: tid)
        }
        lock.unlock()

        session.getAllTasks { tasks in
            for task in tasks where matchingTaskIDs.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
    }

    private func assetID(for taskIdentifier: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return taskAssetMap[taskIdentifier]
    }

    private func shouldReportProgress(_ progress: Double, for taskIdentifier: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let lastTime = lastReportTimestamp[taskIdentifier] ?? 0
        let lastProg = lastReportedProgress[taskIdentifier] ?? 0
        // 至少间隔 0.25 秒且进度变化超过 1% 才向主线程派发 UI 更新，大幅降低下载期间的 CPU 开销
        if (now - lastTime >= 0.25 && abs(progress - lastProg) >= 0.01) || progress >= 0.99 {
            lastReportTimestamp[taskIdentifier] = now
            lastReportedProgress[taskIdentifier] = progress
            return true
        }
        return false
    }

    private func removeTask(_ taskIdentifier: Int) {
        lock.lock()
        taskAssetMap.removeValue(forKey: taskIdentifier)
        lastReportedProgress.removeValue(forKey: taskIdentifier)
        lastReportTimestamp.removeValue(forKey: taskIdentifier)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host.hasSuffix("apple.com"),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let tid = downloadTask.taskIdentifier
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 400_000_000
        let progress = min(0.99, max(0.01, Double(totalBytesWritten) / Double(expected)))
        guard shouldReportProgress(progress, for: tid),
              let assetID = assetID(for: tid) else { return }
        onProgress?(assetID, progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let assetID = assetID(for: downloadTask.taskIdentifier) else { return }
        defer { removeTask(downloadTask.taskIdentifier) }

        if let httpResp = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResp.statusCode) {
            let err = NSError(
                domain: "AerialDownloadError",
                code: httpResp.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "服务器返回 HTTP \(httpResp.statusCode)"]
            )
            onFailed?(assetID, err)
            return
        }

        let fm = FileManager.default
        let stagingDir = URL(fileURLWithPath: "/tmp/autowallpaper-downloads", isDirectory: true)
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedURL = stagingDir.appendingPathComponent("\(assetID).mov")

        do {
            if fm.fileExists(atPath: stagedURL.path) {
                try? fm.removeItem(at: stagedURL)
            }
            try fm.moveItem(at: location, to: stagedURL)

            let attrs = try fm.attributesOfItem(atPath: stagedURL.path)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            guard fileSize > 50_000_000 else {
                try? fm.removeItem(at: stagedURL)
                let err = NSError(
                    domain: "AerialDownloadError",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "下载的视频文件不完整（大小不足 50MB）"]
                )
                onFailed?(assetID, err)
                return
            }

            onFinishedToTempFile?(assetID, stagedURL)
        } catch {
            onFailed?(assetID, error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error,
              let assetID = assetID(for: task.taskIdentifier) else { return }
        removeTask(task.taskIdentifier)
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }
        onFailed?(assetID, error)
    }
}

/// 独立后台下载航拍视频并写入 `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/`
/// 采用内核级 kqueue 目录事件监听代替轮询，闲置 CPU 占用为 0%
@MainActor
final class AssetDownloadManager: ObservableObject {
    static let shared = AssetDownloadManager()

    let systemVideosDir = "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS"

    /// 系统中真实已下载完成（>50MB）的航拍 Asset ID 集合
    @Published private(set) var downloadedAssetIDs: Set<String> = []
    /// 缓存每个已下载视频的体积描述（避免 UI 渲染时重复调用磁盘 stat）
    private(set) var cachedSizeTexts: [String: String] = [:]
    /// 缓存系统已下载视频的总字节数
    private(set) var totalCachedBytes: UInt64 = 0

    /// 正在后台 HTTP 下载中的 Asset ID 集合
    @Published private(set) var activeDownloads: Set<String> = []
    /// 每个下载任务的真实字节进度 (0.0 ~ 1.0)
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published var lastErrorMessage: String?

    var onAssetDownloaded: ((String) -> Void)?

    private let sessionDelegate = AerialURLSessionDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    private var dirWatcherSource: DispatchSourceFileSystemObject?
    private var dirFileDescriptor: Int32 = -1

    private init() {
        setupSessionCallbacks()
        refreshSystemDownloadedAssets()
        startKernelDirectoryWatcher()
    }

    private func setupSessionCallbacks() {
        sessionDelegate.onProgress = { [weak self] assetID, progress in
            Task { @MainActor in
                self?.downloadProgress[assetID] = progress
            }
        }

        sessionDelegate.onFinishedToTempFile = { [weak self] assetID, stagedURL in
            Task { @MainActor in
                self?.installStagedVideoToSystemDirectory(assetID: assetID, stagedURL: stagedURL)
            }
        }

        sessionDelegate.onFailed = { [weak self] assetID, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.activeDownloads.remove(assetID)
                self.downloadProgress.removeValue(forKey: assetID)
                let name = AerialCatalog.shared.assetsByID[assetID]?.displayName ?? assetID
                self.lastErrorMessage = "下载「\(name)」失败：\(error.localizedDescription)"
            }
        }
    }

    /// 使用 macOS 内核 kqueue (DispatchSourceFileSystemObject) 监听 4KSDR240FPS 目录变动，零轮询开销
    private func startKernelDirectoryWatcher() {
        let fd = open(systemVideosDir, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshSystemDownloadedAssets()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dirWatcherSource = source
    }

    /// 将下载完成的临时 `.mov` 安装到 `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/`
    private func installStagedVideoToSystemDirectory(assetID: String, stagedURL: URL) {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: "\(systemVideosDir)/\(assetID).mov")

        do {
            if fm.isWritableFile(atPath: systemVideosDir) {
                if fm.fileExists(atPath: destURL.path) {
                    try? fm.removeItem(at: destURL)
                }
                try fm.moveItem(at: stagedURL, to: destURL)
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destURL.path)
            } else {
                let escapedSrc = stagedURL.path.replacingOccurrences(of: "'", with: "'\\''")
                let escapedDst = destURL.path.replacingOccurrences(of: "'", with: "'\\''")
                let escapedDir = systemVideosDir.replacingOccurrences(of: "'", with: "'\\''")
                let cmd = "mkdir -p '\(escapedDir)' && chmod 775 '\(escapedDir)' && mv -f '\(escapedSrc)' '\(escapedDst)' && chmod 644 '\(escapedDst)'"
                let scriptSource = "do shell script \"\(cmd)\" with administrator privileges"

                if let script = NSAppleScript(source: scriptSource) {
                    var errorDict: NSDictionary?
                    script.executeAndReturnError(&errorDict)
                    if let errorDict = errorDict {
                        try? fm.removeItem(at: stagedURL)
                        let msg = (errorDict[NSAppleScript.errorMessage] as? String) ?? "未授予管理员权限写入系统航拍目录"
                        throw NSError(domain: "AerialInstallError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                }
            }

            activeDownloads.remove(assetID)
            downloadProgress[assetID] = 1.0
            refreshSystemDownloadedAssets()
            onAssetDownloaded?(assetID)
        } catch {
            activeDownloads.remove(assetID)
            downloadProgress.removeValue(forKey: assetID)
            lastErrorMessage = "安装航拍视频到系统目录失败：\(error.localizedDescription)"
        }
    }

    /// 扫描 `/Library/Application Support/com.apple.idleassetsd/Customer/` 获取真实已就绪的航拍视频与体积缓存
    func refreshSystemDownloadedAssets() {
        let fm = FileManager.default
        let subdirs = ["4KSDR240FPS", "4KHDR", "4KSDR", "2KSDR", "2KHDR", "2KAVC"]
        let baseDir = "/Library/Application Support/com.apple.idleassetsd/Customer"

        var readyIDs = Set<String>()
        var sizeMap: [String: String] = [:]
        var sumBytes: UInt64 = 0

        for sub in subdirs {
            let dirPath = "\(baseDir)/\(sub)"
            guard let items = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in items where file.hasSuffix(".mov") {
                let fullPath = "\(dirPath)/\(file)"
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? UInt64,
                   size > 50_000_000 {
                    let assetID = String(file.dropLast(4))
                    readyIDs.insert(assetID)
                    sumBytes += size
                    let mb = Double(size) / (1024.0 * 1024.0)
                    sizeMap[assetID] = String(format: "%.0f MB", mb)
                }
            }
        }

        cachedSizeTexts = sizeMap
        totalCachedBytes = sumBytes

        if readyIDs != downloadedAssetIDs {
            downloadedAssetIDs = readyIDs
        }

        for aid in readyIDs where activeDownloads.contains(aid) {
            activeDownloads.remove(aid)
            downloadProgress.removeValue(forKey: aid)
        }
    }

    func isDownloaded(_ assetID: String) -> Bool {
        downloadedAssetIDs.contains(assetID)
    }

    func formattedSize(for assetID: String) -> String? {
        cachedSizeTexts[assetID]
    }

    func isDownloading(_ assetID: String) -> Bool {
        activeDownloads.contains(assetID) && !isDownloaded(assetID)
    }

    func estimatedProgress(for assetID: String) -> Double {
        if isDownloaded(assetID) { return 1.0 }
        return downloadProgress[assetID] ?? 0.02
    }

    /// 直接通过后台 HTTP 下载指定航拍视频（不修改当前桌面壁纸配置、不重启 WallpaperAgent）
    func downloadAsset(_ assetID: String, prioritize: Bool = false) {
        guard !isDownloaded(assetID), !isDownloading(assetID) else { return }

        guard let asset = AerialCatalog.shared.assetsByID[assetID],
              let urlString = asset.videoURL,
              let url = URL(string: urlString) else {
            lastErrorMessage = "未找到该航拍视频 (\(assetID)) 的苹果服务器下载链接。"
            return
        }

        lastErrorMessage = nil
        activeDownloads.insert(assetID)
        downloadProgress[assetID] = 0.01

        let task = session.downloadTask(with: url)
        sessionDelegate.register(taskIdentifier: task.taskIdentifier, assetID: assetID)
        task.resume()
    }

    /// 批量后台下载当前地点所有未下载时段的视频
    func downloadMissingAssets(
        for locationSet: AerialLocationSet,
        customMapping: [String: [String: String]],
        prioritizing currentPeriod: DayPeriod? = nil
    ) {
        var orderedAssetIDs: [String] = []
        if let currentPeriod,
           let currentID = locationSet.assetID(for: currentPeriod, customMapping: customMapping),
           !isDownloaded(currentID) {
            orderedAssetIDs.append(currentID)
        }

        for period in DayPeriod.allCases {
            if let aid = locationSet.assetID(for: period, customMapping: customMapping),
               !isDownloaded(aid),
               !orderedAssetIDs.contains(aid) {
                orderedAssetIDs.append(aid)
            }
        }

        for aid in orderedAssetIDs {
            downloadAsset(aid)
        }
    }

    /// 取消所有正在进行的下载
    func cancelAllDownloads() {
        for aid in activeDownloads {
            sessionDelegate.cancelAndRemove(assetID: aid, in: session)
        }
        activeDownloads.removeAll()
        downloadProgress.removeAll()
    }

    /// 删除指定的一个或多个已下载航拍视频文件（释放磁盘空间）
    @discardableResult
    func deleteDownloadedAssets(_ assetIDs: [String]) -> Result<String, Error> {
        let fm = FileManager.default
        var targetURLs: [URL] = []
        var totalBytes: UInt64 = 0

        for aid in Set(assetIDs) {
            if activeDownloads.contains(aid) {
                sessionDelegate.cancelAndRemove(assetID: aid, in: session)
                activeDownloads.remove(aid)
                downloadProgress.removeValue(forKey: aid)
            }
            let urls = AerialCatalog.shared.localVideoFiles(for: aid)
            for u in urls {
                if let attrs = try? fm.attributesOfItem(atPath: u.path),
                   let size = attrs[.size] as? UInt64 {
                    totalBytes += size
                }
                targetURLs.append(u)
            }
        }

        guard !targetURLs.isEmpty else {
            refreshSystemDownloadedAssets()
            return .success("该壁纸本地尚无缓存视频文件。")
        }

        var needsAdminPaths: [String] = []
        for url in targetURLs {
            do {
                try fm.removeItem(at: url)
            } catch {
                needsAdminPaths.append(url.path)
            }
        }

        if !needsAdminPaths.isEmpty {
            let quotedPaths = needsAdminPaths.map { path -> String in
                let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escaped)'"
            }.joined(separator: " ")
            let escapedDir = systemVideosDir.replacingOccurrences(of: "'", with: "'\\''")

            let scriptSource = "do shell script \"chmod 775 '\(escapedDir)' && rm -f \(quotedPaths)\" with administrator privileges"
            if let script = NSAppleScript(source: scriptSource) {
                var errorDict: NSDictionary?
                script.executeAndReturnError(&errorDict)
                if let errorDict = errorDict {
                    let msg = (errorDict[NSAppleScript.errorMessage] as? String) ?? "未授予管理员权限，取消删除。"
                    refreshSystemDownloadedAssets()
                    return .failure(NSError(domain: "AssetDeleteError", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            }
        }

        refreshSystemDownloadedAssets()
        let mb = Double(totalBytes) / (1024.0 * 1024.0)
        let sizeText = mb >= 1024.0
            ? String(format: "%.2f GB", mb / 1024.0)
            : String(format: "%.0f MB", mb)
        return .success("已删除 \(targetURLs.count) 个航拍视频文件，释放 \(sizeText) 磁盘空间。")
    }
}
