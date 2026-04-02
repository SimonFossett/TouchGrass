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
    @State private var showChangeUsername = false
    @State private var newUsernameInput = ""
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
                            rawImage = downsampledImage(image)
                            showCrop = true
                        } catch {
                            showPhotoError = true
                        }
                    }
                }

                // Change username button
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
                                Text("Save Username")
                                    .fontWeight(.semibold)
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
        .overlay {
            if showCrop, let raw = rawImage {
                ImageCropView(image: raw) { cropped in
                    profileManager.saveImage(cropped)
                    showCrop = false
                } onCancel: {
                    showCrop = false
                }
                .ignoresSafeArea()
            }
        }
    }
}

private func downsampledImage(_ image: UIImage, maxDimension: CGFloat = 1500) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > maxDimension else { return image }
    let scale = maxDimension / longest
    let newSize = CGSize(width: (image.size.width * scale).rounded(),
                         height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
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
                    Spacer()

                    // Zoom controls
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                scale = max(1.0, scale - 0.25)
                                lastScale = scale
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 40)
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1, height: 24)

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                scale = min(5.0, scale + 0.25)
                                lastScale = scale
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 40)
                        }
                    }
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 20)
                                .fill(LinearGradient(
                                    colors: [.white.opacity(0.18), .white.opacity(0.02), .clear],
                                    startPoint: .topLeading, endPoint: .center
                                ))
                                .blendMode(.screen)
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.1), .clear, .white.opacity(0.12)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ), lineWidth: 1.5)
                        }
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.bottom, 16)

                    HStack(spacing: 20) {
                        Button("Cancel") { onCancel() }
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 48)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color.white.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(LinearGradient(
                                            colors: [.white.opacity(0.18), .white.opacity(0.02), .clear],
                                            startPoint: .topLeading, endPoint: .center
                                        ))
                                        .blendMode(.screen)
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(LinearGradient(
                                            colors: [.white.opacity(0.35), .white.opacity(0.1), .clear, .white.opacity(0.12)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ), lineWidth: 1.5)
                                }
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                        Button {
                            let cropped = cropImage(containerSize: geo.size)
                            onSave(cropped)
                        } label: {
                            Text("Save")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 48)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.green.opacity(0.7))
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(LinearGradient(
                                                colors: [.white.opacity(0.18), .white.opacity(0.02), .clear],
                                                startPoint: .topLeading, endPoint: .center
                                            ))
                                            .blendMode(.screen)
                                        RoundedRectangle(cornerRadius: 24)
                                            .stroke(LinearGradient(
                                                colors: [.white.opacity(0.35), .white.opacity(0.1), .clear, .white.opacity(0.12)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ), lineWidth: 1.5)
                                    }
                                )
                                .shadow(color: Color.green.opacity(0.4), radius: 8, y: 4)
                        }
                    }
                    .padding(.bottom, 50)
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
