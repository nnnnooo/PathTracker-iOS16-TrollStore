import SwiftUI
import VisionKit
import UIKit

/// Live camera MRZ scanner powered by iOS 16 VisionKit DataScannerViewController.
struct VisaScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScanned: (MRZParser.Parsed) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ZStack(alignment: .bottom) {
                        MRZCameraScanner { parsed in
                            let gen = UINotificationFeedbackGenerator()
                            gen.notificationOccurred(.success)
                            onScanned(parsed)
                            dismiss()
                        }
                        .ignoresSafeArea()

                        VStack(spacing: 6) {
                            Text("对准签证页底部两行机读码（MRZ）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("识别全程在本地完成，画面不会保存或上传")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("当前设备不支持实时文本扫描")
                            .font(.headline)
                        Text("请返回使用手动填写方式添加签证。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("扫描签证机读码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct MRZCameraScanner: UIViewControllerRepresentable {
    let onDetected: (MRZParser.Parsed) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDetected: onDetected) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetected: (MRZParser.Parsed) -> Void
        private var hasEmitted = false

        init(onDetected: @escaping (MRZParser.Parsed) -> Void) {
            self.onDetected = onDetected
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasEmitted else { return }
            let lines: [String] = allItems.compactMap { item in
                if case .text(let t) = item { return t.transcript }
                return nil
            }.flatMap { $0.components(separatedBy: .newlines) }

            if let parsed = MRZParser.parse(lines: lines) {
                hasEmitted = true
                dataScanner.stopScanning()
                DispatchQueue.main.async {
                    self.onDetected(parsed)
                }
            }
        }
    }
}
