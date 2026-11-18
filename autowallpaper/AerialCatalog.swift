//
//  AerialCatalog.swift
//  autowallpaper
//
//  Created by Antigravity on 2026/11/18.
//

import Foundation
import AppKit
import ImageIO

/// 解析 macOS 原生航拍目录 entries.json 与本地化名称，构建航拍地点切换组
final class AerialCatalog {
    static let shared = AerialCatalog()

    private let customerDir = "/Library/Application Support/com.apple.idleassetsd/Customer"
    private let entriesPath = "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"

    /// 内存缩略图缓存（限制数量与内存成本，避免重复磁盘读取与大图解码）
    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024 // 16 MB 上限
        return cache
    }()

    private(set) var assetsByID: [String: AerialAsset] = [:]
    private(set) var allAssets: [AerialAsset] = []
    private(set) var locationSets: [AerialLocationSet] = []

    private init() {
        reload()
    }

    func reload() {
        let zhStrings = loadStrings(localeFolder: "zh_CN.lproj")
        let enStrings = loadStrings(localeFolder: "en.lproj")

        var loadedAssets: [AerialAsset] = []
        var dynamicSubcategories: [(id: String, zhName: String, enName: String, catName: String)] = []

        if let data = try? Data(contentsOf: URL(fileURLWithPath: entriesPath)),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            if let categories = root["categories"] as? [[String: Any]] {
                for cat in categories {
                    let catKey = cat["localizedNameKey"] as? String ?? ""
                    let catZh = zhStrings[catKey] ?? enStrings[catKey] ?? "航拍"
                    if let subcats = cat["subcategories"] as? [[String: Any]] {
                        for sub in subcats {
                            if let subID = sub["id"] as? String {
                                let subKey = sub["localizedNameKey"] as? String ?? ""
                                let subZh = zhStrings[subKey] ?? subKey
                                let subEn = enStrings[subKey] ?? subKey
                                dynamicSubcategories.append((id: subID, zhName: subZh, enName: subEn, catName: catZh))
                            }
                        }
                    }
                }
            }

            if let rawAssets = root["assets"] as? [[String: Any]] {
                for item in rawAssets {
                    guard let id = item["id"] as? String else { continue }
                    let shotID = item["shotID"] as? String ?? id
                    let nameKey = item["localizedNameKey"] as? String ?? ""
                    let fallbackLabel = item["accessibilityLabel"] as? String ?? shotID
                    let zhName = zhStrings[nameKey] ?? fallbackLabel
                    let enName = enStrings[nameKey] ?? fallbackLabel
                    let subcats = item["subcategories"] as? [String] ?? []
                    let cats = item["categories"] as? [String] ?? []
                    let videoURL = item["url-4K-SDR-240FPS"] as? String
                    let previewURL = item["previewImage"] as? String

                    let asset = AerialAsset(
                        id: id,
                        shotID: shotID,
                        localizedNameKey: nameKey,
                        zhName: zhName,
                        enName: enName,
                        subcategories: subcats,
                        categories: cats,
                        videoURL: videoURL,
                        previewImageURL: previewURL
                    )
                    loadedAssets.append(asset)
                }
            }
        }

        if loadedAssets.isEmpty {
            loadedAssets = Self.fallbackAssets
        }

        self.allAssets = loadedAssets
        self.assetsByID = Dictionary(uniqueKeysWithValues: loadedAssets.map { ($0.id, $0) })

        var sets = Self.curatedLocationSets(assetsByID: self.assetsByID)

        // 自动检测系统中新增的包含日夜时段的地点（例如 macOS Tahoe 太浩湖等）
        let knownSubcategoryIDs = Set(sets.compactMap { $0.subcategoryID })
        for sub in dynamicSubcategories where !knownSubcategoryIDs.contains(sub.id) {
            let matching = loadedAssets.filter { $0.subcategories.contains(sub.id) }
            if matching.count >= 3, let autoSet = Self.buildAutoLocationSet(sub: sub, assets: matching) {
                sets.insert(autoSet, at: 0)
            }
        }

        self.locationSets = sets
    }

    private func loadStrings(localeFolder: String) -> [String: String] {
        let path = "\(customerDir)/TVIdleScreenStrings.bundle/\(localeFolder)/Localizable.nocache.strings"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            return [:]
        }
        return dict
    }

    /// 检查某个视频资源是否已经下载到 macOS 系统原生航拍目录
    func isAssetDownloaded(_ assetID: String) -> Bool {
        return localVideoURL(for: assetID) != nil
    }

    /// 返回系统 `/Library/Application Support/com.apple.idleassetsd/Customer/` 下该资源所有已存在的 .mov 路径
    func localVideoFiles(for assetID: String) -> [URL] {
        let fm = FileManager.default
        let candidatePaths = [
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/\(assetID).mov",
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KHDR/\(assetID).mov",
            "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR/\(assetID).mov",
            "/Library/Application Support/com.apple.idleassetsd/Customer/2KSDR/\(assetID).mov",
            "/Library/Application Support/com.apple.idleassetsd/Customer/2KHDR/\(assetID).mov",
            "/Library/Application Support/com.apple.idleassetsd/Customer/2KAVC/\(assetID).mov"
        ]
        var urls: [URL] = []
        for path in candidatePaths where fm.fileExists(atPath: path) {
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }

    /// 返回系统 `/Library/Application Support/com.apple.idleassetsd/Customer/` 下实际已就绪的 .mov 路径
    /// 注意：macOS WallpaperAgent 与 idleassetsd 仅识别该系统目录下的视频文件
    func localVideoURL(for assetID: String) -> URL? {
        let fm = FileManager.default
        for url in localVideoFiles(for: assetID) {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64,
               size > 50_000_000 { // 原生 4K 航拍视频均大于 100MB，大于 50MB 视为完整就绪
                return url
            }
        }
        return nil
    }

    /// 获取本地已下载视频的文件体积（字节）
    func localVideoSizeBytes(for assetID: String) -> UInt64 {
        let fm = FileManager.default
        var total: UInt64 = 0
        for url in localVideoFiles(for: assetID) {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }

    /// 获取本地已下载视频的可读体积文本（例如 "459 MB"）
    func formattedVideoSize(for assetID: String) -> String? {
        let bytes = localVideoSizeBytes(for: assetID)
        guard bytes > 0 else { return nil }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }

    /// 使用 ImageIO 硬件降采样并缓存本地预览缩略图，大幅降低内存占用与主线程 I/O
    func previewImage(for assetID: String, maxPixelSize: Int = 420) -> NSImage? {
        let cacheKey = "\(assetID)-\(maxPixelSize)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        guard let asset = assetsByID[assetID] else { return nil }
        let path = asset.localPreviewPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
        let cost = cgImg.bytesPerRow * cgImg.height
        thumbnailCache.setObject(nsImg, forKey: cacheKey, cost: cost)
        return nsImg
    }

    func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    // MARK: - 自动推断新增地点组（例如 Tahoe 等）

    private static func buildAutoLocationSet(
        sub: (id: String, zhName: String, enName: String, catName: String),
        assets: [AerialAsset]
    ) -> AerialLocationSet? {
        func findAsset(keywords: [String]) -> AerialAsset? {
            for kw in keywords {
                if let match = assets.first(where: {
                    $0.enName.localizedCaseInsensitiveContains(kw) || $0.zhName.localizedCaseInsensitiveContains(kw)
                }) {
                    return match
                }
            }
            return nil
        }

        let sunriseAsset = findAsset(keywords: ["Sunrise", "Dawn", "Horizon", "日出", "地平线", "破晓"])
        let morningAsset = findAsset(keywords: ["Morning", "Fog", "Clouds Light", "清晨", "朝霞", "雾"])
        let sunsetAsset = findAsset(keywords: ["Sunset", "Dusk", "日落", "夕阳"])
        let nightAsset = findAsset(keywords: ["Night", "Evening", "Dark", "夜晚", "夜色", "黄昏"])

        // 至少包含清晨/日出/日落/夜晚中的两个时段才作为动态时间地点
        let matchedTimeCount = [sunriseAsset, morningAsset, sunsetAsset, nightAsset].compactMap { $0 }.count
        guard matchedTimeCount >= 2 else { return nil }

        let dayAsset = assets.first(where: {
            $0.id != sunriseAsset?.id && $0.id != morningAsset?.id && $0.id != sunsetAsset?.id && $0.id != nightAsset?.id
        }) ?? assets[0]

        let resolvedSunrise = sunriseAsset ?? morningAsset ?? dayAsset
        let resolvedMorning = morningAsset ?? sunriseAsset ?? dayAsset
        let resolvedSunset = sunsetAsset ?? nightAsset ?? dayAsset
        let resolvedNight = nightAsset ?? sunsetAsset ?? dayAsset

        return AerialLocationSet(
            id: "auto-\(sub.id)",
            subcategoryID: sub.id,
            name: sub.zhName,
            englishName: sub.enName,
            categoryName: sub.catName,
            summary: "包含 \(assets.count) 个航拍镜头，支持按日出日落全天候切换",
            defaultPeriodAssets: [
                .sunrise: resolvedSunrise.id,
                .morning: resolvedMorning.id,
                .day: dayAsset.id,
                .sunset: resolvedSunset.id,
                .night: resolvedNight.id
            ],
            availableAssetIDs: assets.map { $0.id }
        )
    }

    // MARK: - 精选全时段航拍地点组

    private static func curatedLocationSets(assetsByID: [String: AerialAsset]) -> [AerialLocationSet] {
        return [
            AerialLocationSet(
                id: "sonoma",
                subcategoryID: "3CC63110-FF0E-4443-9A2D-63CD0795954E",
                name: "索诺马 (Sonoma)",
                englishName: "Sonoma",
                categoryName: "自然景观",
                summary: "从地平线破晓、云海清晨、俯瞰山谷到河流夕照与静谧黄昏的完整昼夜航拍",
                defaultPeriodAssets: [
                    .sunrise: "FE876489-CBD5-479B-A8F0-1B67F0741CEA", // 索诺马地平线
                    .morning: "097CA871-A1C2-40F7-97F0-EFAABF555BBC", // 索诺马的云层
                    .day: "C3C48B18-E4AE-4A62-877D-0B0D74CDC9E0",     // 俯瞰索诺马
                    .sunset: "12718607-0FE6-4B8C-B571-A320CDD67897",  // 索诺马河流
                    .night: "94DAB450-A650-4DFC-99B2-A0F0D8AD6649"    // 索诺马黄昏
                ],
                availableAssetIDs: [
                    "FE876489-CBD5-479B-A8F0-1B67F0741CEA",
                    "097CA871-A1C2-40F7-97F0-EFAABF555BBC",
                    "C3C48B18-E4AE-4A62-877D-0B0D74CDC9E0",
                    "12718607-0FE6-4B8C-B571-A320CDD67897",
                    "94DAB450-A650-4DFC-99B2-A0F0D8AD6649"
                ]
            ),
            AerialLocationSet(
                id: "sequoia",
                subcategoryID: "78D1B993-DA5B-4CA6-90F0-865DA7F9091D",
                name: "红杉国家公园 (Sequoia)",
                englishName: "Sequoia",
                categoryName: "自然景观",
                summary: "macOS Sequoia 经典航拍，涵盖红杉林日出、晨曦穿过林间与静谧星空夜晚",
                defaultPeriodAssets: [
                    .sunrise: "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7", // 红杉国家公园日出
                    .morning: "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B", // 红杉国家公园清晨
                    .day: "AA5E82B9-289A-480C-A14B-242989107275",     // 俯瞰红杉林
                    .sunset: "8A57476A-E177-4AAD-B317-643F681584E1",  // 俄勒冈州日落 (红杉林海岸)
                    .night: "97C3047F-ED39-472C-9778-CABF25D8682D"    // 红杉国家公园夜晚
                ],
                availableAssetIDs: [
                    "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7",
                    "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B",
                    "97C3047F-ED39-472C-9778-CABF25D8682D",
                    "AA5E82B9-289A-480C-A14B-242989107275",
                    "97447D85-960C-4B2A-A101-048284D95853",
                    "8A57476A-E177-4AAD-B317-643F681584E1"
                ]
            ),
            AerialLocationSet(
                id: "san-francisco",
                subcategoryID: "20A0F234-6E93-4C96-8A9E-0E48ECDC8303",
                name: "旧金山与金门大桥 (Golden Gate)",
                englishName: "San Francisco",
                categoryName: "城市景观",
                summary: "晨雾中的金门大桥、白昼湾区天际线、落日余晖与璀璨旧金山夜景",
                defaultPeriodAssets: [
                    .sunrise: "EE533FBD-90AE-419A-AD13-D7A60E2015D6", // 雾中旧金山
                    .morning: "72B4390D-DF1D-4D51-B179-229BBAEFFF2C", // 旧金山金门大桥
                    .day: "85CE77BF-3413-4A7B-9B0F-732E96229A73",     // 旧金山城市轮廓线
                    .sunset: "29BDF297-EB43-403A-8719-A78DA11A2948",  // 旧金山黄昏
                    .night: "3E94AE98-EAF2-4B09-96E3-452F46BC114E"    // 旧金山夜色
                ],
                availableAssetIDs: [
                    "EE533FBD-90AE-419A-AD13-D7A60E2015D6",
                    "72B4390D-DF1D-4D51-B179-229BBAEFFF2C",
                    "85CE77BF-3413-4A7B-9B0F-732E96229A73",
                    "DE851E6D-C2BE-4D9F-AB54-0F9CE994DC51",
                    "4AD99907-9E76-408D-A7FC-8429FF014201",
                    "29BDF297-EB43-403A-8719-A78DA11A2948",
                    "3E94AE98-EAF2-4B09-96E3-452F46BC114E"
                ]
            ),
            AerialLocationSet(
                id: "china",
                subcategoryID: "23850E78-D69D-48EB-9F5C-DC2319D238D5",
                name: "中国·长城与山河 (China)",
                englishName: "China",
                categoryName: "自然景观",
                summary: "晨光中的群山剪影、梯田稻浪、日光万里长城、暮色长城与神州夜色",
                defaultPeriodAssets: [
                    .sunrise: "044AD56C-A107-41B2-90CC-E60CCACFBCF5", // 中国剪影
                    .morning: "9CCB8297-E9F5-4699-AE1F-890CFBD5E29C", // 中国稻田
                    .day: "F0236EC5-EE72-4058-A6CE-1F7D2E8253BF",     // 日光下的中国长城
                    .sunset: "22162A9B-DB90-4517-867C-C676BC3E8E95",  // 中国长城 (日落暮色)
                    .night: "6324F6EB-E0F1-468F-AC2E-A983EBDDD53B"    // 中国夜色
                ],
                availableAssetIDs: [
                    "044AD56C-A107-41B2-90CC-E60CCACFBCF5",
                    "9CCB8297-E9F5-4699-AE1F-890CFBD5E29C",
                    "F0236EC5-EE72-4058-A6CE-1F7D2E8253BF",
                    "22162A9B-DB90-4517-867C-C676BC3E8E95",
                    "B876B645-3955-420E-99DF-60139E451CF3",
                    "D5E76230-81A3-4F65-A1BA-51B8CADED625",
                    "6324F6EB-E0F1-468F-AC2E-A983EBDDD53B"
                ]
            ),
            AerialLocationSet(
                id: "yosemite",
                subcategoryID: "E4B726A1-7DD5-4E5A-A430-C99FE47E7A4F",
                name: "优胜美地 (Yosemite)",
                englishName: "Yosemite",
                categoryName: "自然景观",
                summary: "优胜美地地平线日出、云雾山谷、巍峨花岗岩峰峦与暮色轮廓线",
                defaultPeriodAssets: [
                    .sunrise: "E540DEE6-4C40-42C8-9CCC-D4CB0FAD7D7B", // 优胜美地地平线
                    .morning: "E487C6EF-B3FB-427B-A2BE-8CBA60F902F0", // 优胜美地的云层
                    .day: "4109D42A-D717-46A7-A9A2-FE53A82B25C0",     // 优胜美地山谷
                    .sunset: "E5799A24-1949-4E66-A17B-B5EB05F28C5D",  // 优胜美地轮廓线
                    .night: "8D04D70F-738B-441D-8D43-AF46B2BF8062"    // 优胜美地的积雪
                ],
                availableAssetIDs: [
                    "E540DEE6-4C40-42C8-9CCC-D4CB0FAD7D7B",
                    "E487C6EF-B3FB-427B-A2BE-8CBA60F902F0",
                    "4109D42A-D717-46A7-A9A2-FE53A82B25C0",
                    "81CA5ACD-E682-4D8B-A948-0F147EB6ED4F",
                    "DAD82DCE-F3AE-4AEC-8A79-1694D412FC0A",
                    "E5799A24-1949-4E66-A17B-B5EB05F28C5D",
                    "8D04D70F-738B-441D-8D43-AF46B2BF8062"
                ]
            ),
            AerialLocationSet(
                id: "grand-canyon",
                subcategoryID: "125E88CC-6233-4693-8293-1B8C91AFEC89",
                name: "科罗拉多大峡谷 (Grand Canyon)",
                englishName: "Grand Canyon",
                categoryName: "自然景观",
                summary: "河谷晨光、壮阔岩层俯瞰、大峡谷金色日落与静谧暮色",
                defaultPeriodAssets: [
                    .sunrise: "8002C4C8-C611-4894-A068-3D3A3C03472A", // 大峡谷河谷
                    .morning: "AE0115AE-C53B-4DB9-B12F-CA4B7B630CC9", // 大峡谷沉积物
                    .day: "DD266E1F-5DF2-4CDB-A2EB-26CE35664657",     // 俯瞰大峡谷
                    .sunset: "F9F918CD-E15F-4F01-A326-84A44650C5C9",  // 大峡谷日落
                    .night: "E334A6D2-7145-47C8-9B00-C20DED08B2D5"    // 大峡谷黄昏
                ],
                availableAssetIDs: [
                    "8002C4C8-C611-4894-A068-3D3A3C03472A",
                    "AE0115AE-C53B-4DB9-B12F-CA4B7B630CC9",
                    "DD266E1F-5DF2-4CDB-A2EB-26CE35664657",
                    "F9F918CD-E15F-4F01-A326-84A44650C5C9",
                    "E334A6D2-7145-47C8-9B00-C20DED08B2D5"
                ]
            ),
            AerialLocationSet(
                id: "monument-valley",
                subcategoryID: "48103A98-1EDA-49A1-A860-D199CB9210A8",
                name: "纪念碑谷与犹他 (Monument Valley)",
                englishName: "Monument Valley",
                categoryName: "自然景观",
                summary: "犹他州红岩孤峰破晓、大教堂峡谷、纪念碑谷白昼、鲍威尔湖日落与黄昏",
                defaultPeriodAssets: [
                    .sunrise: "1A17ED86-9E0D-4DF2-8CF3-5AB5DB67A348", // Factory Butte
                    .morning: "7530C83C-8F7B-42C6-BB71-5FA2ED070BEC", // 大教堂峡谷
                    .day: "100858D2-FE01-4B70-8E2D-3FCF20AFE6B5",     // 纪念碑谷
                    .sunset: "D759828B-4BAB-456B-AD75-225BA238F925",  // 鲍威尔湖
                    .night: "AB7FC3C3-8853-45CD-AB6E-89F0985C2922"    // 犹他州黄昏
                ],
                availableAssetIDs: [
                    "1A17ED86-9E0D-4DF2-8CF3-5AB5DB67A348",
                    "7530C83C-8F7B-42C6-BB71-5FA2ED070BEC",
                    "100858D2-FE01-4B70-8E2D-3FCF20AFE6B5",
                    "D759828B-4BAB-456B-AD75-225BA238F925",
                    "AB7FC3C3-8853-45CD-AB6E-89F0985C2922",
                    "47BC0599-72E7-43C4-8BE1-CBCE2432E2A5",
                    "A168628E-11EE-4456-AD66-E7E3E47D1B21"
                ]
            ),
            AerialLocationSet(
                id: "new-york",
                subcategoryID: "8FB0A685-4360-4F17-8245-1D2E230C9683",
                name: "纽约 (New York)",
                englishName: "New York",
                categoryName: "城市景观",
                summary: "曼哈顿高空晨景、中城区白昼、天际线落日与璀璨不夜城",
                defaultPeriodAssets: [
                    .sunrise: "3BA0CFC7-E460-4B59-A817-B97F9EBB9B89", // 俯瞰纽约
                    .morning: "840FE8E4-D952-4680-B1A7-AC5BACA2C1F8", // 纽约中城区
                    .day: "640DFB00-FBB9-45DA-9444-9F663859F4BC",     // 纽约城市轮廓线
                    .sunset: "44166C39-8566-4ECA-BD16-43159429B52F",  // 纽约夜晚
                    .night: "B1B5DDC5-73C8-4920-8133-BACCE38A08DE"    // 纽约夜色
                ],
                availableAssetIDs: [
                    "3BA0CFC7-E460-4B59-A817-B97F9EBB9B89",
                    "840FE8E4-D952-4680-B1A7-AC5BACA2C1F8",
                    "640DFB00-FBB9-45DA-9444-9F663859F4BC",
                    "44166C39-8566-4ECA-BD16-43159429B52F",
                    "B1B5DDC5-73C8-4920-8133-BACCE38A08DE"
                ]
            ),
            AerialLocationSet(
                id: "los-angeles",
                subcategoryID: "29A85ABC-196E-40E5-BFCC-498CFF39E956",
                name: "洛杉矶 (Los Angeles)",
                englishName: "Los Angeles",
                categoryName: "城市景观",
                summary: "圣莫尼卡海岸清晨、好莱坞山丘、加州黄金日落与天使之城夜景",
                defaultPeriodAssets: [
                    .sunrise: "92E48DE9-13A1-4172-B560-29B4668A87EE", // 洛杉矶海滩
                    .morning: "EC67726A-8212-4C5E-83CF-8412932740D2", // 洛杉矶山丘
                    .day: "35693AEA-F8C4-4A80-B77D-C94B20A68956",     // 洛杉矶立交桥
                    .sunset: "89B1643B-06DD-4DEC-B1B0-774493B0F7B7",  // 洛杉矶日落
                    .night: "F5804DD6-5963-40DA-9FA0-39C0C6E6DEF9"    // 洛杉矶夜色
                ],
                availableAssetIDs: [
                    "92E48DE9-13A1-4172-B560-29B4668A87EE",
                    "EC67726A-8212-4C5E-83CF-8412932740D2",
                    "35693AEA-F8C4-4A80-B77D-C94B20A68956",
                    "CE279831-1CA7-4A83-A97B-FF1E20234396",
                    "89B1643B-06DD-4DEC-B1B0-774493B0F7B7",
                    "F5804DD6-5963-40DA-9FA0-39C0C6E6DEF9"
                ]
            ),
            AerialLocationSet(
                id: "hong-kong",
                subcategoryID: "BC0F2DA2-7B11-45A6-8ECC-26820868149A",
                name: "香港 (Hong Kong)",
                englishName: "Hong Kong",
                categoryName: "城市景观",
                summary: "维多利亚港清晨、香港天际线、山顶地平线日落与璀璨香江夜色",
                defaultPeriodAssets: [
                    .sunrise: "FE8E1F9D-59BA-4207-B626-28E34D810D0A", // 香港港湾
                    .morning: "024891DE-B7F6-4187-BFE0-E6D237702EF0", // 香港城市轮廓线
                    .day: "024891DE-B7F6-4187-BFE0-E6D237702EF0",     // 香港城市轮廓线
                    .sunset: "C8559883-6F3E-4AF2-8960-903710CD47B7",  // 香港地平线
                    .night: "E99FA658-A59A-4A2D-9F3B-58E7BDC71A9A"    // 香港夜色
                ],
                availableAssetIDs: [
                    "FE8E1F9D-59BA-4207-B626-28E34D810D0A",
                    "024891DE-B7F6-4187-BFE0-E6D237702EF0",
                    "C8559883-6F3E-4AF2-8960-903710CD47B7",
                    "E99FA658-A59A-4A2D-9F3B-58E7BDC71A9A"
                ]
            ),
            AerialLocationSet(
                id: "dubai",
                subcategoryID: "74834396-888E-4D30-BE33-88BCF6BC30FE",
                name: "迪拜 (Dubai)",
                englishName: "Dubai",
                categoryName: "城市景观",
                summary: "迪拜湾晨曦、码头白昼、哈利法塔天际线日落与大漠明珠夜景",
                defaultPeriodAssets: [
                    .sunrise: "3FFA2A97-7D28-49EA-AA39-5BC9051B2745", // 迪拜湾
                    .morning: "E991AC0C-F272-44D8-88F3-05F44EDFE3AE", // 迪拜湾码头
                    .day: "876D51F4-3D78-4221-8AD2-F9E78C0FD9B9",     // 俯瞰迪拜
                    .sunset: "00BA71CD-2C54-415A-A68A-8358E677D750",  // 迪拜城市轮廓线
                    .night: "9680B8EB-CE2A-4395-AF41-402801F4D6A6"    // 迪拜夜色
                ],
                availableAssetIDs: [
                    "3FFA2A97-7D28-49EA-AA39-5BC9051B2745",
                    "E991AC0C-F272-44D8-88F3-05F44EDFE3AE",
                    "876D51F4-3D78-4221-8AD2-F9E78C0FD9B9",
                    "00BA71CD-2C54-415A-A68A-8358E677D750",
                    "9680B8EB-CE2A-4395-AF41-402801F4D6A6"
                ]
            ),
            AerialLocationSet(
                id: "london",
                subcategoryID: "6623FD45-2067-4621-B622-8B3539321CE2",
                name: "伦敦 (London)",
                englishName: "London",
                categoryName: "城市景观",
                summary: "泰晤士河晨光、伦敦桥白昼、城市天际线与华灯初上的黄昏",
                defaultPeriodAssets: [
                    .sunrise: "A5AAFF5D-8887-42BB-8AFD-867EF557ED85", // 俯瞰伦敦
                    .morning: "7F4C26C2-67C2-4C3A-8F07-8A7BF6148C97", // 伦敦泰晤士河
                    .day: "58754319-8709-4AB0-8674-B34F04E7FFE2",     // 伦敦城市轮廓线
                    .sunset: "F604AF56-EA77-4960-AEF7-82533CC1A8B3",  // 伦敦黄昏
                    .night: "F604AF56-EA77-4960-AEF7-82533CC1A8B3"    // 伦敦黄昏
                ],
                availableAssetIDs: [
                    "A5AAFF5D-8887-42BB-8AFD-867EF557ED85",
                    "7F4C26C2-67C2-4C3A-8F07-8A7BF6148C97",
                    "58754319-8709-4AB0-8674-B34F04E7FFE2",
                    "F604AF56-EA77-4960-AEF7-82533CC1A8B3"
                ]
            ),
            AerialLocationSet(
                id: "hawaii",
                subcategoryID: "9029A4DA-14F9-4A3C-9D84-76B8F617109B",
                name: "夏威夷 (Hawaii)",
                englishName: "Hawaii",
                categoryName: "自然景观",
                summary: "浅色云海破晓、翠绿山谷、太平洋壮丽海岸线与深色暮云",
                defaultPeriodAssets: [
                    .sunrise: "258A6797-CC13-4C3A-AB35-4F25CA3BF474", // 夏威夷云层（浅色）
                    .morning: "499995FA-E51A-4ACE-8DFD-BDF8AFF6C943", // 夏威夷谷
                    .day: "12E0343D-2CD9-48EA-AB57-4D680FB6D0C7",     // 夏威夷海岸线
                    .sunset: "3D729CFC-9000-48D3-A052-C5BD5B7A6842",  // 夏威夷洋
                    .night: "82BD33C9-B6D2-47E7-9C42-AA3B7758921A"    // 夏威夷云层（深色）
                ],
                availableAssetIDs: [
                    "258A6797-CC13-4C3A-AB35-4F25CA3BF474",
                    "499995FA-E51A-4ACE-8DFD-BDF8AFF6C943",
                    "12E0343D-2CD9-48EA-AB57-4D680FB6D0C7",
                    "3D729CFC-9000-48D3-A052-C5BD5B7A6842",
                    "82BD33C9-B6D2-47E7-9C42-AA3B7758921A"
                ]
            ),
            AerialLocationSet(
                id: "greenland",
                subcategoryID: "BC646863-24D5-4172-A4C0-4361F078A1E1",
                name: "格陵兰 (Greenland)",
                englishName: "Greenland",
                categoryName: "自然景观",
                summary: "极地冰川海岸晨光、壮阔冰盖白昼与北极圈暮色黄昏",
                defaultPeriodAssets: [
                    .sunrise: "2F52E34C-39D4-4AB1-9025-8F7141FAA720", // 格陵兰海岸
                    .morning: "2F52E34C-39D4-4AB1-9025-8F7141FAA720", // 格陵兰海岸
                    .day: "B8F204CE-6024-49AB-85F9-7CA2F6DCD226",     // 格陵兰大冰川
                    .sunset: "EE01F02D-1413-436C-AB05-410F224A5B7B",  // 格陵兰黄昏
                    .night: "EE01F02D-1413-436C-AB05-410F224A5B7B"    // 格陵兰黄昏
                ],
                availableAssetIDs: [
                    "2F52E34C-39D4-4AB1-9025-8F7141FAA720",
                    "B8F204CE-6024-49AB-85F9-7CA2F6DCD226",
                    "EE01F02D-1413-436C-AB05-410F224A5B7B"
                ]
            )
        ]
    }

    private static let fallbackAssets: [AerialAsset] = [
        AerialAsset(id: "FE876489-CBD5-479B-A8F0-1B67F0741CEA", shotID: "W010_C003_F01", localizedNameKey: "", zhName: "索诺马地平线", enName: "Sonoma Horizon", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "097CA871-A1C2-40F7-97F0-EFAABF555BBC", shotID: "S011_C003_F01", localizedNameKey: "", zhName: "索诺马的云层", enName: "Sonoma Clouds", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "C3C48B18-E4AE-4A62-877D-0B0D74CDC9E0", shotID: "S009_C018_F01", localizedNameKey: "", zhName: "俯瞰索诺马", enName: "Sonoma from Above", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "12718607-0FE6-4B8C-B571-A320CDD67897", shotID: "S005_C013_F01", localizedNameKey: "", zhName: "索诺马河流", enName: "Sonoma River", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "94DAB450-A650-4DFC-99B2-A0F0D8AD6649", shotID: "S013_C001_F01", localizedNameKey: "", zhName: "索诺马黄昏", enName: "Sonoma Evening", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7", shotID: "A007_C0001", localizedNameKey: "", zhName: "红杉国家公园日出", enName: "Sequoia Sunrise", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "F88CDF4A-9681-4D1F-88FE-34F1A3C6A62B", shotID: "A010_C0005", localizedNameKey: "", zhName: "红杉国家公园清晨", enName: "Sequoia Morning", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil),
        AerialAsset(id: "97C3047F-ED39-472C-9778-CABF25D8682D", shotID: "A018_C0002", localizedNameKey: "", zhName: "红杉国家公园夜晚", enName: "Sequoia Night", subcategories: [], categories: [], videoURL: nil, previewImageURL: nil)
    ]
}
