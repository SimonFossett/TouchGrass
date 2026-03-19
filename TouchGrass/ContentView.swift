//
//  ContentView.swift
//  TouchGrass
//
//  Created by Simon Fossett on 3/15/26.
//

import SwiftUI
import MapKit

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
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray6))
        }
        .edgesIgnoringSafeArea(.bottom)
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

// MARK: - Home View
struct HomeView: View {
    @State private var searchText: String = ""
    @State private var friends: [Friend] = [
        Friend(name: "Alice", coordinate: CLLocationCoordinate2D(latitude: 37.7799, longitude: -122.4294), stepScore: 4820),
        Friend(name: "Bob", coordinate: CLLocationCoordinate2D(latitude: 37.7699, longitude: -122.4094), stepScore: 3150),
        Friend(name: "Charlie", coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4194), stepScore: 7230),
        Friend(name: "Diana", coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094), stepScore: 2100),
        Friend(name: "Eve", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4394), stepScore: 5670),
        Friend(name: "Simon", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4294), stepScore: 9500),
    ]
    @State private var selectedFriend: Friend? = nil
    @State private var showingFriendDetail = false
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    @State private var pendingRequests: [AppUser] = []
    private let profileManager = ProfileImageManager.shared

    var filteredFriends: [Friend] {
        let pinned = friends.filter { $0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let unpinned = friends.filter { !$0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
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
                        try? FirebaseManager.shared.signOut()
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
            ScrollView {
                LazyVStack(spacing: 0) {

                    // MARK: Pending friend requests (always at top)
                    if !pendingRequests.isEmpty {
                        SectionHeader(title: "Friend Requests")
                        ForEach(pendingRequests) { user in
                            FriendRequestRow(user: user) {
                                acceptRequest(user)
                            } onDecline: {
                                declineRequest(user)
                            }
                            Divider().padding(.leading, 74)
                        }
                        SectionHeader(title: "Friends")
                    }

                    // MARK: Regular friends list
                    ForEach(filteredFriends) { friend in
                        FriendRow(friend: friend)
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.5) {
                                selectedFriend = friend
                                showingFriendDetail = true
                            }
                        Divider()
                            .padding(.leading, 74)
                    }
                }
            }
            .refreshable {
                await loadPendingRequests()
            }
        }
        .task {
            await loadPendingRequests()
        }
        .sheet(isPresented: $showingFriendDetail) {
            if let friend = selectedFriend,
               let idx = friends.firstIndex(where: { $0.id == friend.id }) {
                FriendDetailSheet(friend: friends[idx]) {
                    friends[idx].isPinned.toggle()
                    showingFriendDetail = false
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
    }

    // MARK: - Helpers

    private func loadPendingRequests() async {
        pendingRequests = (try? await FriendService.shared.incomingRequests()) ?? []
    }

    private func acceptRequest(_ user: AppUser) {
        Task {
            try? await FriendService.shared.acceptRequest(from: user.id)
            pendingRequests.removeAll { $0.id == user.id }
            // Insert the new friend in alphabetical order
            let newFriend = Friend(
                name: user.username,
                coordinate: .init(latitude: 0, longitude: 0),
                stepScore: user.stepScore
            )
            let insertIdx = friends.firstIndex { $0.name.lowercased() > user.username.lowercased() }
                ?? friends.endIndex
            friends.insert(newFriend, at: insertIdx)
        }
    }

    private func declineRequest(_ user: AppUser) {
        Task {
            try? await FriendService.shared.denyRequest(from: user.id)
            pendingRequests.removeAll { $0.id == user.id }
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

// MARK: - Friend Detail Sheet
struct FriendDetailSheet: View {
    let friend: Friend
    let onPin: () -> Void

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
                VStack(spacing: 12) {
                    Image(systemName: "person.slash.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No users found for \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
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
            guard !searchText.isEmpty else { results = []; return }
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isLoading = true
            results = (try? await UserService.shared.searchUsers(query: searchText)) ?? []
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
            try? await FriendService.shared.sendRequest(to: user.id)
            status = .requested
            onStatusChange(.requested)
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
    private let stepManager = StepCounterManager.shared
    @State private var username: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // MARK: Profile picture (centered)
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

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            if let user = try? await UserService.shared.fetchCurrentUser() {
                username = user.username
            }
        }
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

#Preview {
    ContentView()
}
