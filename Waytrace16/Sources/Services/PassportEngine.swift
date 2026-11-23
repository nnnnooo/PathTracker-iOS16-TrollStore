import Foundation
import SwiftUI
import CoreLocation

enum PassportTheme: String, CaseIterable, Identifiable {
    case burgundy, navy, forest, obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burgundy: return "酒红"
        case .navy: return "藏青"
        case .forest: return "墨绿"
        case .obsidian: return "夜黑"
        }
    }

    var coverColor: Color {
        switch self {
        case .burgundy: return Color(red: 0.42, green: 0.11, blue: 0.15)
        case .navy: return Color(red: 0.10, green: 0.17, blue: 0.30)
        case .forest: return Color(red: 0.11, green: 0.27, blue: 0.20)
        case .obsidian: return Color(red: 0.11, green: 0.11, blue: 0.13)
        }
    }

    var foilColor: Color {
        switch self {
        case .burgundy, .forest: return Color(red: 0.87, green: 0.74, blue: 0.42)
        case .navy, .obsidian: return Color(red: 0.82, green: 0.85, blue: 0.90)
        }
    }

    var paperColor: Color {
        switch self {
        case .burgundy: return Color(red: 0.98, green: 0.96, blue: 0.92)
        case .navy: return Color(red: 0.95, green: 0.96, blue: 0.98)
        case .forest: return Color(red: 0.95, green: 0.97, blue: 0.95)
        case .obsidian: return Color(red: 0.94, green: 0.94, blue: 0.95)
        }
    }
}

struct CountryStamp: Identifiable {
    let id: String
    let countryCode: String
    let countryName: String
    let nativeName: String
    let entryDate: Date
    let exitDate: Date
    let days: Int
    let portCity: String?
}

struct ProvinceSeal: Identifiable {
    let id: String
    let shortChar: String
    let fullName: String
    let keywords: [String]
    var visited: Bool
    var firstVisit: Date?
    var days: Int
}

struct CityStamp: Identifiable {
    let id: String
    let cityName: String
    let countryName: String?
    let firstVisit: Date
    let days: Int
    let visits: Int
}

struct ExtremePoint: Identifiable {
    let id: String
    let label: String   // 北至 / 南至 / 东至 / 西至 / 最高
    let placeName: String
    let detail: String
    let date: Date
}

struct SpecialStamp: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let unlocked: Bool
    let date: Date?
}

struct StampSet: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let requiredCities: [String]
    let matchedCities: [String]

    var isCompleted: Bool { matchedCities.count == requiredCities.count && !requiredCities.isEmpty }
    var progress: Double { requiredCities.isEmpty ? 0 : Double(matchedCities.count) / Double(requiredCities.count) }
}

struct PassportSummary {
    let homeCountryCode: String?
    let homeCountryName: String?
    let countryStamps: [CountryStamp]
    let provinceSeals: [ProvinceSeal]
    let cityStamps: [CityStamp]
    let extremes: [ExtremePoint]
    let specialStamps: [SpecialStamp]
    let stampSets: [StampSet]
}

enum PassportEngine {
    private static let provinceCatalog: [(char: String, name: String, keys: [String])] = [
        ("京", "北京", ["北京", "Beijing"]),
        ("津", "天津", ["天津", "Tianjin"]),
        ("沪", "上海", ["上海", "Shanghai"]),
        ("渝", "重庆", ["重庆", "Chongqing"]),
        ("冀", "河北", ["河北", "Hebei", "石家庄", "秦皇岛", "保定", "唐山", "承德", "张家口"]),
        ("晋", "山西", ["山西", "Shanxi", "太原", "大同", "平遥", "晋中", "运城"]),
        ("辽", "辽宁", ["辽宁", "Liaoning", "沈阳", "大连", "丹东", "鞍山"]),
        ("吉", "吉林", ["吉林", "Jilin", "长春", "延边", "白山"]),
        ("黑", "黑龙江", ["黑龙江", "Heilongjiang", "哈尔滨", "漠河", "齐齐哈尔", "牡丹江"]),
        ("苏", "江苏", ["江苏", "Jiangsu", "南京", "苏州", "无锡", "扬州", "常州", "徐州", "南通"]),
        ("浙", "浙江", ["浙江", "Zhejiang", "杭州", "宁波", "温州", "嘉兴", "绍兴", "舟山", "丽水", "金华", "台州", "湖州", "衢州"]),
        ("皖", "安徽", ["安徽", "Anhui", "合肥", "黄山", "芜湖", "宣城", "安庆"]),
        ("闽", "福建", ["福建", "Fujian", "福州", "厦门", "泉州", "漳州", "武夷山", "南平"]),
        ("赣", "江西", ["江西", "Jiangxi", "南昌", "景德镇", "九江", "赣州", "上饶"]),
        ("鲁", "山东", ["山东", "Shandong", "济南", "青岛", "烟台", "威海", "泰安", "曲阜", "济宁"]),
        ("豫", "河南", ["河南", "Henan", "郑州", "洛阳", "开封", "安阳", "南阳"]),
        ("鄂", "湖北", ["湖北", "Hubei", "武汉", "宜昌", "襄阳", "恩施", "十堰"]),
        ("湘", "湖南", ["湖南", "Hunan", "长沙", "张家界", "湘西", "凤凰", "岳阳", "衡阳"]),
        ("粤", "广东", ["广东", "Guangdong", "广州", "深圳", "珠海", "佛山", "东莞", "汕头", "潮州", "惠州", "中山"]),
        ("琼", "海南", ["海南", "Hainan", "海口", "三亚", "万宁", "陵水"]),
        ("川", "四川", ["四川", "Sichuan", "成都", "乐山", "九寨沟", "阿坝", "甘孜", "绵阳", "宜宾", "泸州"]),
        ("贵", "贵州", ["贵州", "Guizhou", "贵阳", "遵义", "安顺", "黔东南", "荔波"]),
        ("云", "云南", ["云南", "Yunnan", "昆明", "大理", "丽江", "香格里拉", "迪庆", "西双版纳", "腾冲", "保山"]),
        ("陕", "陕西", ["陕西", "Shaanxi", "西安", "延安", "咸阳", "宝鸡", "汉中"]),
        ("甘", "甘肃", ["甘肃", "Gansu", "兰州", "敦煌", "酒泉", "张掖", "天水", "嘉峪关"]),
        ("青", "青海", ["青海", "Qinghai", "西宁", "海西", "海南藏族", "玉树"]),
        ("台", "台湾", ["台湾", "Taiwan", "台北", "高雄", "台中", "台南", "花莲"]),
        ("蒙", "内蒙古", ["内蒙古", "Inner Mongolia", "呼和浩特", "呼伦贝尔", "包头", "鄂尔多斯", "赤峰"]),
        ("桂", "广西", ["广西", "Guangxi", "南宁", "桂林", "北海", "柳州", "崇左"]),
        ("藏", "西藏", ["西藏", "Tibet", "Xizang", "拉萨", "林芝", "日喀则", "阿里", "山南"]),
        ("宁", "宁夏", ["宁夏", "Ningxia", "银川", "中卫", "吴忠"]),
        ("新", "新疆", ["新疆", "Xinjiang", "乌鲁木齐", "喀什", "伊犁", "阿勒泰", "吐鲁番", "库尔勒"]),
        ("港", "香港", ["香港", "Hong Kong"]),
        ("澳", "澳门", ["澳门", "Macao", "Macau"])
    ]

    private static let nativeCountryNames: [String: String] = [
        "JP": "日本国",
        "KR": "대한민국",
        "CH": "SCHWEIZ · SUISSE",
        "FR": "RÉPUBLIQUE FRANÇAISE",
        "DE": "BUNDESREPUBLIK DEUTSCHLAND",
        "IT": "REPUBBLICA ITALIANA",
        "ES": "REINO DE ESPAÑA",
        "GB": "UNITED KINGDOM",
        "US": "UNITED STATES",
        "CA": "CANADA",
        "AU": "AUSTRALIA",
        "NZ": "NEW ZEALAND",
        "TH": "ประเทศไทย",
        "SG": "SINGAPORE",
        "MY": "MALAYSIA",
        "VN": "VIỆT NAM",
        "ID": "INDONESIA",
        "HK": "香港 · HONG KONG",
        "MO": "澳門 · MACAU",
        "TW": "台灣 · TAIWAN",
        "CN": "中华人民共和国"
    ]

    private static let setCatalog: [(id: String, title: String, subtitle: String, cities: [String])] = [
        ("jiangnan", "江南烟雨", "苏杭水乡经典环线", ["杭州", "苏州", "上海", "南京"]),
        ("capitals", "六大古都", "千年历史中轴线", ["北京", "西安", "南京", "洛阳", "杭州", "开封"]),
        ("yunnan", "彩云之南", "滇西北风花雪月", ["昆明", "大理", "丽江"]),
        ("silkroad", "丝绸之路", "河西走廊与西域", ["西安", "兰州", "敦煌", "乌鲁木齐"]),
        ("gba", "粤港澳大湾区", "南海之滨都市圈", ["广州", "深圳", "香港", "澳门"]),
        ("bashu", "巴蜀风情", "天府之国与山城", ["成都", "重庆"]),
        ("kansai", "关西古韵", "日本关西三都", ["大阪", "京都", "奈良"]),
        ("jjj", "京津冀", "燕赵大地", ["北京", "天津"]),
        ("dongbei", "白山黑水", "东北三省", ["哈尔滨", "长春", "沈阳"]),
        ("uswest", "美国西部", "太平洋海岸与峡谷", ["洛杉矶", "旧金山", "拉斯维加斯"])
    ]

    static func build(stays: [Stay], chunks: [TrackChunk]) -> PassportSummary {
        let tagged = stays.filter { $0.countryCode != nil || $0.city != nil }.sorted { $0.arrival < $1.arrival }

        // Determine home country by most stays
        let countryCounts = Dictionary(grouping: tagged.compactMap(\.countryCode)) { $0 }.mapValues(\.count)
        let homeCode = countryCounts.max { $0.value < $1.value }?.key
        let homeName = tagged.first { $0.countryCode == homeCode }?.country

        // 1. Country entry/exit stamps (non-home countries, merged into continuous visits)
        var countryStamps: [CountryStamp] = []
        var activeVisit: (code: String, name: String, start: Date, end: Date, port: String?)?
        for stay in tagged {
            guard let code = stay.countryCode, code != homeCode else {
                if let v = activeVisit {
                    countryStamps.append(makeCountryStamp(v))
                    activeVisit = nil
                }
                continue
            }
            let dep = stay.departure ?? stay.arrival
            if let v = activeVisit, v.code == code, stay.arrival.timeIntervalSince(v.end) < 14 * 86_400 {
                activeVisit?.end = max(v.end, dep)
            } else {
                if let v = activeVisit { countryStamps.append(makeCountryStamp(v)) }
                activeVisit = (code, stay.country ?? code, stay.arrival, dep, stay.city)
            }
        }
        if let v = activeVisit { countryStamps.append(makeCountryStamp(v)) }
        countryStamps.reverse()

        // 2. China 34 Province Seals
        let cal = Calendar.current
        let provinceSeals: [ProvinceSeal] = provinceCatalog.map { item in
            let matches = stays.filter { stay in
                if item.char == "港" && stay.countryCode == "HK" { return true }
                if item.char == "澳" && stay.countryCode == "MO" { return true }
                if item.char == "台" && stay.countryCode == "TW" { return true }
                let hay = [stay.region, stay.city, stay.country].compactMap { $0 }.joined(separator: " ")
                return item.keys.contains { hay.localizedCaseInsensitiveContains($0) }
            }
            let days = Set(matches.map { cal.startOfDay(for: $0.arrival) }).count
            return ProvinceSeal(
                id: item.char,
                shortChar: item.char,
                fullName: item.name,
                keywords: item.keys,
                visited: !matches.isEmpty,
                firstVisit: matches.map(\.arrival).min(),
                days: days
            )
        }

        // 3. City Stamps
        let byCity = Dictionary(grouping: tagged.filter { $0.city != nil }) { $0.city! }
        let cityStamps: [CityStamp] = byCity.map { city, list in
            let days = Set(list.map { cal.startOfDay(for: $0.arrival) }).count
            return CityStamp(
                id: city,
                cityName: city,
                countryName: list.first?.country,
                firstVisit: list.map(\.arrival).min() ?? Date(),
                days: days,
                visits: list.count
            )
        }.sorted { $0.firstVisit > $1.firstVisit }

        // 4. Four Extremes + Highest Point
        var extremes: [ExtremePoint] = []
        if let north = stays.max(by: { $0.latitude < $1.latitude }) {
            extremes.append(ExtremePoint(id: "north", label: "北至", placeName: north.city ?? north.displayName,
                                         detail: String(format: "%.2f° N", north.latitude), date: north.arrival))
        }
        if let south = stays.min(by: { $0.latitude < $1.latitude }) {
            extremes.append(ExtremePoint(id: "south", label: "南至", placeName: south.city ?? south.displayName,
                                         detail: String(format: "%.2f° %@", abs(south.latitude), south.latitude >= 0 ? "N" : "S"), date: south.arrival))
        }
        if let east = stays.max(by: { $0.longitude < $1.longitude }) {
            extremes.append(ExtremePoint(id: "east", label: "东至", placeName: east.city ?? east.displayName,
                                         detail: String(format: "%.2f° E", east.longitude), date: east.arrival))
        }
        if let west = stays.min(by: { $0.longitude < $1.longitude }) {
            extremes.append(ExtremePoint(id: "west", label: "西至", placeName: west.city ?? west.displayName,
                                         detail: String(format: "%.2f° %@", abs(west.longitude), west.longitude >= 0 ? "E" : "W"), date: west.arrival))
        }
        let allPoints = chunks.flatMap(\.points).filter { $0.altitude > 10 && $0.altitude < 9000 }
        if let highest = allPoints.max(by: { $0.altitude < $1.altitude }) {
            extremes.append(ExtremePoint(id: "alt", label: "最高点", placeName: "海拔记录",
                                         detail: "\(Int(highest.altitude.rounded())) m", date: highest.timestamp))
        }

        // 5. Special Stamps
        let hasNorth = stays.contains { $0.latitude > 0 }
        let hasSouth = stays.contains { $0.latitude < 0 }
        let crossedEquator = hasNorth && hasSouth
        let arcticStay = stays.first { $0.latitude >= 66.5 }
        let hasEastFar = stays.contains { $0.longitude > 100 }
        let hasWestFar = stays.contains { $0.longitude < -100 }
        let newYearStay = stays.first {
            let comps = cal.dateComponents([.month, .day], from: $0.arrival)
            return comps.month == 1 && comps.day == 1
        }

        let specialStamps: [SpecialStamp] = [
            SpecialStamp(id: "equator", title: "跨越赤道", subtitle: "足迹遍及南北半球", symbol: "globe", unlocked: crossedEquator, date: stays.first { $0.latitude < 0 }?.arrival),
            SpecialStamp(id: "arctic", title: "进入北极圈", subtitle: "北纬 66.5° 以上", symbol: "snowflake", unlocked: arcticStay != nil, date: arcticStay?.arrival),
            SpecialStamp(id: "dateline", title: "跨越太平洋", subtitle: "东西半球远行", symbol: "airplane.circle.fill", unlocked: hasEastFar && hasWestFar, date: stays.first { $0.longitude < -100 }?.arrival),
            SpecialStamp(id: "newyear", title: "跨年足迹", subtitle: "元旦当日在路上", symbol: "sparkles", unlocked: newYearStay != nil, date: newYearStay?.arrival)
        ]

        // 6. Stamp Sets
        let visitedCityNames = Set(stays.compactMap(\.city))
        let stampSets: [StampSet] = setCatalog.map { item in
            let matched = item.cities.filter { target in
                visitedCityNames.contains { $0.contains(target) }
            }
            return StampSet(id: item.id, title: item.title, subtitle: item.subtitle, requiredCities: item.cities, matchedCities: matched)
        }.sorted { $0.progress > $1.progress }

        return PassportSummary(
            homeCountryCode: homeCode,
            homeCountryName: homeName,
            countryStamps: countryStamps,
            provinceSeals: provinceSeals,
            cityStamps: cityStamps,
            extremes: extremes,
            specialStamps: specialStamps,
            stampSets: stampSets
        )
    }

    private static func makeCountryStamp(_ v: (code: String, name: String, start: Date, end: Date, port: String?)) -> CountryStamp {
        let cal = Calendar.current
        let days = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: v.start), to: cal.startOfDay(for: v.end)).day ?? 0) + 1)
        return CountryStamp(
            id: "\(v.code)-\(Int(v.start.timeIntervalSince1970))",
            countryCode: v.code,
            countryName: v.name,
            nativeName: nativeCountryNames[v.code] ?? v.name.uppercased(),
            entryDate: v.start,
            exitDate: v.end,
            days: days,
            portCity: v.port
        )
    }
}
