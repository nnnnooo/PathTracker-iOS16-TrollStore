import Foundation
import CoreLocation

/// Offline city lookup for overseas stays (especially Canada, US, Japan, Europe, Australia)
/// where Apple's CLGeocoder inside mainland China routes through AutoNavi (高德) and often returns nil city.
enum OfflineOverseasCities {
    struct Entry: Sendable {
        let country: String
        let zh: String
        let lat: Double
        let lon: Double
    }

    static func match(countryCode: String, location: CLLocation) -> String? {
        // 1. Check dedicated overseas city catalog (65 km strict radius)
        let countryEntries = entries.filter { $0.country == countryCode }
        if let best = countryEntries
            .map({ ($0, CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: location)) })
            .min(by: { $0.1 < $1.1 }) {
            if best.1 < 65_000 {
                return best.0.zh
            }
        }

        // 2. Check CityStampStyle.catalog (80 km radius)
        if let cityMatch = CityStampStyle.catalog
            .filter({ $0.country == countryCode })
            .min(by: { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: location) }),
           CLLocation(latitude: cityMatch.latitude, longitude: cityMatch.longitude).distance(from: location) < 80_000 {
            return cityMatch.zh
        }

        // 3. Check MustSee landmarks (30 km radius)
        if let mustSee = MustSee.allPlaces.first(where: { $0.location.distance(from: location) < 30_000 }) {
            return mustSee.name
        }

        // 4. Wider regional fallback (150 km) so rural Canadian towns still get their nearest metro/region name instead of "未知地点"
        if let best = countryEntries
            .map({ ($0, CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: location)) })
            .min(by: { $0.1 < $1.1 }),
           best.1 < 150_000 {
            return best.0.zh
        }

        // 5. Canada province bounding-box fallback
        if countryCode == "CA" {
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            if lon > -95.2 && lon <= -74.3 && lat >= 41.6 && lat <= 56.9 { return "安大略省" }
            if lon > -79.8 && lon <= -57.1 && lat >= 44.9 && lat <= 62.6 { return "魁北克省" }
            if lon >= -139.1 && lon <= -114.0 && lat >= 48.3 && lat <= 60.0 { return "不列颠哥伦比亚省" }
            if lon > -120.0 && lon <= -110.0 && lat >= 49.0 && lat <= 60.0 { return "艾伯塔省" }
            return "加拿大"
        }

        return nil
    }

    private static let entries: [Entry] = [
        // Canada - Ontario (Greater Toronto, Golden Horseshoe, Southwestern, Eastern, Northern)
        Entry(country: "CA", zh: "多伦多", lat: 43.6532, lon: -79.3832),
        Entry(country: "CA", zh: "密西沙加", lat: 43.5890, lon: -79.6441),
        Entry(country: "CA", zh: "万锦", lat: 43.8561, lon: -79.3370),
        Entry(country: "CA", zh: "列治文山", lat: 43.8828, lon: -79.4403),
        Entry(country: "CA", zh: "旺市", lat: 43.8361, lon: -79.4983),
        Entry(country: "CA", zh: "布兰普顿", lat: 43.7315, lon: -79.7624),
        Entry(country: "CA", zh: "奥克维尔", lat: 43.4675, lon: -79.6877),
        Entry(country: "CA", zh: "伯灵顿", lat: 43.3255, lon: -79.7990),
        Entry(country: "CA", zh: "汉密尔顿", lat: 43.2557, lon: -79.8711),
        Entry(country: "CA", zh: "尼亚加拉瀑布城", lat: 43.0896, lon: -79.0849),
        Entry(country: "CA", zh: "圣凯瑟琳斯", lat: 43.1594, lon: -79.2469),
        Entry(country: "CA", zh: "滑铁卢", lat: 43.4643, lon: -80.5204),
        Entry(country: "CA", zh: "基奇纳", lat: 43.4516, lon: -80.4925),
        Entry(country: "CA", zh: "圭尔夫", lat: 43.5448, lon: -80.2482),
        Entry(country: "CA", zh: "剑桥", lat: 43.3616, lon: -80.3144),
        Entry(country: "CA", zh: "伦敦", lat: 42.9849, lon: -81.2453),
        Entry(country: "CA", zh: "温莎", lat: 42.3149, lon: -83.0364),
        Entry(country: "CA", zh: "巴里", lat: 44.3894, lon: -79.6903),
        Entry(country: "CA", zh: "蓝山", lat: 44.5028, lon: -80.3122),
        Entry(country: "CA", zh: "托伯莫里", lat: 45.2535, lon: -81.6644),
        Entry(country: "CA", zh: "马斯科卡", lat: 45.0419, lon: -79.3106),
        Entry(country: "CA", zh: "阿冈昆省立公园", lat: 45.5833, lon: -78.3667),
        Entry(country: "CA", zh: "奥沙瓦", lat: 43.8971, lon: -78.8658),
        Entry(country: "CA", zh: "彼得伯勒", lat: 44.3091, lon: -78.3197),
        Entry(country: "CA", zh: "金斯顿", lat: 44.2312, lon: -76.4860),
        Entry(country: "CA", zh: "渥太华", lat: 45.4215, lon: -75.6972),
        Entry(country: "CA", zh: "萨德伯里", lat: 46.4917, lon: -80.9930),
        Entry(country: "CA", zh: "桑德贝", lat: 48.3809, lon: -89.2477),
        Entry(country: "CA", zh: "苏圣玛丽", lat: 46.5136, lon: -84.3358),
        // Canada - Quebec & Atlantic
        Entry(country: "CA", zh: "蒙特利尔", lat: 45.5017, lon: -73.5673),
        Entry(country: "CA", zh: "魁北克城", lat: 46.8139, lon: -71.2080),
        Entry(country: "CA", zh: "汤卜朗山", lat: 46.1185, lon: -74.5962),
        Entry(country: "CA", zh: "加蒂诺", lat: 45.4765, lon: -75.7013),
        Entry(country: "CA", zh: "舍布鲁克", lat: 45.4042, lon: -71.8929),
        Entry(country: "CA", zh: "哈利法克斯", lat: 44.6488, lon: -63.5752),
        Entry(country: "CA", zh: "夏洛特敦", lat: 46.2382, lon: -63.1311),
        Entry(country: "CA", zh: "圣约翰斯", lat: 47.5615, lon: -52.7126),
        // Canada - West & North
        Entry(country: "CA", zh: "温哥华", lat: 49.2827, lon: -123.1207),
        Entry(country: "CA", zh: "列治文", lat: 49.1666, lon: -123.1336),
        Entry(country: "CA", zh: "本拿比", lat: 49.2488, lon: -122.9805),
        Entry(country: "CA", zh: "维多利亚", lat: 48.4284, lon: -123.3656),
        Entry(country: "CA", zh: "惠斯勒", lat: 50.1163, lon: -122.9574),
        Entry(country: "CA", zh: "基洛纳", lat: 49.8880, lon: -119.4960),
        Entry(country: "CA", zh: "坎卢普斯", lat: 50.6745, lon: -120.3273),
        Entry(country: "CA", zh: "班夫", lat: 51.1784, lon: -115.5708),
        Entry(country: "CA", zh: "贾斯珀", lat: 52.8737, lon: -118.0814),
        Entry(country: "CA", zh: "卡尔加里", lat: 51.0447, lon: -114.0719),
        Entry(country: "CA", zh: "埃德蒙顿", lat: 53.5461, lon: -113.4938),
        Entry(country: "CA", zh: "温尼伯", lat: 49.8951, lon: -97.1384),
        Entry(country: "CA", zh: "萨斯卡通", lat: 52.1332, lon: -106.6700),
        Entry(country: "CA", zh: "黄刀镇", lat: 62.4540, lon: -114.3718),
        Entry(country: "CA", zh: "白马市", lat: 60.7212, lon: -135.0568),
        // US major border / tourist cities
        Entry(country: "US", zh: "布法罗", lat: 42.8864, lon: -78.8784),
        Entry(country: "US", zh: "波士顿", lat: 42.3601, lon: -71.0589),
        Entry(country: "US", zh: "费城", lat: 39.9526, lon: -75.1652),
        Entry(country: "US", zh: "迈阿密", lat: 25.7617, lon: -80.1918),
        Entry(country: "US", zh: "圣地亚哥", lat: 32.7157, lon: -117.1611),
        Entry(country: "US", zh: "底特律", lat: 42.3314, lon: -83.0458),
    ]
}
