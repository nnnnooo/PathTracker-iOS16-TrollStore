import SwiftUI
import UIKit
import Photos

// MARK: - Zero-Flash Fullscreen Photo Lightbox (Native UIScrollView Zoom + Zero-Conflict Horizontal Paging + Swipe-Down Dismiss)

struct PhotoPreviewItem: Identifiable, Hashable {
    let id: String
    let assetID: String?
    let thumbnail: UIImage
    let caption: String?

    static func == (lhs: PhotoPreviewItem, rhs: PhotoPreviewItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
enum PhotoLightboxPresenter {
    private static weak var currentHost: UIViewController?

    static func present(items: [PhotoPreviewItem], startIndex: Int = 0) {
        guard !items.isEmpty else { return }
        guard let presenter = topViewController() else { return }
        if currentHost != nil { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let safeIndex = min(max(0, startIndex), items.count - 1)
        let dismissAction: () -> Void = {
            currentHost?.dismiss(animated: true) {
                currentHost = nil
            }
        }
        let wrapped = PhotoLightboxView(
            items: items,
            initialIndex: safeIndex,
            onDismiss: dismissAction
        )
        let hosting = UIHostingController(rootView: wrapped)
        hosting.modalPresentationStyle = .overFullScreen
        hosting.modalTransitionStyle = .crossDissolve
        hosting.view.backgroundColor = .clear

        currentHost = hosting
        presenter.present(hosting, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private struct PhotoLightboxView: View {
    let items: [PhotoPreviewItem]
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0

    init(items: [PhotoPreviewItem], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.items = items
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    private var backdropOpacity: Double {
        let progress = min(1.0, abs(dragOffset) / 260.0)
        return max(0.0, 1.0 - progress * 0.85)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    ZoomablePhotoPage(
                        item: item,
                        dragOffset: $dragOffset,
                        onDismiss: onDismiss
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .ignoresSafeArea()

            VStack {
                HStack {
                    if items.count > 1 {
                        Text("\(currentIndex + 1) / \(items.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55), in: Capsule())
                    }
                    Spacer()
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                if let caption = items[safe: currentIndex]?.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 22)
                }
            }
            .opacity(backdropOpacity)
        }
        .statusBarHidden(false)
    }
}

private struct ZoomablePhotoPage: View {
    let item: PhotoPreviewItem
    @Binding var dragOffset: CGFloat
    let onDismiss: () -> Void

    @State private var displayImage: UIImage

    init(item: PhotoPreviewItem, dragOffset: Binding<CGFloat>, onDismiss: @escaping () -> Void) {
        self.item = item
        self._dragOffset = dragOffset
        self.onDismiss = onDismiss
        _displayImage = State(initialValue: item.thumbnail)
    }

    var body: some View {
        NativeZoomableImageView(
            image: displayImage,
            onVerticalDragChanged: { dy in dragOffset = dy },
            onVerticalDragEnded: { dy, vy in
                if abs(dy) > 100 || abs(vy) > 650 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            },
            onSingleTap: onDismiss
        )
        .ignoresSafeArea()
        .task(id: item.assetID) {
            guard let assetID = item.assetID else { return }
            if let hd = await Self.loadFullResolution(assetID: assetID) {
                displayImage = hd
            }
        }
    }

    private static func loadFullResolution(assetID: String) async -> UIImage? {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        return await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = true
            let maxSide = UIScreen.main.bounds.height * UIScreen.main.scale
            let target = CGSize(width: maxSide, height: maxSide)
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: req) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded, !resumed {
                    resumed = true
                    cont.resume(returning: img)
                }
            }
        }
    }
}

/// Native UIScrollView zoomable image container that NEVER blocks horizontal paging in TabView(.page).
/// Vertical swipe-to-dismiss only activates when zoomScale == 1 AND vertical velocity clearly dominates horizontal velocity.
private struct NativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onVerticalDragChanged: (CGFloat) -> Void
    let onVerticalDragEnded: (CGFloat, CGFloat) -> Void
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 4.5
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.frame = scroll.bounds
        scroll.addSubview(iv)
        context.coordinator.imageView = iv
        context.coordinator.scrollView = scroll

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        let dismissPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDismissPan(_:)))
        dismissPan.delegate = context.coordinator
        scroll.addGestureRecognizer(dismissPan)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
        }
        if scroll.zoomScale <= 1.01, let iv = context.coordinator.imageView, iv.frame.size != scroll.bounds.size {
            iv.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeZoomableImageView
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        init(_ parent: NativeZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let iv = imageView else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
            iv.center = CGPoint(
                x: scrollView.contentSize.width * 0.5 + offsetX,
                y: scrollView.contentSize.height * 0.5 + offsetY
            )
        }

        @objc func handleSingleTap() {
            guard let scroll = scrollView, scroll.zoomScale <= 1.05 else { return }
            parent.onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = scrollView else { return }
            if scroll.zoomScale > 1.05 {
                scroll.setZoomScale(1.0, animated: true)
            } else {
                let pt = gesture.location(in: imageView)
                let zoomScale: CGFloat = 2.5
                let w = scroll.bounds.width / zoomScale
                let h = scroll.bounds.height / zoomScale
                let rect = CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h)
                scroll.zoom(to: rect, animated: true)
            }
        }

        /// Only begin vertical dismiss pan when NOT zoomed in and vertical movement clearly dominates horizontal swipe.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scroll = scrollView,
                  scroll.zoomScale <= 1.01 else {
                return false
            }
            let v = pan.velocity(in: scroll)
            return abs(v.y) > abs(v.x) * 1.35
        }

        @objc func handleDismissPan(_ pan: UIPanGestureRecognizer) {
            guard let scroll = scrollView else { return }
            let t = pan.translation(in: scroll)
            let v = pan.velocity(in: scroll)
            switch pan.state {
            case .changed:
                parent.onVerticalDragChanged(t.y)
            case .ended, .cancelled, .failed:
                parent.onVerticalDragEnded(t.y, v.y)
            default:
                break
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
