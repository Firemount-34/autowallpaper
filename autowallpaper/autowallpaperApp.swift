//
//  autowallpaperApp.swift
//  autowallpaper
//
//  Created by wangcan on 2026/11/18.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppViewModel.shared.applyDockVisibilityAndIcon()
        }
    }
}

@main
struct autowallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel.shared

    var body: some Scene {
        // 1. 应用主界面
        WindowGroup("Aerial 日出日落自动壁纸", id: "main") {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 980, height: 680)

        // 2. 独立应用设置窗口（支持点击「设置」按钮打开）
        Window("应用设置", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 600, height: 560)
        .windowResizability(.contentSize)

        // 3. macOS 原生菜单栏 Cmd + , 偏好设置支持
        Settings {
            SettingsView(viewModel: viewModel)
        }

        // 4. 顶部状态栏（菜单栏）常驻图标 —— 根据当前应用图标动态生成
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            Image(nsImage: viewModel.menuBarAppIconImage)
        }
        .menuBarExtraStyle(.window)
    }
}
