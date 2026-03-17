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

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
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

    var filteredFriends: [Friend] {
        let pinned = friends.filter { $0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let unpinned = friends.filter { !$0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let all = pinned + unpinned
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.lowercased().hasPrefix(searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-width search bar
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGray5))

            // Friends list
            ScrollView {
                LazyVStack(spacing: 0) {
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
    @State private var requestStatuses: [UUID: FriendRequestStatus] = [:]
    @State private var selectedUser: PlatformUser? = nil

    // Mock platform users — replace with backend fetch
    let allUsers: [PlatformUser] = [
        PlatformUser(username: "alex_walks",    stepScore: 12450),
        PlatformUser(username: "brianna_fit",   stepScore: 8920),
        PlatformUser(username: "carlos_runner", stepScore: 21300),
        PlatformUser(username: "dana_steps",    stepScore: 5670),
        PlatformUser(username: "eli_outdoor",   stepScore: 9800),
        PlatformUser(username: "fiona_hike",    stepScore: 14200),
        PlatformUser(username: "george_trek",   stepScore: 3450),
        PlatformUser(username: "hana_walks",    stepScore: 7800),
        PlatformUser(username: "ivan_run",      stepScore: 18900),
        PlatformUser(username: "julia_pace",    stepScore: 6100),
        PlatformUser(username: "kevin_steps",   stepScore: 11200),
        PlatformUser(username: "laura_hike",    stepScore: 9300),
        PlatformUser(username: "mike_outdoor",  stepScore: 4500),
        PlatformUser(username: "nina_trek",     stepScore: 16700),
        PlatformUser(username: "oscar_run",     stepScore: 7200),
        PlatformUser(username: "paula_fit",     stepScore: 13800),
        PlatformUser(username: "quinn_walk",    stepScore: 5500),
        PlatformUser(username: "rosa_steps",    stepScore: 8100),
        PlatformUser(username: "simon_fossett", stepScore: 9500),
        PlatformUser(username: "tara_hike",     stepScore: 11900),
    ]

    var filteredUsers: [PlatformUser] {
        guard !searchText.isEmpty else { return [] }
        return allUsers.filter { $0.username.lowercased().hasPrefix(searchText.lowercased()) }
    }

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
            } else if filteredUsers.isEmpty {
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
                        ForEach(filteredUsers) { user in
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
        .sheet(item: $selectedUser) { user in
            UserProfileSheet(
                user: user,
                status: requestStatuses[user.id] ?? .none,
                onAddFriend: { requestStatuses[user.id] = .requested }
            )
            .presentationDetents([.medium])
        }
    }
}

struct MapView: View {
    var body: some View {
        MapScreen()
    }
}

// MARK: - Platform User Model
struct PlatformUser: Identifiable {
    let id = UUID()
    let username: String
    let stepScore: Int
}

enum FriendRequestStatus {
    case none, requested, friends
}

// MARK: - User Search Row
struct UserSearchRow: View {
    let user: PlatformUser
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
    let user: PlatformUser
    let status: FriendRequestStatus
    let onAddFriend: () -> Void

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

            Button(action: {
                if status == .none { onAddFriend() }
            }) {
                HStack {
                    Image(systemName: status == .none ? "person.badge.plus" : "clock")
                    Text(status == .none ? "Add Friend" : "Request Sent")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(status == .none ? Color.blue : Color(UIColor.systemGray4))
                .foregroundColor(status == .none ? .white : .secondary)
                .cornerRadius(12)
            }
            .disabled(status != .none)
            .padding(.horizontal, 30)

            Spacer()
        }
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

struct ProfileView: View {
    var body: some View {
        VStack {
            Text("Profile Screen")
                .font(.largeTitle)
        }
    }
}

#Preview {
    ContentView()
}
