import SwiftUI
import MapKit
import UIKit

struct BlindBoxView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @ObservedObject private var boxStore = BlindBoxStore.shared

    @State private var horizon: BlindBoxEngine.Horizon = .weekend
    @State private var vibe: BlindBoxEngine.Vibe = .any
    @State private var currentPass: BoardingPass?
    @State private var isShaking = false
    @State private var visitedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                selectorCard

                if let pass = currentPass {
                    boardingPassCard(pass)
                } else {
                    parcelCard
                }

                if !boxStore.savedPasses.isEmpty {
                    savedPassesSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("旅行盲盒")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.stays.count)-\(userStore.manualVisits.count)") {
            let staysSnapshot = store.stays
            let manualSnapshot = userStore.manualVisits
            let computed = await Task.detached(priority: .userInitiated) {
                Set(MustSee.visitedMap(places: MustSee.allPlaces, stays: staysSnapshot, manual: manualSnapshot).keys)
            }.value
            visitedIDs = computed
        }
    }

    private var selectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你有多少时间？").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Picker("时间", selection: $horizon) {
                ForEach(BlindBoxEngine.Horizon.allCases) { h in
                    Text(h.title).tag(h)
                }
            }
            .pickerStyle(.segmented)

            Text("想要什么感觉？").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BlindBoxEngine.Vibe.allCases) { item in
                        Button {
                            vibe = item
                        } label: {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    vibe == item ? Color.orange : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundColor(vibe == item ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var parcelCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.56, blue: 0.39))
                    .frame(height: 190)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                // String cross
                Rectangle().fill(Color(red: 0.92, green: 0.86, blue: 0.76)).frame(height: 4)
                Rectangle().fill(Color(red: 0.92, green: 0.86, blue: 0.76)).frame(width: 4, height: 190)

                VStack(spacing: 6) {
                    Text("?")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundColor(Color(red: 0.32, green: 0.21, blue: 0.12))
                        .frame(width: 66, height: 66)
                        .background(Color(red: 0.98, green: 0.95, blue: 0.88), in: RoundedRectangle(cornerRadius: 12))
                    Text("只抽你还没去过的地方")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
            .rotationEffect(.degrees(isShaking ? 2.5 : 0))

            Button {
                drawNewPass()
            } label: {
                Label("拆开旅行盲盒", systemImage: "gift.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private func boardingPassCard(_ pass: BoardingPass) -> some View {
        let alreadySaved = boxStore.savedPasses.contains { $0.placeID == pass.placeID }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WAYTRACE BOARDING PASS")
                    .font(.caption2.monospaced().bold())
                    .foregroundColor(.orange)
                Spacer()
                if let km = pass.distanceKm {
                    Text(String(format: "距你 %.0f km", km))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pass.placeName).font(.title.bold())
                Text(pass.region).font(.subheadline).foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label(pass.reason, systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                Text(pass.suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    boxStore.save(pass)
                    userStore.addWish(pass.placeID)
                } label: {
                    Label(alreadySaved ? "已收下" : "收下登机牌", systemImage: alreadySaved ? "checkmark" : "ticket.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(alreadySaved)

                Button {
                    drawNewPass()
                } label: {
                    Label("再拆一个", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if let place = MustSee.allPlaces.first(where: { $0.id == pass.placeID }) {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.onMap))
                    item.name = place.name
                    item.openInMaps()
                } label: {
                    Label("在 Apple 地图中查看与导航", systemImage: "location.north.line.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1.5)
        )
    }

    private var savedPassesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的登机牌夹 (\(boxStore.savedPasses.count))")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(boxStore.savedPasses) { pass in
                    let arrived = visitedIDs.contains(pass.placeID)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(pass.placeName).font(.subheadline.weight(.semibold))
                                Text(arrived ? "已经到了" : "在等你")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((arrived ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                                    .foregroundColor(arrived ? .green : .orange)
                            }
                            Text("\(pass.region) · \(Formatters.dayTitle(pass.drawnAt)) 拆出")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            boxStore.remove(id: pass.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func drawNewPass() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { isShaking = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isShaking = false
                currentPass = BlindBoxEngine.draw(
                    horizon: horizon,
                    vibe: vibe,
                    userLocation: engine.currentLocation,
                    visitedIDs: visitedIDs,
                    wishIDs: userStore.wishIDs,
                    excludingPlaceID: currentPass?.placeID
                )
            }
        }
    }
}
