import Foundation
import SwiftUI

enum MedalTier: Int, CaseIterable {
    case bronze, silver, gold, platinum

    var title: String {
        switch self {
        case .bronze: return "铜"
        case .silver: return "银"
        case .gold: return "金"
        case .platinum: return "铂金"
        }
    }

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.76, green: 0.48, blue: 0.28)
        case .silver: return Color(red: 0.65, green: 0.70, blue: 0.76)
        case .gold: return Color(red: 0.90, green: 0.70, blue: 0.16)
        case .platinum: return Color(red: 0.45, green: 0.76, blue: 0.95)
        }
    }
}

struct MilestoneMedal: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tier: MedalTier
    let current: Double
    let target: Double

    var isUnlocked: Bool { current >= target }
    var progress: Double { min(1.0, max(0.0, current / max(target, 1))) }
}

struct VirtualRoute: Identifiable {
    let id: String
    let name: String
    let totalKm: Double
    let stops: [String]
}

struct TravelerPersona {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
}

enum MilestonesEngine {
    static let virtualRoutes: [VirtualRoute] = [
        VirtualRoute(id: "canal", name: "京杭大运河", totalKm: 1794, stops: ["杭州", "苏州", "扬州", "济宁", "天津", "北京"]),
        VirtualRoute(id: "route66", name: "美国 66 号公路", totalKm: 3940, stops: ["芝加哥", "圣路易斯", "阿马里洛", "圣塔菲", "洛杉矶"]),
        VirtualRoute(id: "g318", name: "318 国道", totalKm: 5476, stops: ["上海", "武汉", "成都", "理塘", "拉萨", "樟木"]),
        VirtualRoute(id: "silkroad", name: "丝绸之路", totalKm: 6400, stops: ["西安", "敦煌", "喀什", "撒马尔罕", "伊斯坦布尔"])
    ]

    static func computeMedals(chunks: [TrackChunk], stays: [Stay], recordedDays: Int) -> [MilestoneMedal] {
        let totalKm = chunks.reduce(0.0) { $0 + $1.distance } / 1000.0
        let countries = Double(Set(stays.compactMap(\.country)).count)
        let cities = Double(Set(stays.compactMap(\.city)).count)
        let days = Double(recordedDays)
        let stayCount = Double(stays.count)

        return [
            // Distance (6)
            MilestoneMedal(id: "d1", title: "迈出第一步", subtitle: "累计 10 km", symbol: "figure.walk", tier: .bronze, current: totalKm, target: 10),
            MilestoneMedal(id: "d2", title: "百里行者", subtitle: "累计 100 km", symbol: "figure.walk", tier: .bronze, current: totalKm, target: 100),
            MilestoneMedal(id: "d3", title: "千里之行", subtitle: "累计 1,000 km", symbol: "car.fill", tier: .silver, current: totalKm, target: 1_000),
            MilestoneMedal(id: "d4", title: "万里长征", subtitle: "累计 5,000 km", symbol: "car.fill", tier: .gold, current: totalKm, target: 5_000),
            MilestoneMedal(id: "d5", title: "赤道半圈", subtitle: "累计 20,000 km", symbol: "airplane", tier: .gold, current: totalKm, target: 20_000),
            MilestoneMedal(id: "d6", title: "环绕地球", subtitle: "累计 40,075 km", symbol: "globe.asia.australia.fill", tier: .platinum, current: totalKm, target: 40_075),

            // Countries (5)
            MilestoneMedal(id: "c1", title: "初探世界", subtitle: "1 个国家/地区", symbol: "flag.fill", tier: .bronze, current: countries, target: 1),
            MilestoneMedal(id: "c2", title: "跨出国门", subtitle: "3 个国家/地区", symbol: "airplane.departure", tier: .bronze, current: countries, target: 3),
            MilestoneMedal(id: "c3", title: "行遍十国", subtitle: "10 个国家/地区", symbol: "globe", tier: .silver, current: countries, target: 10),
            MilestoneMedal(id: "c4", title: "环球旅人", subtitle: "25 个国家/地区", symbol: "globe.americas.fill", tier: .gold, current: countries, target: 25),
            MilestoneMedal(id: "c5", title: "世界公民", subtitle: "50 个国家/地区", symbol: "sparkles", tier: .platinum, current: countries, target: 50),

            // Cities (5)
            MilestoneMedal(id: "ct1", title: "城市漫游", subtitle: "5 座城市", symbol: "building.2.fill", tier: .bronze, current: cities, target: 5),
            MilestoneMedal(id: "ct2", title: "城际穿梭", subtitle: "15 座城市", symbol: "building.2.fill", tier: .silver, current: cities, target: 15),
            MilestoneMedal(id: "ct3", title: "城市收藏家", subtitle: "30 座城市", symbol: "map.fill", tier: .silver, current: cities, target: 30),
            MilestoneMedal(id: "ct4", title: "百城之约", subtitle: "60 座城市", symbol: "star.fill", tier: .gold, current: cities, target: 60),
            MilestoneMedal(id: "ct5", title: "百城大满贯", subtitle: "100 座城市", symbol: "crown.fill", tier: .platinum, current: cities, target: 100),

            // Days (4)
            MilestoneMedal(id: "day1", title: "一周坚持", subtitle: "记录 7 天", symbol: "calendar", tier: .bronze, current: days, target: 7),
            MilestoneMedal(id: "day2", title: "满月足迹", subtitle: "记录 30 天", symbol: "calendar", tier: .silver, current: days, target: 30),
            MilestoneMedal(id: "day3", title: "四季同行", subtitle: "记录 180 天", symbol: "sun.max.fill", tier: .gold, current: days, target: 180),
            MilestoneMedal(id: "day4", title: "全年无休", subtitle: "记录 365 天", symbol: "flame.fill", tier: .platinum, current: days, target: 365),

            // Stays (3)
            MilestoneMedal(id: "s1", title: "驻足时光", subtitle: "50 次停留", symbol: "mappin.circle.fill", tier: .bronze, current: stayCount, target: 50),
            MilestoneMedal(id: "s2", title: "足迹遍布", subtitle: "500 次停留", symbol: "mappin.and.ellipse", tier: .silver, current: stayCount, target: 500),
            MilestoneMedal(id: "s3", title: "时光档案馆", subtitle: "2,000 次停留", symbol: "books.vertical.fill", tier: .platinum, current: stayCount, target: 2000),
        ]
    }

    static func persona(chunks: [TrackChunk], stays: [Stay]) -> TravelerPersona {
        let cities = Set(stays.compactMap(\.city)).count
        let walkKm = chunks.filter { $0.mode == .walking || $0.mode == .running }.reduce(0.0) { $0 + $1.distance } / 1000
        let totalKm = max(1, chunks.reduce(0.0) { $0 + $1.distance } / 1000)
        let nightStays = stays.filter {
            let h = Calendar.current.component(.hour, from: $0.arrival)
            return h >= 21 || h <= 3
        }.count

        if cities >= 15 {
            return TravelerPersona(title: "城市收藏家", subtitle: "你已点亮 \(cities) 座城市，地图正在一点点展开", symbol: "building.2.crop.circle.fill", color: .orange)
        } else if walkKm / totalKm > 0.35 && walkKm > 20 {
            return TravelerPersona(title: "双脚丈量者", subtitle: "超过三成的里程由步行完成，喜欢慢慢看世界", symbol: "figure.walk.circle.fill", color: .green)
        } else if stays.count > 10 && Double(nightStays) / Double(stays.count) > 0.25 {
            return TravelerPersona(title: "夜行的散步者", subtitle: "夜晚的街头总有你的足迹与故事", symbol: "moon.stars.circle.fill", color: .indigo)
        } else {
            return TravelerPersona(title: "好奇的探索者", subtitle: "每一次出发，都在为自己的地图添上一笔", symbol: "safari.fill", color: .blue)
        }
    }
}
