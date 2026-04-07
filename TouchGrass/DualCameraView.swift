//
//  DualCameraView.swift
//  TouchGrass
//
//  BeReal-style dual-camera capture:
//  back camera fills the screen, front camera appears as a draggable PiP.
//  Both fire simultaneously; the result is composited into one image.
//

import SwiftUI
import UIKit
import AVFoundation

// MARK: - SwiftUI Wrapper

struct DualCameraView: UIViewControllerRepresentable {
    /// Called with the final composited UIImage when the user taps "Post Story".
    let onPost: (UIImage) -> Void
    /// Called when the user dismisses without posting.
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> DualCameraHostVC {
        DualCameraHostVC(onPost: onPost, onDismiss: onDismiss)
    }

    func updateUIViewController(_ vc: DualCameraHostVC, context: Context) {}
}

// MARK: - Host View Controller

final class DualCameraHostVC: UIViewController, AVCapturePhotoCaptureDelegate {

    // MARK: Session

    private var multiCamSession: AVCaptureMultiCamSession?
    private var fallbackSession: AVCaptureSession?
    private var isMultiCam = false

    // MARK: Inputs / Outputs

    private var backDeviceInput: AVCaptureDeviceInput?
    private var frontDeviceInput: AVCaptureDeviceInput?
    private let backPhotoOutput  = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()

    // MARK: Preview Layers

    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    // MARK: UI

    private let pipContainerView = UIView()
    private let captureButton    = UIButton()
    private let closeButton      = UIButton()
    private var pipWidthConstraint: NSLayoutConstraint?
    private var pipHeightConstraint: NSLayoutConstraint?

    // MARK: Capture State

    private var backPhoto: UIImage?
    private var frontPhoto: UIImage?
    private var captureGroup = DispatchGroup()
    private var pendingComposite: UIImage?
    private var previewContainerView: UIView?

    // MARK: Callbacks

    private let onPost: (UIImage) -> Void
    private let onDismiss: () -> Void

    // MARK: - Init

    init(onPost: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
        self.onPost    = onPost
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildStaticUI()
        checkCameraPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backPreviewLayer?.frame = view.bounds

        let pipSize = computePiPSize()
        frontPreviewLayer?.frame = CGRect(origin: .zero, size: pipSize)
        pipWidthConstraint?.constant  = pipSize.width
        pipHeightConstraint?.constant = pipSize.height
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.multiCamSession?.stopRunning()
            self?.fallbackSession?.stopRunning()
        }
    }

    // MARK: - Camera Permission

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCameraSetup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.startCameraSetup() : self?.showPermissionError()
                }
            }
        default:
            showPermissionError()
        }
    }

    private func showPermissionError() {
        let lbl = UILabel()
        lbl.text = "Camera access is required.\n\nGo to Settings → Privacy & Security → Camera → TouchGrass"
        lbl.numberOfLines = 0
        lbl.textAlignment = .center
        lbl.textColor     = .white
        lbl.font          = .systemFont(ofSize: 15)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            lbl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36)
        ])
    }

    // MARK: - Camera Setup (background thread)

    private func startCameraSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if AVCaptureMultiCamSession.isMultiCamSupported {
                self.configureMultiCamSession()
            } else {
                self.configureFallbackSession()
            }
            DispatchQueue.main.async { self.attachPreviewLayers() }
        }
    }

    private func configureMultiCamSession() {
        let s = AVCaptureMultiCamSession()
        s.beginConfiguration()
        defer { s.commitConfiguration(); s.startRunning() }

        // Back camera
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let backIn = try? AVCaptureDeviceInput(device: backCamera),
              s.canAddInput(backIn) else { return }
        s.addInput(backIn)
        backDeviceInput = backIn

        // Back photo output + explicit connection to back port
        guard s.canAddOutput(backPhotoOutput) else { return }
        s.addOutput(backPhotoOutput)
        if let port = backIn.ports(for: .video,
                                    sourceDeviceType: backCamera.deviceType,
                                    sourceDevicePosition: .back).first {
            let conn = AVCaptureConnection(inputPorts: [port], output: backPhotoOutput)
            if s.canAddConnection(conn) { s.addConnection(conn) }
        }

        // Front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let frontIn = try? AVCaptureDeviceInput(device: frontCamera),
              s.canAddInput(frontIn) else { return }
        s.addInput(frontIn)
        frontDeviceInput = frontIn

        // Front photo output + explicit connection to front port
        guard s.canAddOutput(frontPhotoOutput) else { return }
        s.addOutput(frontPhotoOutput)
        if let port = frontIn.ports(for: .video,
                                     sourceDeviceType: frontCamera.deviceType,
                                     sourceDevicePosition: .front).first {
            let conn = AVCaptureConnection(inputPorts: [port], output: frontPhotoOutput)
            if s.canAddConnection(conn) { s.addConnection(conn) }
        }

        multiCamSession = s
        isMultiCam      = true
    }

    private func configureFallbackSession() {
        let s = AVCaptureSession()
        s.sessionPreset = .photo
        s.beginConfiguration()
        defer { s.commitConfiguration(); s.startRunning() }

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let backIn = try? AVCaptureDeviceInput(device: backCamera),
              s.canAddInput(backIn), s.canAddOutput(backPhotoOutput) else { return }
        s.addInput(backIn)
        s.addOutput(backPhotoOutput)
        backDeviceInput = backIn
        fallbackSession = s
        isMultiCam      = false
    }

    // MARK: - Preview Layer Attachment (main thread)

    private func attachPreviewLayers() {
        // --- Back camera (full-screen) ---
        let backLayer = AVCaptureVideoPreviewLayer()
        backLayer.videoGravity = .resizeAspectFill
        backLayer.frame = view.bounds

        if isMultiCam, let ms = multiCamSession, let backIn = backDeviceInput {
            backLayer.setSessionWithNoConnection(ms)
            if let port = backIn.ports(for: .video,
                                        sourceDeviceType: backIn.device.deviceType,
                                        sourceDevicePosition: .back).first {
                let conn = AVCaptureConnection(inputPort: port, videoPreviewLayer: backLayer)
                if ms.canAddConnection(conn) { ms.addConnection(conn) }
            }
        } else if let s = fallbackSession {
            backLayer.session = s
        }

        view.layer.insertSublayer(backLayer, at: 0)
        backPreviewLayer = backLayer

        // --- Front camera (PiP) — only when MultiCam is available ---
        guard isMultiCam,
              let ms = multiCamSession,
              let frontIn = frontDeviceInput else {
            pipContainerView.isHidden = true
            return
        }

        let frontLayer = AVCaptureVideoPreviewLayer()
        frontLayer.videoGravity = .resizeAspectFill

        frontLayer.setSessionWithNoConnection(ms)
        if let port = frontIn.ports(for: .video,
                                     sourceDeviceType: frontIn.device.deviceType,
                                     sourceDevicePosition: .front).first {
            let conn = AVCaptureConnection(inputPort: port, videoPreviewLayer: frontLayer)
            if ms.canAddConnection(conn) { ms.addConnection(conn) }
        }

        let pipSize = computePiPSize()
        frontLayer.frame = CGRect(origin: .zero, size: pipSize)
        pipContainerView.layer.addSublayer(frontLayer)
        frontPreviewLayer = frontLayer
        pipContainerView.isHidden = false
    }

    // MARK: - Static UI

    private func buildStaticUI() {
        // PiP container
        let pipSize = computePiPSize()
        pipContainerView.backgroundColor = UIColor(white: 0.15, alpha: 1)
        pipContainerView.clipsToBounds = true
        pipContainerView.layer.cornerRadius  = 16
        pipContainerView.layer.borderColor   = UIColor.white.cgColor
        pipContainerView.layer.borderWidth   = 2.5
        pipContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pipContainerView)

        pipWidthConstraint  = pipContainerView.widthAnchor.constraint(equalToConstant: pipSize.width)
        pipHeightConstraint = pipContainerView.heightAnchor.constraint(equalToConstant: pipSize.height)
        NSLayoutConstraint.activate([
            pipContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            pipContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pipWidthConstraint!,
            pipHeightConstraint!
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePiPDrag(_:)))
        pipContainerView.addGestureRecognizer(pan)

        // Close button (top-right)
        let xConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closeButton.tintColor        = .white
        closeButton.backgroundColor  = UIColor.white.withAlphaComponent(0.18)
        closeButton.layer.cornerRadius = 21
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 42),
            closeButton.heightAnchor.constraint(equalToConstant: 42)
        ])

        // Capture button (centered at bottom) — outer ring + inner fill
        captureButton.backgroundColor   = .clear
        captureButton.layer.cornerRadius = 40
        captureButton.layer.borderColor  = UIColor.white.cgColor
        captureButton.layer.borderWidth  = 5
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        let innerFill = UIView()
        innerFill.backgroundColor      = .white
        innerFill.layer.cornerRadius   = 31
        innerFill.isUserInteractionEnabled = false
        innerFill.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addSubview(innerFill)
        NSLayoutConstraint.activate([
            innerFill.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            innerFill.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            innerFill.widthAnchor.constraint(equalToConstant: 62),
            innerFill.heightAnchor.constraint(equalToConstant: 62)
        ])

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -36),
            captureButton.widthAnchor.constraint(equalToConstant: 80),
            captureButton.heightAnchor.constraint(equalToConstant: 80)
        ])

        // Hint label
        let hintLabel = UILabel()
        hintLabel.text          = "Both cameras fire at once"
        hintLabel.textColor     = UIColor.white.withAlphaComponent(0.6)
        hintLabel.font          = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -12),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func computePiPSize() -> CGSize {
        let w = max(100, view.bounds.width * 0.32)
        return CGSize(width: w, height: w * (4.0 / 3.0))
    }

    // MARK: - Gestures

    @objc private func handlePiPDrag(_ g: UIPanGestureRecognizer) {
        guard let pip = g.view else { return }
        let t = g.translation(in: view)
        pip.center = CGPoint(x: pip.center.x + t.x, y: pip.center.y + t.y)
        g.setTranslation(.zero, in: view)
    }

    @objc private func closeTapped()   { onDismiss() }

    // MARK: - Capture

    @objc private func captureTapped() {
        captureButton.isEnabled = false
        backPhoto  = nil
        frontPhoto = nil

        if isMultiCam {
            // Enter the group BEFORE firing the outputs
            captureGroup = DispatchGroup()
            captureGroup.enter()   // back
            captureGroup.enter()   // front
            backPhotoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            frontPhotoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            captureGroup.notify(queue: .main) { [weak self] in self?.showPreview() }
        } else {
            backPhotoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { if isMultiCam { captureGroup.leave() } }

        guard error == nil,
              let data  = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let corrected = fixOrientation(image)

        if output === backPhotoOutput {
            backPhoto = corrected
        } else {
            frontPhoto = mirror(corrected)   // front cam needs horizontal flip
        }

        if !isMultiCam {
            DispatchQueue.main.async { self.showPreview() }
        }
    }

    // MARK: - Preview Screen

    private func showPreview() {
        guard let back = backPhoto else { captureButton.isEnabled = true; return }

        // Hide live-camera UI so the AVCaptureVideoPreviewLayer (GPU-composited)
        // can't render on top of the preview screen.
        pipContainerView.isHidden = true
        captureButton.isHidden    = true
        closeButton.isHidden      = true

        let composite: UIImage
        if let front = frontPhoto {
            composite = createComposite(back: back, front: front)
        } else {
            composite = back
        }
        pendingComposite = composite

        // Full-screen overlay container
        let container = UIView()
        container.backgroundColor = .black
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        previewContainerView = container

        // Story image
        let imageView = UIImageView(image: composite)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Semi-transparent bottom bar
        let bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.52)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Button row
        let stack = UIStackView()
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            stack.heightAnchor.constraint(equalToConstant: 54)
        ])

        let retakeBtn = makeButton(title: "Retake",     bg: UIColor.white.withAlphaComponent(0.18))
        let postBtn   = makeButton(title: "Post Story", bg: UIColor(red: 0.10, green: 0.75, blue: 0.32, alpha: 1))
        retakeBtn.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        postBtn.addTarget(self,   action: #selector(postTapped),   for: .touchUpInside)
        stack.addArrangedSubview(retakeBtn)
        stack.addArrangedSubview(postBtn)
    }

    @objc private func retakeTapped() {
        previewContainerView?.removeFromSuperview()
        previewContainerView = nil
        backPhoto  = nil
        frontPhoto = nil
        pendingComposite = nil

        // Restore live-camera UI
        pipContainerView.isHidden = !isMultiCam  // only show PiP if dual-cam is active
        captureButton.isHidden    = false
        captureButton.isEnabled   = true
        closeButton.isHidden      = false
    }

    @objc private func postTapped() {
        guard let composite = pendingComposite else { return }
        onPost(composite)
    }

    // MARK: - Composite Image

    /// Overlays the front-camera image as a smaller rounded-rect PiP in the
    /// top-left corner of the back-camera image, matching BeReal's style.
    private func createComposite(back: UIImage, front: UIImage) -> UIImage {
        let sz = CGSize(width: back.size.width  * back.scale,
                        height: back.size.height * back.scale)

        let pipW: CGFloat = sz.width  * 0.32
        let pipH: CGFloat = sz.height * 0.32
        let margin: CGFloat = sz.width * 0.035
        let radius: CGFloat = pipW * 0.12
        let pipRect = CGRect(x: margin, y: margin, width: pipW, height: pipH)

        let format   = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: sz, format: format).image { ctx in
            // 1 — back photo
            back.draw(in: CGRect(origin: .zero, size: sz))

            // 2 — front photo clipped to rounded rect
            ctx.cgContext.saveGState()
            UIBezierPath(roundedRect: pipRect, cornerRadius: radius).addClip()
            front.draw(in: pipRect)
            ctx.cgContext.restoreGState()

            // 3 — white border around PiP
            let borderRect = pipRect.insetBy(dx: -3, dy: -3)
            let border = UIBezierPath(roundedRect: borderRect, cornerRadius: radius + 3)
            border.lineWidth = 6
            UIColor.white.setStroke()
            border.stroke()
        }
    }

    // MARK: - Image Utilities

    private func fixOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private func mirror(_ image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: image.size.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - UIKit Helpers

    private func makeButton(title: String, bg: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor   = bg
        btn.layer.cornerRadius = 27
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }
}
