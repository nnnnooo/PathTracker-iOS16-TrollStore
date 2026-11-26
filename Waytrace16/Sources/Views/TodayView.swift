import SwiftUI
import CoreLocation
import CoreMotion

struct TodayView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger

    @AppStorage("wt16.timeline.newestFirst") private var newestFirst = true
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showFullScreenMap = false
    @State private var showNewRecording = false
    @State private var editingStay: Stay?
    @State private var editingChunk: TrackChunk?
    @State private var dayShareCardURL: URL?
    @State private var daySteps: Int?

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var dayChunks: [TrackChunk] { store.chunks(on: selectedDate) }
    private var dayStays: [Stay] { store.stays(on: selectedDate) }
    private var onThisDayMemories: [MemoriesEngine.OnThisDayMemory] {
        MemoriesEngine.onThisDay(date: selectedDate, stays: store.stays)
    }
    private var reunionMoment: MemoriesEngine.ReunionMoment? {
        isToday ? MemoriesEngine.reunion(todayStays: dayStays, allStays: store.stays) : nil
    }
    private var dayDistance: Double {
        let saved = dayChunks.reduce(0) { $0 + $1.distance }
        let live = isToday ? TrackPoint.distance(of: engine.pendingPoints) : 0
        return saved + live
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isToday {
                        trackingStatusCard
                        if let reunion = reunionMoment { reunionCard(reunion) }
                        if !onThisDayMemories.isEmpty { onThisDaySection }
                    }

                    mapCard
                    metricsBar
                    timelineSection

                    if !dayChunks.isEmpty || !dayStays.isEmpty {
                        shareDaySection
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, isToday ? 24 : 76)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .simultaneousGesture(
                DragGesture(minimumDistance: 35)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard abs(dx) > 90, abs(dx) > abs(dy) * 2 else { return }
                        shift(by: dx > 0 ? -1 : 1)
                    }
            )
            .overlay(alignment: .bottom) {
                if !isToday {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            selectedDate = Date()
                        }
                    } label: {
                        Label("回到今天", systemImage: "arrow.uturn.forward")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    }
                    .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button {
                            shift(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                        }
                        Button {
                            shift(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(isToday)
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(Formatters.dayTitle(selectedDate))
                            .font(.headline)
                        Text(Formatters.weekdaySubtitle(selectedDate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .fixedSize()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if engine.activeTrip == nil {
                            Button {
                                showNewRecording = true
                            } label: {
                                Image(systemName: "record.circle")
                                    .foregroundColor(.orange)
                            }
                        }
                        Button {
                            showDatePicker = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        ProfileToolbarButton(showingSettings: $showingSettings)
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
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("今天") {
                                    selectedDate = Date()
                                    showDatePicker = false
                                }
                            }
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
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding()
                    }
                }
            }
            .sheet(isPresented: $showNewRecording) { NewRecordingSheet() }
            .sheet(item: $editingStay) { stay in StayDetailSheet(stay: stay) }
            .sheet(item: $editingChunk) { chunk in MoveDetailSheet(chunk: chunk) }
            .onChange(of: selectedDate) { _ in dayShareCardURL = nil }
            .task(id: Calendar.current.startOfDay(for: selectedDate)) {
                await loadSteps(for: selectedDate)
            }
        }
    }

    private func loadSteps(for date: Date) async {
        guard CMPedometer.isStepCountingAvailable() else {
            daySteps = nil
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let now = Date()
        let end = cal.isDateInToday(date) ? now : (cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
        guard now.timeIntervalSince(start) <= 7.5 * 86_400 else {
            daySteps = nil
            return
        }
        let pedometer = CMPedometer()
        let steps: Int? = await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue)
            }
        }
        daySteps = steps
    }

    private func shift(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate),
              next <= Date() else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedDate = next
        }
    }

    // MARK: - Tracking Status Card (Upstream Capsule & Cards)

    @ViewBuilder
    private var trackingStatusCard: some View {
        if let active = engine.activeTrip {
            HStack(spacing: 12) {
                PulsingDot(color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(active.coverEmoji) \(active.title)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(active.activity?.title ?? "记录中") · \(Formatters.duration(ctx.date.timeIntervalSince(active.startDate))) · \(Formatters.distance(dayDistance))")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    engine.endActiveRecording()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if engine.isPaused {
            HStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已暂停记录").font(.subheadline.weight(.semibold))
                    Text(engine.isPausedIndefinitely ? "不记录，也不使用定位。想继续时点“继续”。" : "将在 \(engine.pausedUntil.map(Formatters.timeHM) ?? "") 自动恢复。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button("继续") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { engine.resume() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if !engine.isEnabled {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("想记录时再记录").font(.subheadline.weight(.semibold))
                        Text("现在没有在记录，也不会使用你的位置。").font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showNewRecording = true
                    } label: {
                        Label("开始记录", systemImage: "record.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("全天自动") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if engine.authorization == .notDetermined { engine.requestWhenInUse() }
                        engine.isEnabled = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if !engine.hasAlwaysPermission {
            HStack(spacing: 12) {
                Image(systemName: engine.hasAnyPermission ? "location.circle.fill" : "location.slash.fill")
                    .font(.title2)
                    .foregroundColor(engine.hasAnyPermission ? .yellow : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.hasAnyPermission ? "仅在使用时记录" : "需要位置权限")
                        .font(.subheadline.weight(.semibold))
                    Text(engine.hasAnyPermission ? "建议在位置权限中选「始终」，锁屏也能自动记录。" : "允许后才能记录每日足迹。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button(engine.hasAnyPermission ? "更改" : "允许") {
                    if engine.authorization == .notDetermined { engine.requestWhenInUse() }
                    else { engine.requestAlways() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            // Upstream compact recording capsule with inline mode badge
            HStack(spacing: 8) {
                PulsingDot(color: .green)
                Text(engine.activity == .moving ? "正在记录 · 移动中" : "正在记录")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Menu {
                    Section("记录模式") {
                        ForEach(LocationEngine.Precision.allCases) { mode in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                engine.precision = mode
                            } label: {
                                if engine.precision == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    }
                } label: {
                    Text(engine.precision.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .lineLimit(1)
                }
                GPSSignalBadge(location: engine.currentLocation)
                Spacer(minLength: 4)
                if tagger.isTagging {
                    Text(tagger.progressText ?? "识别地点(\(tagger.pendingCount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let stay = engine.openStay {
                    Label(stay.displayName, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Menu {
                    Section("暂停记录") {
                        Button("暂停，直到我继续") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.pause(until: nil)
                        }
                        Button("暂停 1 小时") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.pause(until: Date().addingTimeInterval(3600))
                        }
                        Button("暂停 3 小时") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.pause(until: Date().addingTimeInterval(3 * 3600))
                        }
                        Button("暂停到明天早上") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let cal = Calendar.current
                            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                            engine.pause(until: tomorrow.addingTimeInterval(7 * 3600))
                        }
                    }
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }

    // MARK: - Map Card

    private var mapCard: some View {
        Button {
            showFullScreenMap = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                DayRouteMapView(
                    chunks: dayChunks,
                    pendingPoints: isToday ? engine.pendingPoints : [],
                    stays: dayStays,
                    currentLocation: engine.currentLocation
                )
                .allowsHitTesting(false)

                if dayChunks.isEmpty && dayStays.isEmpty && (!isToday || engine.pendingPoints.isEmpty) {
                    Rectangle().fill(.ultraThinMaterial)
                    Label("这一天还没有轨迹", systemImage: "map")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Label("查看地图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 3-Column Metrics Bar

    private var metricsBar: some View {
        HStack(spacing: 0) {
            if let steps = daySteps {
                dayFigure(value: NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal), label: "步", symbol: "shoeprints.fill", tint: .orange)
                Divider().frame(height: 34)
                dayFigure(value: Formatters.distance(dayDistance), label: "移动", symbol: "figure.walk", tint: .green)
                Divider().frame(height: 34)
                dayFigure(value: "\(dayStays.count)", label: "个地点", symbol: "mappin.and.ellipse", tint: .pink)
            } else {
                dayFigure(value: Formatters.distance(dayDistance), label: "移动", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .blue)
                Divider().frame(height: 34)
                dayFigure(value: "\(dayStays.count)", label: "个地点", symbol: "mappin.and.ellipse", tint: .pink)
                Divider().frame(height: 34)
                dayFigure(value: "\(dayChunks.count)", label: "段行程", symbol: "figure.walk", tint: .green)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dayFigure(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundColor(tint)
                Text(label).foregroundColor(.secondary)
            }
            .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Upstream Rail Timeline

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
        let sorted = (dayStays.map { TimelineEntry.stay($0) } + dayChunks.map { TimelineEntry.move($0) })
            .sorted { $0.sortDate < $1.sortDate }
        return newestFirst ? sorted.reversed() : sorted
    }

    private var timelineSection: some View {
        let entries = timelineEntries
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("时间线").font(.title3.bold())
                Spacer()
                if !entries.isEmpty {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.25)) { newestFirst.toggle() }
                    } label: {
                        Label(newestFirst ? "最新在前" : "最早在前", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk.departure")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(isToday ? "今天的故事刚刚开始" : "没有记录")
                        .font(.headline)
                    Text(isToday ? "带着手机出发吧，停留超过几分钟的地方会出现在这里。" : "这一天没有记录到轨迹或停留。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let isFirst = index == 0
                        let isLast = index == entries.count - 1
                        switch entry {
                        case .stay(let stay):
                            if index > 0, case .stay = entries[index - 1] {
                                HStack(spacing: 0) {
                                    Color.clear.frame(width: 48)
                                    TimelineRailLine(dashed: true)
                                    Spacer()
                                }
                                .frame(height: 12)
                            }
                            TimelineStayRow(
                                stay: stay,
                                day: selectedDate,
                                isFirst: isFirst,
                                isLast: isLast,
                                isPrivate: store.isCoordinatePrivate(stay.coordinate)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editingStay = stay }
                        case .move(let chunk):
                            Button { editingChunk = chunk } label: {
                                TimelineMoveRow(chunk: chunk, isFirst: isFirst, isLast: isLast)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reunion & On This Day & Share

    private func reunionCard(_ reunion: MemoriesEngine.ReunionMoment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("久别重逢 · \(reunion.placeName)")
                    .font(.subheadline.weight(.semibold))
                Text("距离上次来到这里已经过去 \(reunion.daysSinceLastVisit) 天（上次：\(Formatters.dayTitle(reunion.lastVisitDate))），这是第 \(reunion.totalVisits) 次到访。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("那年今日").font(.headline).padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(onThisDayMemories) { mem in
                        OnThisDayMemoryCard(memory: mem)
                    }
                }
            }
        }
    }

    private var shareDaySection: some View {
        Group {
            if let url = dayShareCardURL {
                ShareLink(item: url) {
                    Label("分享今日足迹卡片", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    let cities = dayStays.compactMap(\.city).removingDuplicates()
                    dayShareCardURL = ShareCardGenerator.renderDayCard(
                        title: Formatters.dayTitle(selectedDate),
                        subtitle: Formatters.weekdaySubtitle(selectedDate),
                        distance: dayDistance,
                        stayCount: dayStays.count,
                        cities: cities,
                        chunks: dayChunks,
                        privacyZones: store.privacyZones
                    )
                } label: {
                    Label("生成今日足迹分享卡片", systemImage: "photo.artframe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Upstream Timeline Rail Subviews

private struct TimelineRailLine: View {
    var color: Color = Color.secondary.opacity(0.22)
    var width: CGFloat = 2
    var dashed: Bool = false
    var fadesIn: Bool = false
    var fadesOut: Bool = false

    var body: some View {
        GeometryReader { proxy in
            Path {
                $0.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                $0.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [2, 5] : []))
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: fadesIn ? .clear : .black, location: 0),
                        .init(color: .black, location: fadesIn ? 0.35 : 0),
                        .init(color: .black, location: fadesOut ? 0.65 : 1),
                        .init(color: fadesOut ? .clear : .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: 34)
    }
}

private struct TimelineStayRow: View {
    let stay: Stay
    let day: Date
    let isFirst: Bool
    let isLast: Bool
    let isPrivate: Bool

    @State private var photos: [PhotoPreviewItem] = []
    private var isHere: Bool { stay.departure == nil }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left margin 24h times
            VStack(alignment: .trailing, spacing: 1) {
                Text(Formatters.timeHM(stay.arrival))
                    .font(.subheadline.weight(.semibold))
                if let dep = stay.departure {
                    Text(Formatters.timeHM(dep))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 48, alignment: .trailing)
            .padding(.top, 13)

            // Center rail + node
            ZStack(alignment: .top) {
                TimelineRailLine(fadesIn: isFirst, fadesOut: isLast && !isHere)
                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 26)
                    .padding(3)
                    .background(Circle().fill(Color(.systemGroupedBackground)))
                    .overlay {
                        if isHere { TimelineNowRing(color: stay.category.tint) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if stay.isFromPhotos {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.pink))
                                .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .padding(.top, 11)
            }

            // Right card
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stay.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if stay.isLandmark {
                            Image(systemName: "star.fill").font(.caption2).foregroundColor(.yellow)
                        }
                        if isPrivate {
                            Image(systemName: "eye.slash.fill").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer(minLength: 4)
                        if isHere {
                            HStack(spacing: 5) {
                                PulsingDot(color: stay.category.tint)
                                Text("现在").font(.caption.weight(.semibold))
                            }
                            .foregroundColor(stay.category.tint)
                        }
                    }
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if let note = stay.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(4)
                }
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { idx, item in
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .onTapGesture {
                                        PhotoLightboxPresenter.present(items: photos, startIndex: idx)
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        if isHere {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(stay.category.tint.opacity(0.35), lineWidth: 1)
                        }
                    }
            )
            .padding(.bottom, 10)
        }
        .task(id: stay.id) {
            photos = await StintPhotoFetcher.shared.stayPhotoItems(for: stay)
        }
    }

    private var detailText: String {
        if stay.tagState == .pending { return "正在识别地点…" }
        let length = isHere ? "已停留 \(Formatters.duration(stay.duration))" : Formatters.duration(stay.duration)
        return [stay.city, length].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct TimelineMoveRow: View {
    let chunk: TrackChunk
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            TimelineRailLine(
                color: chunk.mode.color.opacity(0.75),
                width: 3,
                dashed: chunk.mode == .subway,
                fadesIn: isFirst,
                fadesOut: isLast
            )
            HStack(spacing: 8) {
                Image(systemName: chunk.mode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundColor(chunk.mode.color)
                    .frame(width: 24, height: 24)
                    .background(chunk.mode.color.opacity(0.14), in: Circle())
                Text(chunk.mode.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                Text("\(Formatters.distance(chunk.distance)) · \(Formatters.duration(chunk.duration))")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                MiniRouteSketchView(points: chunk.points, tint: chunk.mode.color)
                    .frame(width: 58, height: 34)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 52)
    }
}

private struct MiniRouteSketchView: View {
    let points: [TrackPoint]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let step = max(1, points.count / 40)
            let sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
            let lats = sampled.map(\.latitude), lons = sampled.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let spanLat = max(maxLat - minLat, 0.0005)
            let spanLon = max(maxLon - minLon, 0.0005)
            let pad: CGFloat = 5
            let w = size.width - pad * 2, h = size.height - pad * 2
            let mapped = sampled.map { pt -> CGPoint in
                let x = pad + CGFloat((pt.longitude - minLon) / spanLon) * w
                let y = pad + CGFloat(1.0 - (pt.latitude - minLat) / spanLat) * h
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.addLines(mapped)
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            if let first = mapped.first {
                context.fill(Path(ellipseIn: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5)), with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5)), with: .color(tint), lineWidth: 1.5)
            }
            if let last = mapped.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(tint))
            }
        }
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimelineNowRing: View {
    let color: Color
    @State private var breathe = false

    var body: some View {
        Circle()
            .stroke(color.opacity(breathe ? 0 : 0.55), lineWidth: 2)
            .scaleEffect(breathe ? 1.45 : 1)
            .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: breathe)
            .onAppear {
                breathe = true
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Detail Sheets (Move & Stay)

private struct MoveDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let chunk: TrackChunk
    @State private var selectedMode: MovementMode
    @State private var showDeleteConfirm = false
    @State private var mapResetToken = 0

    init(chunk: TrackChunk) {
        self.chunk = chunk
        _selectedMode = State(initialValue: chunk.mode)
    }

    private var previewChunk: TrackChunk {
        var copy = chunk
        copy.modeRaw = selectedMode.rawValue
        return copy
    }

    private var departurePlaceName: String {
        let candidates = store.stays(on: chunk.startDate)
        let prev = candidates
            .filter { ($0.departure ?? $0.arrival) <= chunk.startDate.addingTimeInterval(600) }
            .min { abs(($0.departure ?? $0.arrival).timeIntervalSince(chunk.startDate)) < abs(($1.departure ?? $1.arrival).timeIntervalSince(chunk.startDate)) }
        if let prev, abs((prev.departure ?? prev.arrival).timeIntervalSince(chunk.startDate)) <= 1800 {
            return prev.displayName
        }
        return "出发"
    }

    private var arrivalPlaceName: String {
        let candidates = store.stays(on: chunk.endDate)
        let next = candidates
            .filter { $0.arrival >= chunk.endDate.addingTimeInterval(-600) }
            .min { abs($0.arrival.timeIntervalSince(chunk.endDate)) < abs($1.arrival.timeIntervalSince(chunk.endDate)) }
        if let next, abs(next.arrival.timeIntervalSince(chunk.endDate)) <= 1800 {
            return next.displayName
        }
        return "到达"
    }

    private var arrivalStay: Stay? {
        let candidates = store.stays(on: chunk.endDate)
        let next = candidates
            .filter { $0.arrival >= chunk.endDate.addingTimeInterval(-600) }
            .min { abs($0.arrival.timeIntervalSince(chunk.endDate)) < abs($1.arrival.timeIntervalSince(chunk.endDate)) }
        if let next, abs(next.arrival.timeIntervalSince(chunk.endDate)) <= 1800 {
            return next
        }
        return nil
    }

    private static func cnDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f公里", meters / 1000)
        }
        return "\(Int(meters.rounded()))米"
    }

    private static func cnSpeed(_ metersPerSecond: Double) -> String {
        String(format: "%.1f公里/时", max(0, metersPerSecond) * 3.6)
    }

    private static func cnDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int(seconds / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)天 \(hours)小时" : "\(days)天"
        } else if hours > 0 {
            return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时"
        }
        return "\(minutes)分钟"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. 圆角路线地图卡片 + 右上角复位按钮
                    ZStack(alignment: .topTrailing) {
                        DayRouteMapView(
                            chunks: [previewChunk],
                            pendingPoints: [],
                            stays: arrivalStay.map { [$0] } ?? [],
                            currentLocation: nil
                        )
                        .id("\(selectedMode.rawValue)-\(mapResetToken)")
                        .frame(height: 245)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            mapResetToken &+= 1
                        } label: {
                            Image(systemName: "location")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .padding(12)
                    }

                    // 2. 起止地点时间轴卡片
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 1.5, height: 28)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(departurePlaceName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(Formatters.timeHM(chunk.startDate))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(arrivalPlaceName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(Formatters.timeHM(chunk.endDate))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    // 3. 数据卡片
                    VStack(alignment: .leading, spacing: 8) {
                        Text("数据")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)

                        VStack(spacing: 0) {
                            metricRow("距离", Self.cnDistance(chunk.distance))
                            Divider().padding(.leading, 16)
                            metricRow("用时", Self.cnDuration(chunk.duration))
                            Divider().padding(.leading, 16)
                            metricRow("平均速度", Self.cnSpeed(chunk.averageSpeed))
                            Divider().padding(.leading, 16)
                            metricRow("最高速度", Self.cnSpeed(chunk.maxSpeed))
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    // 4. 出行方式卡片（带图标跳转二级页）
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink {
                            MovementModePickerView(selectedMode: $selectedMode)
                        } label: {
                            HStack(spacing: 10) {
                                Text("出行方式")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: selectedMode.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.blue)
                                Text(selectedMode.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text("如果识别错了，可以在这里改正。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                    }

                    // 5. 删除这段轨迹卡片
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .foregroundColor(.blue)
                                Text("删除这段轨迹")
                                    .font(.body)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text("适合删除 GPS 漂移产生的乱线。停留记录不受影响。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(selectedMode.title) · \(Self.cnDistance(chunk.distance))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if selectedMode != chunk.mode {
                            store.updateChunkMode(id: chunk.id, mode: selectedMode)
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue, in: Circle())
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
        .presentationDragIndicator(.visible)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct MovementModePickerView: View {
    @Binding var selectedMode: MovementMode
    @Environment(\.dismiss) private var dismiss

    private static let selectableModes: [MovementMode] = [
        .walking, .running, .cycling, .automotive, .subway, .flying
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(Self.selectableModes.enumerated()), id: \.element) { idx, mode in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedMode = mode
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.symbol)
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 28, alignment: .center)
                            Text(mode.title)
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < Self.selectableModes.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("出行方式")
        .navigationBarTitleDisplayMode(.inline)
    }
}


