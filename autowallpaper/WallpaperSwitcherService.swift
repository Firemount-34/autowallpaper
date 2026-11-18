//
//  WallpaperSwitcherService.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import AppKit

enum WallpaperSwitchError: LocalizedError {
    case storePlistNotFound(String)
    case invalidPlistStructure
    case encodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .storePlistNotFound(let path):
            return "未找到 macOS 壁纸配置文件：\(path)。请确保已授予文件访问权限。"
        case .invalidPlistStructure:
            return "解析 macOS 壁纸配置文件 Index.plist 失败。"
        case .encodingFailed:
            return "编码航拍壁纸 Configuration 数据失败。"
        case .writeFailed(let detail):
            return "写入壁纸配置失败：\(detail)"
        }
    }
}

/// 负责读写 macOS `Index.plist`、备份还原原始配置并重启 `WallpaperAgent`
final class WallpaperSwitcherService {
    static let shared = WallpaperSwitcherService()

    private let fm = FileManager.default

    var storePlistURL: URL {
        let home = fm.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    var backupPlistURL: URL {
        let home = fm.homeDirectoryForCurrentUser
        let appSupportDir = home.appendingPathComponent("Library/Application Support/autowallpaper")
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        return appSupportDir.appendingPathComponent("Index.plist.backup")
    }

    var hasBackup: Bool {
        fm.fileExists(atPath: backupPlistURL.path)
    }

    private init() {}

    /// 读取当前系统 Index.plist 中生效的航拍壁纸 assetID
    func readCurrentSystemAssetID() -> String? {
        guard fm.fileExists(atPath: storePlistURL.path),
              let data = try? Data(contentsOf: storePlistURL),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return extractAssetIDRecursively(from: root)
    }

    private func extractAssetIDRecursively(from dict: [String: Any]) -> String? {
        if let choices = dict["Choices"] as? [[String: Any]],
           let first = choices.first,
           let provider = first["Provider"] as? String,
           provider == "com.apple.wallpaper.choice.aerials",
           let configData = first["Configuration"] as? Data,
           let configDict = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any],
           let assetID = configDict["assetID"] as? String,
           !assetID.isEmpty {
            return assetID
        }

        // 优先从 AllSpacesAndDisplays -> Desktop 查找
        if let allSpaces = dict["AllSpacesAndDisplays"] as? [String: Any],
           let desktop = allSpaces["Desktop"] as? [String: Any],
           let aid = extractAssetIDRecursively(from: desktop) {
            return aid
        }

        for (_, value) in dict {
            if let subDict = value as? [String: Any],
               let found = extractAssetIDRecursively(from: subDict) {
                return found
            }
        }
        return nil
    }

    /// 首次接管前备份原始 Index.plist
    func createBackupIfNeeded() {
        guard !hasBackup, fm.fileExists(atPath: storePlistURL.path) else { return }
        try? fm.copyItem(at: storePlistURL, to: backupPlistURL)
    }

    /// 恢复备份的原始壁纸配置并重启 WallpaperAgent
    @discardableResult
    func restoreBackup() throws -> Bool {
        guard hasBackup else { return false }
        if fm.fileExists(atPath: storePlistURL.path) {
            try fm.removeItem(at: storePlistURL)
        }
        try fm.copyItem(at: backupPlistURL, to: storePlistURL)
        try? fm.removeItem(at: backupPlistURL)
        restartWallpaperAgent()
        return true
    }

    /// 应用指定的航拍壁纸 assetID 到 macOS 桌面（及可选屏保）
    func applyAerialWallpaper(assetID: String, syncScreenSaver: Bool = true) throws {
        guard fm.fileExists(atPath: storePlistURL.path) else {
            throw WallpaperSwitchError.storePlistNotFound(storePlistURL.path)
        }

        createBackupIfNeeded()

        let rawData: Data
        do {
            rawData = try Data(contentsOf: storePlistURL)
        } catch {
            throw WallpaperSwitchError.writeFailed("无法读取 \(storePlistURL.path)：\(error.localizedDescription)")
        }

        guard var rootDict = try PropertyListSerialization.propertyList(
            from: rawData,
            options: [.mutableContainersAndLeaves],
            format: nil
        ) as? [String: Any] else {
            throw WallpaperSwitchError.invalidPlistStructure
        }

        let configPayload: [String: Any] = ["assetID": assetID]
        guard let configData = try? PropertyListSerialization.data(
            fromPropertyList: configPayload,
            format: .binary,
            options: 0
        ) else {
            throw WallpaperSwitchError.encodingFailed
        }

        let aerialChoice: [String: Any] = [
            "Configuration": configData,
            "Files": [] as [Any],
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]

        let now = Date()
        var updatedCount = 0

        func updateContainer(_ container: inout [String: Any]) {
            if var desktop = container["Desktop"] as? [String: Any] {
                updateTargetNode(&desktop, choice: aerialChoice, date: now)
                container["Desktop"] = desktop
                updatedCount += 1
            }
            if syncScreenSaver, var idle = container["Idle"] as? [String: Any] {
                updateTargetNode(&idle, choice: aerialChoice, date: now)
                container["Idle"] = idle
                updatedCount += 1
            }
        }

        func walkAndUpdate(_ node: inout [String: Any]) {
            updateContainer(&node)
            for key in Array(node.keys) {
                guard key != "Desktop" && key != "Idle" else { continue }
                if var child = node[key] as? [String: Any] {
                    walkAndUpdate(&child)
                    node[key] = child
                }
            }
        }

        walkAndUpdate(&rootDict)

        // 如果没有任何现存节点被更新，显式构建 AllSpacesAndDisplays 与 SystemDefault
        if updatedCount == 0 {
            let defaultNode = makeTargetNode(choice: aerialChoice, date: now)
            var scope: [String: Any] = [
                "Desktop": defaultNode,
                "Type": syncScreenSaver ? "linked" : "individual"
            ]
            if syncScreenSaver {
                scope["Idle"] = defaultNode
            }
            rootDict["AllSpacesAndDisplays"] = scope
            rootDict["SystemDefault"] = scope
        }

        do {
            let outputData = try PropertyListSerialization.data(
                fromPropertyList: rootDict,
                format: .binary,
                options: 0
            )
            try outputData.write(to: storePlistURL, options: .atomic)
        } catch {
            throw WallpaperSwitchError.writeFailed(error.localizedDescription)
        }

        restartWallpaperAgent()
    }

    private func updateTargetNode(_ target: inout [String: Any], choice: [String: Any], date: Date) {
        var content = (target["Content"] as? [String: Any]) ?? [:]
        content["Choices"] = [choice]
        if content["Shuffle"] == nil {
            content["Shuffle"] = "$null"
        }
        target["Content"] = content
        target["LastSet"] = date
        target["LastUse"] = date
    }

    private func makeTargetNode(choice: [String: Any], date: Date) -> [String: Any] {
        return [
            "Content": [
                "Choices": [choice],
                "EncodedOptionValues": "$null",
                "Shuffle": "$null"
            ],
            "LastSet": date,
            "LastUse": date
        ]
    }

    /// 重启 WallpaperAgent 进程使新配置立即生效
    func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
        process.waitUntilExit()
    }
}
