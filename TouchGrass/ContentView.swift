//
//  ContentView.swift
//  TouchGrass
//
//  Created by Simon Fossett on 3/15/26.
//

import SwiftUI
import MapKit
import CoreMotion
import FirebaseAuth
import FirebaseFirestore

// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedTab: Tab = .home
    private let firebase = FirebaseManager.shared

    var body: some View {
        if firebase.isAuthenticated {
            mainApp
        } else {
            AuthView()
        }
    }

    var mainApp: some View {
        VStack(spacing: 0) {
            ZStack {
                switch selectedTab {
                case .home:
                    HomeView()
                case .search:
                    SearchView()
                case .map:
                    MapView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tab bar
            HStack {
                TabBarButton(tab: .home, selectedTab: $selectedTab, systemIconName: "house")
                Spacer()
                TabBarButton(tab: .search, selectedTab: $selectedTab, systemIconName: "magnifyingglass")
                Spacer()
                TabBarButton(tab: .map, selectedTab: $selectedTab, systemIconName: "map")
                Spacer()
                TabBarButton(tab: .profile, selectedTab: $selectedTab, systemIconName: "person")
            }
            .padding(.horizontal, 50)
            .padding(.vertical, 18)
            .background(Color(UIColor.systemGray6))
        }
        .edgesIgnoringSafeArea(.bottom)
        .task { checkMotionPermission() }
        .sheet(isPresented: $showMotionSheet) {
            MotionPermissionSheet(isDenied: motionPermissionDenied)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Motion Permission

    @State private var showMotionSheet = false
    @State private var motionPermissionDenied = false

    private func checkMotionPermission() {
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            motionPermissionDenied = true
            showMotionSheet = true
        case .notDetermined:
            if !UserDefaults.standard.bool(forKey: "hasShownMotionPrompt") {
                motionPermissionDenied = false
                showMotionSheet = true
            }
        default:
            break
        }
    }
}

// MARK: - Tab Enum
enum Tab {
    case home, search, map, profile
}

// MARK: - Tab Bar Button
struct TabBarButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab
    let systemIconName: String

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            Image(systemName: systemIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundColor(selectedTab == tab ? .blue : .gray)
        }
    }
}

// MARK: - Home View Model

@Observable
class HomeViewModel {
    var friends: [Friend] = []
    var pendingRequests: [AppUser] = []
    var isLoading = true
    var errorMessage: String? = nil

    private let db = Firestore.firestore()
    private var incomingDocs: [QueryDocumentSnapshot] = []
    private var outgoingDocs: [QueryDocumentSnapshot] = []
    private var requestListeners: [ListenerRegistration] = []
    private var friendDocListeners: [String: ListenerRegistration] = [:]

    init() { startRequestListeners() }
    deinit { stopAll() }

    // MARK: Listeners

    private func startRequestListeners() {
        guard let myUID = Auth.auth().currentUser?.uid else { isLoading = false; return }

        let incoming = db.collection("friendRequests")
            .whereField("toUID", isEqualTo: myUID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription; return }
                self.incomingDocs = snapshot?.documents ?? []
                Task { await self.recomputeState() }
            }

        let outgoing = db.collection("friendRequests")
            .whereField("fromUID", isEqualTo: myUID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription; return }
                self.outgoingDocs = snapshot?.documents ?? []
                Task { await self.recomputeState() }
            }

        requestListeners = [incoming, outgoing]
    }

    func refresh() {
        stopAll()
        friends = []
        pendingRequests = []
        isLoading = true
        startRequestListeners()
    }

    // MARK: State derivation

    private func recomputeState() async {
        var pendingUIDs: [String] = []
        var currentFriendUIDs: [String] = []

        for doc in incomingDocs {
            let status  = doc.data()["status"]  as? String ?? ""
            let fromUID = doc.data()["fromUID"] as? String ?? ""
            guard !fromUID.isEmpty else { continue }
            if status == "pending"  { pendingUIDs.append(fromUID) }
            else if status == "accepted" { currentFriendUIDs.append(fromUID) }
        }
        for doc in outgoingDocs {
            let status = doc.data()["status"] as? String ?? ""
            let toUID  = doc.data()["toUID"]  as? String ?? ""
            guard !toUID.isEmpty else { continue }
            if status == "accepted" { currentFriendUIDs.append(toUID) }
        }

        // Fetch display data for pending request senders
        var users: [AppUser] = []
        for uid in pendingUIDs {
            if let doc = try? await db.collection("users").document(uid).getDocument(),
               let username = doc.data()?["username"] as? String {
                users.append(AppUser(id: uid, username: username,
                                     stepScore: doc.data()?["stepScore"] as? Int ?? 0))
            }
        }
        pendingRequests = users

        // Sync per-friend document listeners
        let newSet      = Set(currentFriendUIDs)
        let listeningSet = Set(friendDocListeners.keys)

        for uid in listeningSet.subtracting(newSet) {
            friendDocListeners[uid]?.remove()
            friendDocListeners.removeValue(forKey: uid)
            friends.removeAll { $0.uid == uid }
        }
        let pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: "pinnedFriendIDs") ?? [])
        for uid in newSet.subtracting(listeningSet) {
            attachFriendListener(uid: uid, pinnedIDs: pinnedIDs)
        }

        if isLoading { isLoading = false }
    }

    private func attachFriendListener(uid: String, pinnedIDs: Set<String>) {
        let listener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self,
                      let data = snapshot?.data(),
                      let username = data["username"] as? String else { return }
                let lat    = data["latitude"]  as? Double ?? 0
                let lng    = data["longitude"] as? Double ?? 0
                let pinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedFriendIDs") ?? [])
                let friend = Friend(
                    uid: uid,
                    name: username,
                    coordinate: .init(latitude: lat, longitude: lng),
                    stepScore: data["stepScore"]   as? Int ?? 0,
                    isPinned:  pinned.contains(uid),
                    streak:    data["dailyStreak"] as? Int ?? 0
                )
                if let idx = self.friends.firstIndex(where: { $0.uid == uid }) {
                    self.friends[idx] = friend
                } else {
                    self.friends.append(friend)
                }
            }
        friendDocListeners[uid] = listener
    }

    // MARK: Actions

    func acceptRequest(from uid: String) {
        Task {
            do { try await FriendService.shared.acceptRequest(from: uid) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func declineRequest(from uid: String) {
        Task {
            do { try await FriendService.shared.denyRequest(from: uid) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func removeFriend(uid: String) {
        Task {
            do { try await FriendService.shared.removeFriend(uid) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func togglePin(uid: String) {
        guard let idx = friends.firstIndex(where: { $0.uid == uid }) else { return }
        friends[idx].isPinned.toggle()
        let isPinned = friends[idx].isPinned
        var pinned = Set(UserDefaults.standard.stringArray(forKey: "pinnedFriendIDs") ?? [])
        if isPinned { pinned.insert(uid) } else { pinned.remove(uid) }
        UserDefaults.standard.set(Array(pinned), forKey: "pinnedFriendIDs")
    }

    private func stopAll() {
        requestListeners.forEach { $0.remove() }
        friendDocListeners.values.forEach { $0.remove() }
        requestListeners.removeAll()
        friendDocListeners.removeAll()
    }
}

// MARK: - Home View
struct HomeView: View {
    @State private var searchText: String = ""
    @State private var viewModel = HomeViewModel()
    @State private var selectedFriend: Friend? = nil
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    private let profileManager = ProfileImageManager.shared

    var filteredFriends: [Friend] {
        let pinned   = viewModel.friends.filter {  $0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let unpinned = viewModel.friends.filter { !$0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let all = pinned + unpinned
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.lowercased().hasPrefix(searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: profile picture + search bar
            HStack(spacing: 12) {
                // Profile picture button
                Button {
                    showProfileMenu = true
                } label: {
                    if let img = profileManager.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(UIColor.systemGray3))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            )
                    }
                }
                .confirmationDialog("", isPresented: $showProfileMenu, titleVisibility: .hidden) {
                    Button("Edit Profile") { showEditProfile = true }
                    Button("Sign Out", role: .destructive) {
                        ProfileImageManager.shared.clearImage()
                        do {
                            try FirebaseManager.shared.signOut()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search friends...", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray5))

            // Friends list
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {

                        // MARK: Pending friend requests (always at top)
                        if !viewModel.pendingRequests.isEmpty {
                            SectionHeader(title: "Friend Requests")
                            ForEach(viewModel.pendingRequests) { user in
                                FriendRequestRow(user: user) {
                                    viewModel.acceptRequest(from: user.id)
                                } onDecline: {
                                    viewModel.declineRequest(from: user.id)
                                }
                                Divider().padding(.leading, 74)
                            }
                            SectionHeader(title: "Friends")
                        }

                        // MARK: Regular friends list
                        if viewModel.friends.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray.opacity(0.4))
                                Text("No friends yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Search for users to add friends")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 60)
                        } else {
                            ForEach(filteredFriends) { friend in
                                FriendRow(friend: friend)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedFriend = friend
                                    }
                                Divider()
                                    .padding(.leading, 74)
                            }
                        }
                    }
                }
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
        .sheet(item: $selectedFriend) { friend in
            FriendDetailSheet(friend: friend) {
                viewModel.togglePin(uid: friend.uid)
                selectedFriend = nil
            } onRemove: {
                viewModel.removeFriend(uid: friend.uid)
                selectedFriend = nil
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 16)
                .padding(.vertical, 6)
            Spacer()
        }
        .background(Color(UIColor.systemGray6))
    }
}

// MARK: - Friend Request Row

struct FriendRequestRow: View {
    let user: AppUser
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 52, height: 52)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.system(size: 16, weight: .semibold))
                Text("Wants to connect")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.systemGray3))
                        .clipShape(Circle())
                }
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.green)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Friend Row
struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.name))
                    .frame(width: 52, height: 52)
                Text(String(friend.name.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if friend.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Text(friend.name)
                        .font(.system(size: 16, weight: .semibold))
                }
            }

            Spacer()

            // Streak fire icon
            if friend.streak > 0 {
                StreakBadge(streak: friend.streak)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Streak Badge

struct StreakBadge: View {
    let streak: Int

    var body: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            Text("\(streak)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .offset(y: 4)
        }
        .frame(width: 32, height: 36)
    }
}

// MARK: - Friend Detail Sheet
struct FriendDetailSheet: View {
    let friend: Friend
    let onPin: () -> Void
    let onRemove: () -> Void

    @State private var showRemoveConfirm = false

    var body: some View {
        VStack(spacing: 24) {
            // Enlarged profile picture
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.name))
                    .frame(width: 100, height: 100)
                Text(String(friend.name.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 30)

            Text(friend.name)
                .font(.title2)
                .fontWeight(.bold)

            // Step score
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundColor(.green)
                Text("Step Score: \(friend.stepScore)")
                    .font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)

            // Pin / Unpin button
            Button(action: onPin) {
                HStack {
                    Image(systemName: friend.isPinned ? "pin.slash.fill" : "pin.fill")
                    Text(friend.isPinned ? "Unpin Friend" : "Pin to Top")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(friend.isPinned ? Color(UIColor.systemGray4) : Color.orange)
                .foregroundColor(friend.isPinned ? .primary : .white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 30)

            // Remove Friend button
            Button {
                showRemoveConfirm = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.minus")
                    Text("Remove Friend")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            .confirmationDialog(
                "Remove \(friend.name)?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove Friend", role: .destructive) { onRemove() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(friend.name) will be removed from your friends list and won't see you on theirs.")
            }

            Spacer()
        }
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Placeholder Screens
struct SearchView: View {
    @State private var searchText = ""
    @State private var results: [AppUser] = []
    @State private var requestStatuses: [String: FriendRequestStatus] = [:]
    @State private var selectedUser: AppUser? = nil
    @State private var isLoading = false
    @State private var searchFailed = false

    var body: some View {
        VStack(spacing: 0) {
            // Full-width search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search for users...", text: $searchText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray5))

            if searchText.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Search for users to add as friends")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if results.isEmpty {
                Spacer()
                if searchFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("Search failed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Check your connection and try again")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("No users found for \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { user in
                            UserSearchRow(user: user, status: requestStatuses[user.id] ?? .none)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedUser = user }
                            Divider()
                                .padding(.leading, 74)
                        }
                    }
                }
            }
        }
        // Re-runs automatically when searchText changes; cancels the previous task
        .task(id: searchText) {
            guard !searchText.isEmpty else { results = []; searchFailed = false; return }
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true
            searchFailed = false
            do {
                results = try await UserService.shared.searchUsers(query: searchText)
            } catch {
                searchFailed = true
                results = []
            }
            isLoading = false
        }
        .sheet(item: $selectedUser) { user in
            UserProfileSheet(user: user) { newStatus in
                requestStatuses[user.id] = newStatus
            }
            .presentationDetents([.medium])
        }
    }
}

struct MapView: View {
    var body: some View {
        MapScreen()
    }
}

// MARK: - Friend Request Status
enum FriendRequestStatus {
    case none, requested, friends
}

// MARK: - User Search Row
struct UserSearchRow: View {
    let user: AppUser
    let status: FriendRequestStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 52, height: 52)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(user.username)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            switch status {
            case .none:
                EmptyView()
            case .requested:
                Text("Requested")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(8)
            case .friends:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - User Profile Sheet
struct UserProfileSheet: View {
    let user: AppUser
    let onStatusChange: (FriendRequestStatus) -> Void

    @State private var status: FriendRequestStatus = .none
    @State private var isLoadingStatus = true
    @State private var isSending = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 100, height: 100)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 30)

            Text(user.username)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundColor(.green)
                Text("Step Score: \(user.stepScore)")
                    .font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)

            Button(action: sendRequest) {
                Group {
                    if isSending || isLoadingStatus {
                        ProgressView().tint(status == .none ? .white : .secondary)
                    } else {
                        HStack {
                            Image(systemName: buttonIcon)
                            Text(buttonLabel)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(status == .none ? Color.blue : Color(UIColor.systemGray4))
                .foregroundColor(status == .none ? .white : .secondary)
                .cornerRadius(12)
            }
            .disabled(status != .none || isSending || isLoadingStatus)
            .padding(.horizontal, 30)

            Spacer()
        }
        .task {
            status = await FriendService.shared.status(for: user.id)
            isLoadingStatus = false
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var buttonIcon: String {
        switch status {
        case .none:     return "person.badge.plus"
        case .requested: return "clock"
        case .friends:  return "checkmark.circle.fill"
        }
    }

    private var buttonLabel: String {
        switch status {
        case .none:     return "Add Friend"
        case .requested: return "Request Sent"
        case .friends:  return "Friends"
        }
    }

    private func sendRequest() {
        guard status == .none else { return }
        isSending = true
        Task {
            do {
                try await FriendService.shared.sendRequest(to: user.id)
                status = .requested
                onStatusChange(.requested)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

struct ProfileView: View {
    private let profileManager = ProfileImageManager.shared
    private let stepManager    = StepCounterManager.shared
    @State private var username: String = ""
    @State private var leaderboardType: LeaderboardType = .daily
    @State private var leaderboardEntries: [LeaderboardEntry] = []
    @State private var isLoadingLeaderboard = false
    @State private var leaderboardLoadFailed = false
    @State private var errorMessage: String? = nil
    @State private var showProfileMenu = false
    @State private var showEditProfile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // MARK: Profile picture (centered, tappable)
                Button {
                    showProfileMenu = true
                } label: {
                    ZStack {
                        if let img = profileManager.profileImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color(UIColor.systemGray4), lineWidth: 1))
                        } else {
                            Circle()
                                .fill(Color(UIColor.systemGray3))
                                .frame(width: 120, height: 120)
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }
                    }
                }
                .confirmationDialog("", isPresented: $showProfileMenu, titleVisibility: .hidden) {
                    Button("Edit Profile") { showEditProfile = true }
                    Button("Sign Out", role: .destructive) {
                        ProfileImageManager.shared.clearImage()
                        do {
                            try FirebaseManager.shared.signOut()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .padding(.top, 48)

                // MARK: Username
                if !username.isEmpty {
                    Text(username)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // MARK: Step metrics
                HStack(spacing: 16) {
                    StepMetricCard(
                        value: stepManager.dailySteps.formatted(),
                        label: "Daily Steps",
                        icon: "figure.walk",
                        color: .green
                    )
                    StepMetricCard(
                        value: stepManager.totalStepScore.formatted(),
                        label: "Step Score",
                        icon: "star.fill",
                        color: .orange
                    )
                }
                .padding(.horizontal, 24)

                // MARK: Apple Health import
                AppleHealthCard()
                    .padding(.horizontal, 24)

                // MARK: Leaderboard section
                VStack(spacing: 0) {
                    // Dropdown picker
                    HStack {
                        Text("\(leaderboardType.rawValue) Leaderboard")
                            .font(.headline)
                        Spacer()
                        Picker("Leaderboard", selection: $leaderboardType) {
                            ForEach(LeaderboardType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                    if isLoadingLeaderboard {
                        ProgressView().padding(.vertical, 30)
                    } else if leaderboardEntries.isEmpty {
                        Text(leaderboardLoadFailed
                             ? "Couldn't load leaderboard — check your connection"
                             : "Add friends to see the leaderboard")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 30)
                    } else {
                        let sorted = leaderboardEntries.sorted {
                            $0.value(for: leaderboardType) > $1.value(for: leaderboardType)
                        }
                        VStack(spacing: 8) {
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, entry in
                                LeaderboardRowView(
                                    placing: idx + 1,
                                    entry: entry,
                                    type: leaderboardType
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .onChange(of: showEditProfile) { _, isShowing in
            if !isShowing {
                Task {
                    if let user = try? await UserService.shared.fetchCurrentUser() {
                        username = user.username
                    }
                }
            }
        }
        .task {
            do {
                if let user = try await UserService.shared.fetchCurrentUser() {
                    username = user.username
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .task(id: leaderboardType) {
            isLoadingLeaderboard = true
            leaderboardLoadFailed = false
            do {
                leaderboardEntries = try await LeaderboardService.shared.fetchEntries()
            } catch {
                leaderboardLoadFailed = true
                leaderboardEntries = []
                errorMessage = error.localizedDescription
            }
            isLoadingLeaderboard = false
            // Streak updates and dailySteps resets are handled server-side by
            // the `midnightReset` Cloud Function — no client-side write needed.
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

// MARK: - Leaderboard Row

struct LeaderboardRowView: View {
    let placing: Int
    let entry: LeaderboardEntry
    let type: LeaderboardType

    var body: some View {
        HStack(spacing: 8) {
            // Left box — placing ordinal
            Text(ordinal(placing))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(placingColor)
                .frame(width: 62, height: 56)
                .background(rowBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(placingColor.opacity(0.55), lineWidth: 1.5)
                )

            // Right box — avatar, username (centered), streak, steps
            HStack(spacing: 0) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(avatarColor(for: entry.username))
                        .frame(width: 34, height: 34)
                    Text(String(entry.username.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.leading, 10)

                // Username — centered in remaining space
                Text(entry.isCurrentUser ? "You" : entry.username)
                    .font(.system(size: 15, weight: entry.isCurrentUser ? .bold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Streak + steps (right-aligned, fixed area)
                HStack(spacing: 6) {
                    let streak = entry.streak(for: type)
                    if streak > 0 {
                        StreakBadge(streak: streak)
                    }
                    Text(entry.value(for: type).formatted())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.trailing, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(rowBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(UIColor.systemGray4), lineWidth: 1)
            )
        }
    }

    private var rowBackground: Color {
        entry.isCurrentUser ? Color.blue.opacity(0.06) : Color(UIColor.systemBackground)
    }

    private var placingColor: Color {
        switch placing {
        case 1:  return Color(red: 1.0, green: 0.84, blue: 0.0)   // gold
        case 2:  return Color(white: 0.6)                           // silver
        case 3:  return Color(red: 0.80, green: 0.50, blue: 0.20)  // bronze
        default: return .secondary
        }
    }

    private func ordinal(_ n: Int) -> String {
        let ones = n % 10, tens = (n % 100) / 10
        let suffix: String
        if tens == 1 { suffix = "th" }
        else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Step Metric Card

struct StepMetricCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Motion Permission Sheet

struct MotionPermissionSheet: View {
    let isDenied: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
                .padding(.top, 40)

            Text("Step Counting")
                .font(.title2)
                .fontWeight(.bold)

            Text(isDenied
                 ? "Step counting is currently disabled. Without it your steps won't be tracked and you won't appear on the leaderboard."
                 : "TouchGrass counts your steps to track daily progress and compete with friends on the leaderboard.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            if isDenied {
                Text("To fix this, go to:\nSettings → Privacy & Security → Motion & Fitness → TouchGrass")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button(isDenied ? "Open Settings" : "Allow Step Counting") {
                    if isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        UserDefaults.standard.set(true, forKey: "hasShownMotionPrompt")
                        // Accessing the shared instance starts CMPedometer,
                        // which triggers the system permission dialog.
                        _ = StepCounterManager.shared
                    }
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)

                Button("Not Now") {
                    UserDefaults.standard.set(true, forKey: "hasShownMotionPrompt")
                    dismiss()
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Apple Health Import Card

struct AppleHealthCard: View {
    private let hkManager = HealthKitManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                        .font(.headline)
                    Text("Import steps from Apple Watch")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if !hkManager.isAvailable {
                Text("HealthKit is not available on this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !hkManager.hasRequestedAccess {
                Button {
                    hkManager.requestAuthorization()
                } label: {
                    Label("Connect Apple Health", systemImage: "link")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if hkManager.isFetching {
                            Text("Fetching…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(hkManager.dailySteps.formatted()) steps today")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text("From Apple Health")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        hkManager.fetchSteps()
                        hkManager.syncToLeaderboard()
                    } label: {
                        Text("Sync")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(hkManager.isFetching)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }
}

#Preview {
    ContentView()
}
