//
//  EditProfileView.swift
//  TouchGrass
//

import SwiftUI
import PhotosUI

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileManager = ProfileImageManager.shared

    @State private var selectedItem: PhotosPickerItem?
    @State private var rawImage: UIImage?
    @State private var showCrop = false
    @State private var showPhotoError = false

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

                // Photo picker
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("Choose Photo")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)
                .onChange(of: selectedItem) { _, item in
                    Task {
                        guard let item else { return }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data) else {
                                showPhotoError = true
                                return
                            }
                            rawImage = image
                            showCrop = true
                        } catch {
                            showPhotoError = true
                        }
                    }
                }

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
        .alert("Couldn't Load Photo", isPresented: $showPhotoError) {
            Button("OK") {}
        } message: {
            Text("The selected photo could not be loaded. Please try another.")
        }
        .fullScreenCover(isPresented: $showCrop) {
            if let raw = rawImage {
                ImageCropView(image: raw) { cropped in
                    profileManager.saveImage(cropped)
                    showCrop = false
                } onCancel: {
                    showCrop = false
                }
            }
        }
    }
}

// MARK: - Image Crop View

struct ImageCropView: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropSize: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .clipped()

                CropOverlayView(cropSize: cropSize)

                VStack {
                    HStack {
                        Button("Cancel") { onCancel() }
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                        Button {
                            let cropped = cropImage(containerSize: geo.size)
                            onSave(cropped)
                        } label: {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func cropImage(containerSize: CGSize) -> UIImage {
        let outputSize = CGSize(width: cropSize, height: cropSize)
        let renderer = UIGraphicsImageRenderer(size: outputSize)

        return renderer.image { _ in
            // Scale factor so the image fills the container
            let fillScale = max(
                containerSize.width / image.size.width,
                containerSize.height / image.size.height
            )

            // Image size after fill scale + user-applied scale
            let displayedW = image.size.width * fillScale * scale
            let displayedH = image.size.height * fillScale * scale

            // Image top-left in container coordinates (centered, then offset)
            let imageX = (containerSize.width - displayedW) / 2 + offset.width
            let imageY = (containerSize.height - displayedH) / 2 + offset.height

            // Crop circle top-left in container coordinates
            let cropX = (containerSize.width - cropSize) / 2
            let cropY = (containerSize.height - cropSize) / 2

            // Image position relative to the crop area
            let drawX = imageX - cropX
            let drawY = imageY - cropY

            let clipPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: outputSize))
            clipPath.addClip()

            image.draw(in: CGRect(x: drawX, y: drawY, width: displayedW, height: displayedH))
        }
    }
}

// MARK: - Crop Overlay

struct CropOverlayView: View {
    let cropSize: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
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
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: cropSize, height: cropSize)
        }
        .allowsHitTesting(false)
    }
}
