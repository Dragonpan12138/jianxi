import AVFoundation
import SwiftUI
import UIKit

struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var cameraError: String?

    var body: some View {
        NavigationStack {
            Group {
                if authorization == .authorized {
                    ZStack {
                        ScannerPreview(onCode: onCode, onError: { cameraError = $0 })
                            .ignoresSafeArea(edges: .bottom)
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .frame(width: 240, height: 240)
                            .allowsHitTesting(false)
                        if let cameraError {
                            Text(cameraError)
                                .multilineTextAlignment(.center)
                                .padding(18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding(24)
                        }
                    }
                    .background(.black)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("需要相机权限才能扫码")
                            .font(.headline)
                        if authorization == .denied || authorization == .restricted {
                            Button("打开设置") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("扫一扫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            if authorization == .notDetermined {
                let allowed = await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .video) { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
                authorization = allowed ? .authorized : .denied
            }
        }
    }
}

private struct ScannerPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
        controller.onError = onError
    }

    static func dismantleUIViewController(_ controller: ScannerViewController, coordinator: ()) {
        controller.stop()
    }
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "dev.rain.laundry.camera")
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
    private var detected = false

    override func viewDidLoad() {
        super.viewDidLoad()
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        captureQueue.async { [weak self] in self?.configure() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            report("没有可用的相机，请粘贴设备码。")
            return
        }
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            report("相机暂时无法扫码，请粘贴设备码。")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        session.startRunning()
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !detected,
              let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue else {
            return
        }
        detected = true
        onCode?(code)
        stop()
    }
}
