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
    var body: some View {
        VStack {
            Text("Search Screen")
                .font(.largeTitle)
        }
    }
}

struct MapView: View {
    var body: some View {
        MapScreen()
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
