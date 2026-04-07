//
//  MapScreen.swift
//  TouchGrass
//

import SwiftUI
import MapKit
import CoreLocation
import Observation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Friend Model
struct Friend: Identifiable {
    let id = UUID()
    var uid: String = ""         // Firebase UID (empty for demo/placeholder entries)
    let name: String
    var coordinate: CLLocationCoordinate2D
    var stepScore: Int = 0
    var isPinned: Bool = false
    var streak: Int = 0          // Consecutive daily-win streak
}

// MARK: - ViewModel for Location & Friends
@Observable
class MapViewModel: NSObject, CLLocationManagerDelegate {
    var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    var userLocation: CLLocationCoordinate2D?
    var friends: [Friend] = []

    private let locationManager = CLLocationManager()
    private let db = Firestore.firestore()
    private var friendListeners: [ListenerRegistration] = []
    private var lastUploadedLocation: CLLocation?
    private var lastLocationUpload: Date = .distantPast
    private var hasSetInitialPosition = false

    override init() {
        super.init()

        // Restore last known position so the map never cold-starts at San Francisco
        let cachedLat = UserDefaults.standard.double(forKey: "lastUserLatitude")
        let cachedLng = UserDefaults.standard.double(forKey: "lastUserLongitude")
        if cachedLat != 0 || cachedLng != 0 {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: cachedLat, longitude: cachedLng),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startFriendLocationListeners()
    }

    deinit {
        stopFriendLocationListeners()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            // Only center the map on the very first fix so the user can freely pan
            if !self.hasSetInitialPosition {
                self.hasSetInitialPosition = true
                self.position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }

        // Throttle Firestore writes: upload only when moved >10 m or 30 s have elapsed
        let movedEnough = lastUploadedLocation.map { location.distance(from: $0) > 10 } ?? true
        let enoughTimeElapsed = Date().timeIntervalSince(lastLocationUpload) > 30
        if movedEnough || enoughTimeElapsed {
            lastUploadedLocation = location
            lastLocationUpload = Date()
            UserDefaults.standard.set(location.coordinate.latitude, forKey: "lastUserLatitude")
            UserDefaults.standard.set(location.coordinate.longitude, forKey: "lastUserLongitude")
            Task { await UserService.shared.updateLocation(location.coordinate) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    // MARK: - Real-Time Friend Locations

    /// Fetches accepted friend UIDs and attaches a Firestore snapshot listener to
    /// each friend's user document. The map updates automatically whenever a
    /// friend's location (or other fields) changes in Firestore.
    func startFriendLocationListeners() {
        Task {
            let uids = (try? await FriendService.shared.friendUIDs()) ?? []
            let pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: "pinnedFriendIDs") ?? [])

            for uid in uids {
                let listener = db.collection("users").document(uid)
                    .addSnapshotListener { [weak self] snapshot, error in
                        guard let self,
                              let data = snapshot?.data(),
                              let username = data["username"] as? String else { return }

                        let lat = data["latitude"] as? Double ?? 0
                        let lng = data["longitude"] as? Double ?? 0

                        let friend = Friend(
                            uid: uid,
                            name: username,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            stepScore: data["stepScore"] as? Int ?? 0,
                            isPinned: pinnedIDs.contains(uid),
                            streak: data["dailyStreak"] as? Int ?? 0
                        )

                        DispatchQueue.main.async {
                            if let idx = self.friends.firstIndex(where: { $0.uid == uid }) {
                                self.friends[idx] = friend
                            } else {
                                self.friends.append(friend)
                            }
                        }
                    }
                await MainActor.run { self.friendListeners.append(listener) }
            }
        }
    }

    func stopFriendLocationListeners() {
        friendListeners.forEach { $0.remove() }
        friendListeners.removeAll()
    }
}

// MARK: - Map Avatar View

struct MapAvatarView: View {
    let uid: String
    let name: String
    let borderColor: Color

    @State private var profileImage: UIImage? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: name))
                .frame(width: 44, height: 44)
            if let img = profileImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .overlay(Circle().stroke(borderColor, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .task(id: uid) {
            if let cached = FriendRow.imageCache[uid] {
                profileImage = cached
                return
            }
            let ref = Storage.storage().reference().child("profile_images/\(uid).jpg")
            guard let data = try? await ref.data(maxSize: 5 * 1024 * 1024),
                  let image = UIImage(data: data) else { return }
            FriendRow.imageCache[uid] = image
            profileImage = image
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Map View
struct MapScreen: View {
    @State var viewModel: MapViewModel
    private let stepManager = StepCounterManager.shared

    @State private var currentUID: String? = Auth.auth().currentUser?.uid
    @State private var currentUsername: String = ""

    // Only show friends who have a real GPS fix (lat/lng both non-zero)
    private var friendsOnMap: [Friend] {
        viewModel.friends.filter { $0.coordinate.latitude != 0 || $0.coordinate.longitude != 0 }
    }

    var body: some View {
        ZStack {
            Map(position: $viewModel.position) {
                // Current user annotation
                if let loc = viewModel.userLocation, let uid = currentUID, !currentUsername.isEmpty {
                    Annotation("You", coordinate: loc) {
                        VStack(spacing: 2) {
                            MapAvatarView(uid: uid, name: currentUsername, borderColor: .green)
                            Text("You")
                                .font(.caption)
                                .padding(2)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(5)
                        }
                    }
                } else {
                    UserAnnotation()
                }
                ForEach(friendsOnMap) { friend in
                    Annotation(friend.name, coordinate: friend.coordinate) {
                        VStack(spacing: 2) {
                            MapAvatarView(uid: friend.uid, name: friend.name, borderColor: .white)
                            Text(friend.name)
                                .font(.caption)
                                .padding(2)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(5)
                        }
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            .task {
                if let user = try? await UserService.shared.fetchCurrentUser() {
                    currentUsername = user.username
                }
            }

            // Step counter overlay
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.green)
                        Text("Steps: \(stepManager.dailySteps)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(GlassBackground(cornerRadius: 12, showReflection: true))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    MapScreen(viewModel: MapViewModel())
}
