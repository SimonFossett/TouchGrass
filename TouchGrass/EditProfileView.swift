//
//  EditProfileView.swift
//  TouchGrass
//

import SwiftUI
import Photos

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileManager = ProfileImageManager.shared

    @State private var showPhotoPicker    = false
    @State private var showPhotoError     = false
    @State private var showChangeUsername = false
    @State private var newUsernameInput   = ""
    @State private var isChangingUsername = false
    @State private var usernameChangeError: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Current profile picture preview
                ZStack {
                    if let img = profileManager.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(UIColor.systemGray3))
                            .frame(width: 120, height: 120)
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 20)

                // Open the split crop+library picker
                Button {
                    showPhotoPicker = true
                } label: {
                    Text("Choose Photo")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)

                // Change username
                Button {
                    newUsernameInput = ""
                    showChangeUsername = true
                } label: {
                    Text("Change Username")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(UIColor.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)

                Spacer()
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Split crop+library picker
        .fullScreenCover(isPresented: $showPhotoPicker) {
            CircularPhotoPicker(isPresented: $showPhotoPicker) { cropped in
                profileManager.saveImage(cropped)
            }
        }
        // Change username sheet
        .sheet(isPresented: $showChangeUsername) {
            NavigationStack {
                VStack(spacing: 24) {
                    Text("Enter a new username (min. 3 characters).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)

                    TextField("New username", text: $newUsernameInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal, 30)

                    Button {
                        isChangingUsername = true
                        Task {
                            do {
                                try await UserService.shared.changeUsername(to: newUsernameInput)
                                isChangingUsername = false
                                showChangeUsername = false
                            } catch {
                                usernameChangeError = error.localizedDescription
                                isChangingUsername = false
                            }
                        }
                    } label: {
                        Group {
                            if isChangingUsername {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save Username").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(newUsernameInput.trimmingCharacters(in: .whitespaces).count < 3 || isChangingUsername)
                    .padding(.horizontal, 30)

                    Spacer()
                }
                .padding(.top, 24)
                .navigationTitle("Change Username")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showChangeUsername = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Couldn't Load Photo", isPresented: $showPhotoError) {
            Button("OK") {}
        } message: {
            Text("The selected photo could not be loaded. Please try another.")
        }
        .alert("Username Error", isPresented: Binding(
            get: { usernameChangeError != nil },
            set: { if !$0 { usernameChangeError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(usernameChangeError ?? "")
        }
    }
}

// MARK: - Circular Photo Picker
// Split-screen: image preview with circle crop mask on top,
// scrollable photo library grid on the bottom.

struct CircularPhotoPicker: View {
    @Binding var isPresented: Bool
    let onSave: (UIImage) -> Void
    @Environment(\.displayScale) private var displayScale

    @State private var assets: [PHAsset]  = []
    @State private var authStatus: PHAuthorizationStatus = .notDetermined

    @State private var selectedImage: UIImage?  = nil
    @State private var selectedID: String?      = nil
    @State private var isLoadingFull            = false

    // Stable preview size — set once from GeometryReader, used by crop math
    @State private var previewSize: CGFloat = 1

    // Pan & zoom state
    @State private var scale:  CGFloat = 1.0
    @State private var offset: CGSize  = .zero

    private let imageManager = PHCachingImageManager()

    var body: some View {
        // Nav bar lives OUTSIDE the GeometryReader so no child view
        // (ScrollView, image gesture, etc.) can ever overlap or intercept it.
        VStack(spacing: 0) {

            // MARK: Nav bar
            HStack {
                Button("Cancel") { isPresented = false }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))

                Spacer()

                Text("Library")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button("Done") {
                    guard let img = selectedImage else { return }
                    let cropped = cropImage(img, previewSize: previewSize)
                    onSave(cropped)
                    isPresented = false
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(selectedImage != nil ? .white : .white.opacity(0.35))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    selectedImage != nil
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .disabled(selectedImage == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black)

            // MARK: Content (GeometryReader used only for size)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    previewArea(previewSize: previewSize)
                    sectionHeader
                    photoGrid(geo: geo)
                }
                .onAppear { previewSize = max(geo.size.width, 1) }
                .task { await requestAndLoad(previewSize: max(geo.size.width, 1)) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: Preview area (image + circle crop overlay)

    private func previewArea(previewSize: CGFloat) -> some View {
        ZStack {
            Color.black

            if isLoadingFull {
                ProgressView().tint(.white)
            } else if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewSize, height: previewSize)
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)
                    .clipped()
                    .allowsHitTesting(false)
            }

            // Dim outside the circle
            CropOverlayView(cropSize: previewSize)
        }
        .frame(width: previewSize, height: previewSize)
        .clipped()
        // UIKit gesture recognizers are used here instead of SwiftUI gestures
        // because UIKit recognizers are strictly bounded to their UIView's frame
        // and cannot leak into sibling views (e.g. the nav bar buttons above).
        .overlay(
            GestureCapture(scale: $scale, offset: $offset) {
                clampOffset(previewSize: previewSize)
            }
        )
    }

    // MARK: "Recents >" header

    private var sectionHeader: some View {
        HStack(spacing: 4) {
            Text("Recents")
                .font(.system(size: 16, weight: .bold))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    // MARK: Photo grid

    private func photoGrid(geo: GeometryProxy) -> some View {
        let cols  = 4
        let gap   = CGFloat(1)
        let thumb = (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)

        return Group {
            if authStatus == .denied || authStatus == .restricted {
                VStack(spacing: 12) {
                    Text("Photo library access is required.")
                        .foregroundStyle(.white)
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(thumb), spacing: gap), count: cols),
                        spacing: gap
                    ) {
                        // Camera placeholder (first cell)
                        ZStack {
                            Color(UIColor.systemGray6)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(width: thumb, height: thumb)

                        ForEach(assets, id: \.localIdentifier) { asset in
                            PhotoThumbnailCell(
                                asset: asset,
                                size: thumb,
                                isSelected: asset.localIdentifier == selectedID,
                                imageManager: imageManager
                            ) {
                                selectAsset(asset, previewSize: geo.size.width)
                            }
                        }
                    }
                }
                .background(Color.black)
            }
        }
    }

    // MARK: - Actions

    private func selectAsset(_ asset: PHAsset, previewSize: CGFloat) {
        guard asset.localIdentifier != selectedID else { return }
        selectedID     = asset.localIdentifier
        isLoadingFull  = true
        scale      = 1.0; lastScale  = 1.0
        offset     = .zero; lastOffset = .zero

        let px = previewSize * displayScale
        let options = PHImageRequestOptions()
        options.deliveryMode        = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous       = false

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: px * 1.5, height: px * 1.5),
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in
                selectedImage = downsampledImage(image)
                if !degraded { isLoadingFull = false }
            }
        }
    }

    /// Constrain pan so the circle (= previewSize diameter) is always fully covered.
    private func clampOffset(previewSize: CGFloat) {
        let maxPan = (previewSize * scale - previewSize) / 2
        let clamped = CGSize(
            width:  min(max(offset.width,  -maxPan), maxPan),
            height: min(max(offset.height, -maxPan), maxPan)
        )
        withAnimation(.interactiveSpring(response: 0.2)) { offset = clamped }
    }

    // MARK: - Crop math

    private func cropImage(_ image: UIImage, previewSize: CGFloat) -> UIImage {
        let outputPt: CGFloat = 600          // output is 600 pt square
        let ratio = outputPt / previewSize   // scale all coordinates to output space

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputPt, height: outputPt))
        return renderer.image { _ in
            // Base fill scale: image fills the previewSize × previewSize square
            let fillW = previewSize / image.size.width
            let fillH = previewSize / image.size.height
            let fill  = max(fillW, fillH)

            let dW = image.size.width  * fill * scale * ratio
            let dH = image.size.height * fill * scale * ratio

            let dX = ((previewSize - image.size.width  * fill * scale) / 2 + offset.width)  * ratio
            let dY = ((previewSize - image.size.height * fill * scale) / 2 + offset.height) * ratio

            UIBezierPath(ovalIn: CGRect(origin: .zero, size: CGSize(width: outputPt, height: outputPt))).addClip()
            image.draw(in: CGRect(x: dX, y: dY, width: dW, height: dH))
        }
    }

    // MARK: - Photo library

    private func requestAndLoad(previewSize: CGFloat) async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authStatus = current == .notDetermined
            ? await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            : current

        guard authStatus == .authorized || authStatus == .limited else { return }

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 200

        var fetched: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: opts)
            .enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched

        if let first = fetched.first {
            selectAsset(first, previewSize: previewSize)
        }
    }
}

// MARK: - Photo Thumbnail Cell

private struct PhotoThumbnailCell: View {
    let asset: PHAsset
    let size: CGFloat
    let isSelected: Bool
    let imageManager: PHCachingImageManager
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(UIColor.systemGray5)
                }
            }
            .frame(width: size, height: size)
            .clipped()

            if isSelected {
                Color.black.opacity(0.25).frame(width: size, height: size)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .onTapGesture { onTap() }
        .task(id: asset.localIdentifier) { await loadThumb() }
    }

    private func loadThumb() async {
        let px = size * displayScale
        let opts = PHImageRequestOptions()
        opts.deliveryMode           = .fastFormat
        opts.resizeMode             = .fast
        opts.isNetworkAccessAllowed = true

        thumbnail = await withCheckedContinuation { cont in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: px, height: px),
                contentMode: .aspectFill,
                options: opts
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }
        }
    }
}

// MARK: - Crop Overlay

struct CropOverlayView: View {
    let cropSize: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .mask(
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: cropSize, height: cropSize)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                .frame(width: cropSize, height: cropSize)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - UIKit Gesture Capture
// A transparent UIView overlay that handles pinch and pan via UIKit gesture
// recognizers. UIKit recognizers are strictly bounded to their UIView frame
// and cannot intercept touches that start outside it — unlike SwiftUI gestures
// which can leak through contentShape in certain hierarchy configurations.

private struct GestureCapture: UIViewRepresentable {
    @Binding var scale:  CGFloat
    @Binding var offset: CGSize
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handlePinch(_:)))
        let pan   = UIPanGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pinch.delegate = context.coordinator
        pan.delegate   = context.coordinator

        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Capture bindings by value — Binding<T> holds a reference to the
        // backing State storage, so the closures always read/write current values.
        let scaleB  = _scale
        let offsetB = _offset
        let endCb   = onEnd
        context.coordinator.getScale  = { scaleB.wrappedValue }
        context.coordinator.getOffset = { offsetB.wrappedValue }
        context.coordinator.setScale  = { scaleB.wrappedValue  = $0 }
        context.coordinator.setOffset = { offsetB.wrappedValue = $0 }
        context.coordinator.onEnd     = endCb
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var getScale:  () -> CGFloat       = { 1 }
        var getOffset: () -> CGSize        = { .zero }
        var setScale:  (CGFloat) -> Void   = { _ in }
        var setOffset: (CGSize)  -> Void   = { _ in }
        var onEnd:     () -> Void          = {}

        private var startScale:  CGFloat = 1
        private var startOffset: CGSize  = .zero

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                startScale = getScale()
            case .changed:
                setScale(max(1.0, startScale * g.scale))
            case .ended, .cancelled:
                onEnd()
            default: break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .began:
                startOffset = getOffset()
            case .changed:
                setOffset(CGSize(width:  startOffset.width  + t.x,
                                 height: startOffset.height + t.y))
            case .ended, .cancelled:
                onEnd()
            default: break
            }
        }
    }
}

// MARK: - Helpers

private func downsampledImage(_ image: UIImage, maxDimension: CGFloat = 1500) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension else { return image }
    let scale = maxDimension / longest
    let newSize = CGSize(width: (image.size.width  * scale).rounded(),
                         height: (image.size.height * scale).rounded())
    let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
    return UIGraphicsImageRenderer(size: newSize, format: fmt).image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
}
