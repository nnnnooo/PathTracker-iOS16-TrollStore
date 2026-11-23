import SwiftUI

struct TripsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine

    @State private var tab = 0 // 0 = 旅程, 1 = 运动记录
    @State private var showNewRecording = false
    @State private var showNewTrip = false

    private var savedTrips: [Trip] { store.trips.filter { !$0.isRecording } }
    private var savedRecordings: [Trip] { store.trips.filter { $0.isRecording } }
    private var discovered: [TripFinder.DiscoveredTrip] {
        TripFinder.discover(from: store.stays, existingTrips: store.trips)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let active = engine.activeTrip {
                        activeRecordingBanner(active)
                    }

                    Picker("类型", selection: $tab) {
                        Text("旅程 (\(savedTrips.count))").tag(0)
                        Text("运动记录 (\(savedRecordings.count))").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if tab == 0 {
                        if !discovered.isEmpty {
                            discoveredSection
                        }
                        if savedTrips.isEmpty {
                            emptyCard(
                                icon: "suitcase.rolling.fill",
                                title: "还没有保存的旅程",
                                subtitle: "离开常住地 80 公里以上的连续日子会自动出现在上方，也可以点右上角手动新建。"
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(savedTrips) { trip in
                                    NavigationLink {
                                        TripDetailView(trip: trip)
                                    } label: {
                                        tripCard(trip)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        if savedRecordings.isEmpty {
                            emptyCard(
                                icon: "figure.hiking",
                                title: "还没有运动记录",
                                subtitle: "徒步、跑步、骑行时可点右上角「开始记录」，用高精度记录路线、配速与爬升。"
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(savedRecordings) { rec in
                                    NavigationLink {
                                        TripDetailView(trip: rec)
                                    } label: {
                                        tripCard(rec)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("旅程")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showNewRecording = true
                        } label: {
                            Label("开始高精度记录", systemImage: "record.circle")
                        }
                        Button {
                            showNewTrip = true
                        } label: {
                            Label("新建多日旅程", systemImage: "suitcase.rolling")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showNewRecording) {
                NewRecordingSheet()
            }
            .sheet(isPresented: $showNewTrip) {
                NewTripSheet()
            }
        }
    }

    private func activeRecordingBanner(_ trip: Trip) -> some View {
        let chunks = store.chunks(for: trip)
        let dist = chunks.reduce(0.0) { $0 + $1.distance } + TrackPoint.distance(of: engine.pendingPoints)
        return HStack(spacing: 12) {
            Text(trip.coverEmoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在记录：\(trip.title)").font(.subheadline.weight(.semibold))
                Text("\(Formatters.distance(dist)) · \(Formatters.duration(trip.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("结束") {
                engine.endActiveRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("在足迹里发现 \(discovered.count) 段旅行")
                    .font(.headline)
                Spacer()
                if discovered.count > 1 {
                    Button("全部收下") {
                        for item in discovered { saveDiscovered(item) }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(discovered.prefix(10)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(item.days) 天 · \(item.stayCount) 个地点")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !item.cities.isEmpty {
                                Text(item.cities.prefix(3).joined(separator: " / "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Button("收进旅程") {
                                saveDiscovered(item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                        .padding(12)
                        .frame(width: 170, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func saveDiscovered(_ item: TripFinder.DiscoveredTrip) {
        let trip = Trip(
            title: item.title,
            startDate: item.startDate,
            endDate: item.endDate,
            notes: item.cities.joined(separator: " · "),
            coverEmoji: "🧳",
            activityRaw: nil
        )
        store.upsertTrip(trip)
    }

    private func tripCard(_ trip: Trip) -> some View {
        let chunks = store.chunks(for: trip)
        let stays = store.stays(for: trip)
        let dist = chunks.reduce(0.0) { $0 + $1.distance }
        return HStack(spacing: 12) {
            Text(trip.coverEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(trip.dateRangeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Formatters.distance(dist)) · \(trip.isRecording ? Formatters.duration(trip.duration) : "\(stays.count) 个地点")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    @State private var exportedURL: URL?
    @State private var shareCardURL: URL?
    @State private var showDeleteConfirm = false

    private var chunks: [TrackChunk] { store.chunks(for: trip) }
    private var stays: [Stay] { store.stays(for: trip) }
    private var allPoints: [TrackPoint] { chunks.flatMap(\.points) }
    private var totalDistance: Double { chunks.reduce(0.0) { $0 + $1.distance } }
    private var climb: Double { TrackPoint.elevationGain(of: allPoints) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DayRouteMapView(
                    chunks: chunks,
                    pendingPoints: engine.activeTripID == trip.id ? engine.pendingPoints : [],
                    stays: stays,
                    currentLocation: engine.currentLocation
                )
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 0) {
                    statCell("距离", Formatters.distance(totalDistance))
                    Divider().frame(height: 30)
                    statCell("用时", Formatters.duration(trip.duration))
                    Divider().frame(height: 30)
                    if trip.isRecording {
                        statCell("配速", Formatters.pace(distance: totalDistance, duration: trip.duration))
                    } else {
                        statCell("地点", "\(stays.count)")
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if trip.isRecording && climb > 0 {
                    HStack {
                        Label("累计爬升", systemImage: "arrow.up.right")
                        Spacer()
                        Text("\(Int(climb.rounded())) m").fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !trip.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("备注").font(.caption).foregroundColor(.secondary)
                        Text(trip.notes).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if !stays.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("经过的地点").font(.headline).padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(stays.enumerated()), id: \.element.id) { idx, stay in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stay.displayName).font(.subheadline.weight(.medium))
                                        Text("\(Formatters.dayTitle(stay.arrival)) \(Formatters.timeHM(stay.arrival))")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(Formatters.duration(stay.duration))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                if idx < stays.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if let cardURL = shareCardURL {
                    ShareLink(item: cardURL) {
                        Label("分享旅程明信片图片", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        shareCardURL = ShareCardGenerator.renderTripCard(
                            trip: trip,
                            distance: totalDistance,
                            stays: stays,
                            chunks: chunks,
                            privacyZones: store.privacyZones
                        )
                    } label: {
                        Label("生成旅程分享明信片", systemImage: "photo.artframe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let url = exportedURL {
                    ShareLink(item: url) {
                        Label("分享此旅程 GPX", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exportedURL = GPXExporter.export(
                            chunks: chunks,
                            stays: stays,
                            privacyZones: store.privacyZones,
                            filename: "\(trip.title).gpx"
                        )
                    } label: {
                        Label("导出此旅程 GPX（自动过滤隐私区域）", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button("删除此记录", role: .destructive) {
                    showDeleteConfirm = true
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确定删除这条记录吗？底层轨迹点不会被删除。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if engine.activeTripID == trip.id { engine.endActiveRecording() }
                store.deleteTrip(id: trip.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NewRecordingSheet: View {
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    @State private var activity: ActivityType = .hiking
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("运动类型") {
                    Picker("类型", selection: $activity) {
                        ForEach(ActivityType.allCases) { item in
                            Text("\(item.emoji) \(item.title)").tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("名称（可选）") {
                    TextField("例如：西湖环线徒步", text: $title)
                }
            }
            .navigationTitle("开始高精度记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        engine.beginRecording(activity: activity, title: title)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NewTripSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("旅程信息") {
                    TextField("旅程名称（如：杭州 3 日游）", text: $title)
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("备注") {
                    TextField("写点回忆…", text: $notes)
                }
            }
            .navigationTitle("新建旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cal = Calendar.current
                        let s = cal.startOfDay(for: startDate)
                        let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)) ?? endDate
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未命名旅程"
                        store.upsertTrip(Trip(title: name, startDate: s, endDate: e, notes: notes, coverEmoji: "🧳"))
                        dismiss()
                    }
                }
            }
        }
    }
}
