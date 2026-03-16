//
//  ContentView.swift
//  TouchGrass
//
//  Created by Simon Fossett on 3/15/26.
//

import SwiftUI

// MARK: - Main Content View (Home Screen)
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
            .padding(.horizontal, 30)
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
                .frame(width: 25, height: 25)
                .foregroundColor(selectedTab == tab ? .blue : .gray)
        }
    }
}

// MARK: - Placeholder Screens
struct HomeView: View {
    var body: some View {
        VStack {
            Text("Home Screen")
                .font(.largeTitle)
        }
    }
}

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
        VStack {
            Text("Map Screen")
                .font(.largeTitle)
        }
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
