//
//  DuoHingeWatcher.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

/// Feeds `DuoPoseMonitor` from the iPhone Duo's hinge. Place it once behind the
/// app's root view; it draws nothing and takes no touches.
struct DuoHingeWatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> DuoHingeWatcherView {
        DuoHingeWatcherView()
    }

    func updateUIView(_ uiView: DuoHingeWatcherView, context: Context) {}
}

final class DuoHingeWatcherView: UIView {
    private var hingeStatus: DuoHingeStatus?
    private var foldRefreshTask: Task<Void, Never>?
    private var overlayWindow: DuoFakePoseOverlayWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.receive(update.hinge.map { DuoHingeStatus($0.status) })
            })
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installFakePoseOverlayIfNeeded()
        publish()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    private func receive(_ status: DuoHingeStatus?) {
        hingeStatus = status
        publish()

        // The fold region can settle a moment after the hinge reports, so read
        // it again once the system has laid it out.
        foldRefreshTask?.cancel()
        foldRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            self?.publish()
        }
    }

    private func publish() {
        guard let window else {
            return
        }

        let monitor = DuoPoseMonitor.shared
        if monitor.isSimulated {
            monitor.updateSimulatedWindowBounds(window.bounds)
            return
        }

        monitor.receive(hingeStatus: hingeStatus, foldFrame: activeFoldFrame(), windowSize: window.bounds.size)
    }

    private func activeFoldFrame() -> CGRect? {
        guard #available(iOS 27.1, *) else {
            return nil
        }
        guard let fold = reservedRegions(kind: .division).first(where: \.isActive) else {
            return nil
        }
        return convert(fold.frame, to: nil)
    }

    private func installFakePoseOverlayIfNeeded() {
        guard DuoPoseMonitor.shared.isSimulated, overlayWindow == nil, let windowScene = window?.windowScene else {
            return
        }

        let overlayWindow = DuoFakePoseOverlayWindow(windowScene: windowScene)
        overlayWindow.isHidden = false
        self.overlayWindow = overlayWindow
    }
}

extension DuoHingeStatus {
    @available(iOS 27.1, *)
    init(_ status: UIHinge.Status) {
        switch status {
        case .closed:
            self = .closed
        case .partiallyOpen:
            self = .partiallyOpen
        case .fullyOpen:
            self = .fullyOpen
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

/// Floats the fake-pose switch and the stand-in fold above everything,
/// including the reader's full-screen cover. Touches outside the switch pass
/// through to the app.
final class DuoFakePoseOverlayWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .alert + 1
        backgroundColor = .clear

        let hostingController = UIHostingController(rootView: DuoFakePoseOverlay())
        hostingController.view.backgroundColor = .clear
        rootViewController = hostingController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool {
        false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === rootViewController?.view ? nil : hitView
    }
}

struct DuoFakePoseOverlay: View {
    private var monitor = DuoPoseMonitor.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            if let foldFrame = monitor.state.foldFrame {
                Rectangle()
                    .fill(Color.orange.opacity(0.10))
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color.orange.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    }
                    .frame(width: foldFrame.width, height: foldFrame.height)
                    .offset(x: foldFrame.minX, y: foldFrame.minY)
                    .allowsHitTesting(false)
            }

            poseSwitch
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .ignoresSafeArea()
    }

    private var poseSwitch: some View {
        Button(action: monitor.cycleSimulatedPose) {
            VStack(spacing: 2) {
                Text("DUO")
                    .font(.system(size: 9, weight: .heavy))
                Text(monitor.pose.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Simulated Duo pose: \(monitor.pose.title)")
        .accessibilityHint("Switches to the next pose")
    }
}
