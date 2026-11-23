import SwiftUI
import CoreLocation

struct TodayView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showFullScreenMap = false
    @State private var showPauseMenu = false
    @State private var showNewRecording = false
    @State private var editingStay: Stay?
    @State private var editingChunk: TrackChunk?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var dayChunks: [TrackChunk] { store.chunks(on: selectedDate) }
    private var dayStays: [Stay] { store.stays(on: selectedDate) }
    private var dayDistance: Double {
        let saved = dayChunks.reduce(0) { $0 + $1.distance }
        let live = isToday ? TrackPoint.distance(of: engine.pendingPoints) : 0
        return saved + live
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateBar
                    mapCard
                    if isToday { statusCard }
                    metricsRow
                    timelineSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showNewRecording = true
                    } label: {
                        Image(systemName: engine.activeTrip != nil ? "record.circle.fill" : "record.circle")
                            .foregroundColor(engine.activeTrip != nil ? .red : .accentColor)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(Formatters.dayTitle(selectedDate)).font(.headline)
                        Text(Formatters.weekdaySubtitle(selectedDate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("选择日期", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("选择日期")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showDatePicker = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $showFullScreenMap) {
                ZStack(alignment: .topTrailing) {
                    DayRouteMapView(
                        chunks: dayChunks,
                        pendingPoints: isToday ? engine.pendingPoints : [],
                        stays: dayStays,
                        currentLocation: engine.currentLocation
                    )
                    .ignoresSafeArea()
                    Button {
                        showFullScreenMap = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .padding()
                    }
                }
            }
            .sheet(isPresented: $showNewRecording) {
                NewRecordingSheet()
            }
            .sheet(item: $editingStay) { stay in
                StayEditSheet(stay: stay)
            }
            .sheet(item: $editingChunk) { chunk in
                MoveDetailSheet(chunk: chunk)
            }
        }
    }

    private var dateBar: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Label("前一天", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            Spacer()
            if !isToday {
                Button("回到今天") {
                    selectedDate = Date()
                }
                .font(.subheadline.weight(.medium))
            }
            Spacer()
            Button {
                let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                if next <= Date() { selectedDate = next }
            } label: {
                HStack(spacing: 4) {
                    Text("后一天")
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
            }
            .disabled(isToday)
        }
        .padding(.top, 8)
    }

    private var mapCard: some View {
        ZStack(alignment: .bottomTrailing) {
            DayRouteMapView(
                chunks: dayChunks,
                pendingPoints: isToday ? engine.pendingPoints : [],
                stays: dayStays,
                currentLocation: engine.currentLocation
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                showFullScreenMap = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(10)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusHeadline).font(.subheadline.weight(.semibold))
                    Text(statusDetail).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if engine.activeTrip != nil {
                    Button("结束记录") {
                        engine.endActiveRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                } else if !engine.hasAlwaysPermission {
                    Button("授予始终定位") {
                        if engine.authorization == .notDetermined {
                            engine.requestWhenInUse()
                        } else {
                            engine.requestAlways()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if !engine.isEnabled {
                    Button("开启记录") {
                        engine.isEnabled = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if engine.isPaused {
                    Button("恢复") {
                        engine.resume()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("暂停") {
                        showPauseMenu = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .confirmationDialog("暂停全天记录", isPresented: $showPauseMenu, titleVisibility: .visible) {
            Button("暂停 1 小时") { engine.pause(until: Date().addingTimeInterval(3600)) }
            Button("暂停 3 小时") { engine.pause(until: Date().addingTimeInterval(3 * 3600)) }
            Button("暂停到明天早上 8:00") {
                let cal = Calendar.current
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                engine.pause(until: tomorrow.addingTimeInterval(8 * 3600))
            }
            Button("一直暂停直到手动恢复") { engine.pause(until: nil) }
            Button("取消", role: .cancel) {}
        }
    }

    private var statusColor: Color {
        if engine.activeTrip != nil { return .red }
        if !engine.hasAnyPermission { return .red }
        if !engine.isEnabled || engine.isPaused { return .gray }
        return engine.activity == .moving ? .green : .blue
    }

    private var statusHeadline: String {
        if let active = engine.activeTrip {
            return "正在高精度记录：\(active.title)"
        }
        if engine.isPaused {
            if engine.isPausedIndefinitely { return "已暂停记录" }
            if let until = engine.pausedUntil { return "已暂停至 \(Formatters.timeHM(until))" }
        }
        if let stay = engine.openStay, engine.isRecording {
            return "停留在 \(stay.displayName)"
        }
        return engine.activity.title
    }

    private var statusDetail: String {
        if engine.activeTrip != nil {
            return "手动运动记录中（高精度 GPS）"
        }
        if !engine.hasAlwaysPermission {
            return "需要「始终允许」定位权限才能在后台自动记录轨迹"
        }
        return "当前模式：\(engine.precision.title)" + (tagger.isTagging ? " · 正在识别地点(\(tagger.pendingCount))" : "")
    }

    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricItem(title: "移动距离", value: Formatters.distance(dayDistance))
            Divider().frame(height: 30)
            metricItem(title: "停留地点", value: "\(dayStays.count)")
            Divider().frame(height: 30)
            metricItem(title: "轨迹分段", value: "\(dayChunks.count)")
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private enum TimelineEntry: Identifiable {
        case stay(Stay)
        case move(TrackChunk)

        var id: String {
            switch self {
            case .stay(let s): return "s-\(s.id.uuidString)"
            case .move(let c): return "c-\(c.id.uuidString)"
            }
        }

        var sortDate: Date {
            switch self {
            case .stay(let s): return s.arrival
            case .move(let c): return c.startDate
            }
        }
    }

    private var timelineEntries: [TimelineEntry] {
        let all: [TimelineEntry] = dayStays.map { .stay($0) } + dayChunks.map { .move($0) }
        return all.sorted { $0.sortDate < $1.sortDate }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("时间线").font(.headline).padding(.horizontal, 4)

            if timelineEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("这一天还没有足迹记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(timelineEntries) { entry in
                        switch entry {
                        case .stay(let stay):
                            Button {
                                editingStay = stay
                            } label: {
                                stayRow(stay)
                            }
                            .buttonStyle(.plain)
                        case .move(let chunk):
                            Button {
                                editingChunk = chunk
                            } label: {
                                moveRow(chunk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func stayRow(_ stay: Stay) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.timeHM(stay.arrival))
                    .font(.caption.monospacedDigit().weight(.medium))
                if let dep = stay.departure {
                    Text(Formatters.timeHM(dep))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text("现在")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 44, alignment: .trailing)

            Image(systemName: stay.category.symbol)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(stay.category.tint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stay.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if stay.isFromPhotos {
                        Text("相册")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundColor(.orange)
                    }
                    if store.isCoordinatePrivate(stay.coordinate) {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(Formatters.duration(stay.duration))
                    if let sub = stay.subtitle {
                        Text("· \(sub)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

                if let note = stay.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moveRow(_ chunk: TrackChunk) -> some View {
        HStack(spacing: 12) {
            Text(Formatters.timeHM(chunk.startDate))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)

            Image(systemName: chunk.mode.symbol)
                .font(.caption)
                .foregroundColor(chunk.mode.color)
                .frame(width: 34)

            Text("\(chunk.mode.title) · \(Formatters.distance(chunk.distance)) · \(Formatters.duration(chunk.duration))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct MoveDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let chunk: TrackChunk
    @State private var selectedMode: MovementMode
    @State private var showDeleteConfirm = false

    init(chunk: TrackChunk) {
        self.chunk = chunk
        _selectedMode = State(initialValue: chunk.mode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DayRouteMapView(chunks: [chunk], pendingPoints: [], stays: [], currentLocation: nil)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }

                Section("路段数据") {
                    LabeledContent("起止时间", value: "\(Formatters.timeHM(chunk.startDate)) – \(Formatters.timeHM(chunk.endDate))")
                    LabeledContent("距离", value: Formatters.distance(chunk.distance))
                    LabeledContent("用时", value: Formatters.duration(chunk.duration))
                    LabeledContent("平均速度", value: Formatters.speed(chunk.averageSpeed))
                    LabeledContent("最高速度", value: Formatters.speed(max(chunk.maxSpeed, chunk.averageSpeed)))
                }

                Section("出行方式") {
                    Picker("修改方式", selection: $selectedMode) {
                        ForEach(MovementMode.allCases, id: \.self) { m in
                            Label(m.title, systemImage: m.symbol).tag(m)
                        }
                    }
                }

                Section {
                    Button("删除此段轨迹（清理 GPS 漂移）", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("路线详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.updateChunkMode(id: chunk.id, mode: selectedMode)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("确定删除这段轨迹吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.deleteChunk(id: chunk.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

private struct StayEditSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let stay: Stay
    @State private var name: String
    @State private var note: String
    @State private var selectedCategory: String
    @State private var isPrivateZone: Bool
    @State private var showDeleteConfirm = false

    private let quickCategories: [(id: String, label: String)] = [
        ("auto", "自动"),
        ("home", "家"),
        ("work", "公司"),
        ("school", "学校"),
        ("restaurant", "餐厅"),
        ("mall", "商场"),
        ("sight", "景点"),
    ]

    init(stay: Stay) {
        self.stay = stay
        _name = State(initialValue: stay.customName ?? stay.placeName ?? "")
        _note = State(initialValue: stay.note ?? "")
        _selectedCategory = State(initialValue: stay.categoryRaw ?? "auto")
        _isPrivateZone = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("地点信息") {
                    TextField("自定义名称（如 家、公司）", text: $name)
                    Picker("类型", selection: $selectedCategory) {
                        ForEach(quickCategories, id: \.id) { item in
                            Text(item.label).tag(item.id)
                        }
                    }
                    TextField("写点备注或当时的心情…", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Toggle("导出时隐藏此地周围 300 米", isOn: $isPrivateZone)
                } footer: {
                    Text("开启后导出 GPX 轨迹时会自动过滤该范围，你自己查看不受影响。")
                }

                Section("详情") {
                    LabeledContent("到达", value: Formatters.timeHM(stay.arrival))
                    LabeledContent("离开", value: stay.departure.map(Formatters.timeHM) ?? "停留中")
                    LabeledContent("时长", value: Formatters.duration(stay.duration))
                    if let sub = stay.subtitle {
                        LabeledContent("区域", value: sub)
                    }
                    if let street = stay.street {
                        LabeledContent("街道", value: street)
                    }
                }

                Section {
                    Button("删除此条停留记录", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("停留详情")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isPrivateZone = store.isCoordinatePrivate(stay.coordinate)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cat: String? = selectedCategory == "auto" ? nil : selectedCategory
                        store.renameNearby(stay, to: name, categoryRaw: cat, note: note)
                        let existingZone = store.privacyZone(containing: stay.coordinate)
                        if isPrivateZone && existingZone == nil {
                            let zoneName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? stay.displayName
                            store.upsertPrivacyZone(PrivacyZone(name: zoneName, latitude: stay.latitude, longitude: stay.longitude, radius: 300))
                        } else if !isPrivateZone, let zone = existingZone {
                            store.deletePrivacyZone(id: zone.id)
                        }
                        dismiss()
                    }
                }
            }
            .confirmationDialog("确定删除这条停留记录吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.deleteStay(id: stay.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
