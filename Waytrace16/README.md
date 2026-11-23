# 漫迹 Waytrace — iOS 16.0+ 精简核心版 (MVP)

基于 [lxyeternal/PathTracker](https://github.com/lxyeternal/PathTracker)（PolyForm Noncommercial 1.0.0 许可，仅限个人学习与自用）重构的 **iOS 16.0+ / TrollStore 适配版**。

## 第一阶段（MVP）已实现的核心功能
1. **全天自动后台轨迹记录与三档省电模式**：省电（系统到访 + 显著位置变化，接近 Rond）、均衡（停留满 10 分钟关 GPS 切 150 米地理围栏）、精细（连续高精度），支持定时暂停与出行方式识别。
2. **每日时间线与停留地点自动识别**：`MKMapView` 分色轨迹地图（含中国大陆 WGS-84 → GCJ-02 纠偏）、`CLGeocoder` + MapKit 兴趣点识别与自定义命名。
3. **全部足迹地图与国家/城市统计**：足迹光点/全部路线切换、国家与城市停留天数明细。
4. **从相册导入历史照片点亮足迹**：本地扫描 EXIF 坐标并聚类去重，后台按 3 公里网格批量识别城市与国家。
5. **本地 SQLite3 存储与 GPX 导出**：适配 TrollStore 环境，无需 iCloud 权限。
