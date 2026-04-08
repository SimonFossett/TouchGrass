//
//  ContentView.swift
//  TouchGrass
//
//  Created by Simon Fossett on 3/15/26.
//

import SwiftUI
import MapKit
import CoreMotion
import Charts
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Tab Bar Visibility Environment Key

private struct HideTabBarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}
extension EnvironmentValues {
    fileprivate var hideTabBar: Binding<Bool> {
        get { self[HideTabBarKey.self] }
        set { self[HideTabBarKey.self] = newValue }
    }
}

// MARK: - Tab Bar Compact Environment Key
// Scrollable screens set this to true when the user scrolls down so the
// tab bar can shrink, and back to false when they scroll to the top.

private struct TabBarCompactKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}
extension EnvironmentValues {
    fileprivate var tabBarCompact: Binding<Bool> {
        get { self[TabBarCompactKey.self] }
        set { self[TabBarCompactKey.self] = newValue }
    }
}

// MARK: - Scroll Offset Preference Key
// A zero-height Color.clear placed at the top of a scroll view's content
// reports its minY in the scroll view's coordinate space. Negative values
// mean the user has scrolled down.

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Tab Frame Preference Key
// Each tab button reports its CGRect in the "tabBar" coordinate space so
// the indicator pill can be positioned and drag-snapped correctly.

private struct TabFrameKey: PreferenceKey {
    static var defaultValue: [Tab: CGRect] = [:]
    static func reduce(value: inout [Tab: CGRect], nextValue: () -> [Tab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @State private var mapViewModel = MapViewModel()
    @State private var hideTabBar = false
    @State private var isTabBarCompact = false
    private let firebase = FirebaseManager.shared

    var body: some View {
        if firebase.isAuthenticated {
            mainApp
        } else {
            AuthView()
        }
    }

    var mainApp: some View {
        ZStack(alignment: .bottom) {
            // Content fills the full screen
            ZStack {
                switch selectedTab {
                case .home:
                    HomeView()
                case .search:
                    SearchView()
                case .map:
                    MapView(viewModel: mapViewModel)
                case .leaderboard:
                    LeaderboardView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)
            .environment(\.hideTabBar, $hideTabBar)
            .environment(\.tabBarCompact, $isTabBarCompact)

            // Tab bar floats over content — hidden during story camera/viewer
            if !hideTabBar {
                CustomTabBarView(selectedTab: $selectedTab, isCompact: $isTabBarCompact)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Reset compact state whenever the user switches tabs so a non-scrollable
        // screen (e.g. Map) never gets stuck with a shrunken bar.
        .onChange(of: selectedTab) { _, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isTabBarCompact = false
            }
        }
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
    case home, search, map, leaderboard, profile
}

// MARK: - Custom Tab Bar
// Hosts the glass pill container, the five tab icons, and the draggable
// indicator pill. The indicator tracks each button's frame via a
// PreferenceKey so it can be positioned precisely without matchedGeometry.

struct CustomTabBarView: View {
    @Binding var selectedTab: Tab
    @Binding var isCompact: Bool

    @State private var tabFrames: [Tab: CGRect] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let orderedTabs: [(Tab, String)] = [
        (.home,        "house"),
        (.search,      "magnifyingglass"),
        (.map,         "map"),
        (.leaderboard, "trophy"),
        (.profile,     "person")
    ]

    var body: some View {
        let iconSize: CGFloat = isCompact ? 20 : 24
        let vertPad:  CGFloat = isCompact ? 7  : 14

        ZStack(alignment: .leading) {

            // ── Indicator pill (sits behind the icons) ──────────────────
            if let frame = tabFrames[selectedTab] {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(0.3))
                    .frame(width: frame.width, height: frame.height)
                    // clamp so the pill never slides outside the bar
                    .offset(x: clampedPillX(frame: frame))
            }

            // ── Icon row ────────────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(orderedTabs, id: \.0) { tab, icon in
                    Image(systemName: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(selectedTab == tab ? .blue : .gray)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedTab = tab
                                dragOffset = 0
                            }
                        }
                        // Each button reports its frame in the "tabBar" space.
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TabFrameKey.self,
                                    value: [tab: proxy.frame(in: .named("tabBar"))]
                                )
                            }
                        )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "tabBar")
        .onPreferenceChange(TabFrameKey.self) { tabFrames = $0 }
        .padding(.horizontal, 36)
        .padding(.vertical, vertPad)
        .background(GlassBackground(cornerRadius: isCompact ? 18 : 22,
                                     showReflection: selectedTab == .map))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .scaleEffect(isCompact ? 0.88 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isCompact)
        // Drag gesture — simultaneousGesture lets individual onTapGestures
        // still fire for short touches (< minimumDistance movement).
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("tabBar"))
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        if let frame = tabFrames[selectedTab] {
                            let pillMidX = clampedPillX(frame: frame) + frame.width / 2
                            selectedTab = nearestTab(to: pillMidX) ?? selectedTab
                        }
                        dragOffset = 0
                    }
                    isDragging = false
                }
        )
    }

    // Returns the nearest tab to a given x position in the "tabBar" space.
    private func nearestTab(to x: CGFloat) -> Tab? {
        tabFrames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }

    // Clamps pill x so it never slides past the leftmost or rightmost button.
    private func clampedPillX(frame: CGRect) -> CGFloat {
        let raw = frame.minX + dragOffset
        let minX = tabFrames.values.map(\.minX).min() ?? 0
        let maxX = (tabFrames.values.map(\.maxX).max() ?? frame.width) - frame.width
        return max(minX, min(raw, maxX))
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
    @State private var viewModel = HomeViewModel()
    @State private var selectedFriend: Friend? = nil
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    @State private var showFriendSearch = false
    @State private var showInbox = false
    private let profileManager = ProfileImageManager.shared
    private let storyService = StoryService.shared
    @State private var activeStoryUserIndex: Int? = nil
    @State private var showMyStoryViewer = false
    @State private var showStoryCamera = false
    @State private var isUploadingStory = false
    @State private var storyUploadError: String? = nil
    @Environment(\.hideTabBar)    private var hideTabBar
    @Environment(\.tabBarCompact) private var tabBarCompact

    var sortedFriends: [Friend] {
        let pinned   = viewModel.friends.filter {  $0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let unpinned = viewModel.friends.filter { !$0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        return pinned + unpinned
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: profile pic · search circle · (spacer) · inbox circle
            HStack(spacing: 12) {
                // Profile picture button
                Button {
                    showProfileMenu = true
                } label: {
                    if let img = profileManager.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(UIColor.systemGray3))
                            .frame(width: 58, height: 58)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 26))
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

                // Circular search button
                Button { showFriendSearch = true } label: {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.primary)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                Spacer()

                // Inbox / friend-requests button
                Button { showInbox = true } label: {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.primary)
                        )
                        .overlay(alignment: .topTrailing) {
                            if !viewModel.pendingRequests.isEmpty {
                                Text(viewModel.pendingRequests.count > 9 ? "9+" : "\(viewModel.pendingRequests.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Color.red, in: Circle())
                                    .offset(x: 4, y: -4)
                            }
                        }
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(UIColor.systemGray5))

            // Friends list
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {

                        // Scroll-offset probe: reports minY in the ScrollView's
                        // coordinate space. Negative → user has scrolled down.
                        Color.clear
                            .frame(height: 0)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: proxy.frame(in: .named("homeScroll")).minY
                                    )
                                }
                            )

                        // MARK: Explore Stories
                        ExploreStoriesSection(
                            myStories: storyService.myStories,
                            friendStories: storyService.userStories,
                            onTapMyStory: { showMyStoryViewer = true },
                            onTapFriendStory: { idx in activeStoryUserIndex = idx },
                            onAddStory: { showStoryCamera = true }
                        )

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
                            ForEach(sortedFriends) { friend in
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
                .scrollDismissesKeyboard(.immediately)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }
                .coordinateSpace(name: "homeScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        tabBarCompact.wrappedValue = offset < -50
                    }
                }
            }
        }
        .dismissKeyboardOnTap()
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
        .fullScreenCover(isPresented: $showInbox) {
            FriendRequestsInboxView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showFriendSearch) {
            FriendSearchView(friends: viewModel.friends) { friend in
                selectedFriend = friend
            }
        }
        .fullScreenCover(isPresented: $showStoryCamera) {
            DualCameraView { compositeImage in
                // Dismiss camera immediately so the user isn't left on a blank screen.
                showStoryCamera = false
                Task {
                    isUploadingStory = true
                    do {
                        try await storyService.postStory(image: compositeImage)
                    } catch {
                        storyUploadError = error.localizedDescription
                    }
                    isUploadingStory = false
                }
            } onDismiss: {
                showStoryCamera = false
            }
            .ignoresSafeArea()
        }
        // Upload spinner — sits on top of everything while the story is being sent
        .overlay {
            if isUploadingStory {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Posting story…")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("Story Upload Failed", isPresented: Binding(
            get: { storyUploadError != nil },
            set: { if !$0 { storyUploadError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(storyUploadError ?? "")
        }
        // Start/refresh story listeners as soon as the friends list is ready
        // and whenever it changes (friend added or removed).
        // Also pre-fetch avatar images so they're ready before the user scrolls.
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading {
                let uids = viewModel.friends.map { $0.uid }
                storyService.startListening(friendUIDs: uids)
                AvatarCache.shared.prefetch(uids: uids)
            }
        }
        .onChange(of: viewModel.friends.count) { _, _ in
            guard !viewModel.isLoading else { return }
            let uids = viewModel.friends.map { $0.uid }
            storyService.startListening(friendUIDs: uids)
            AvatarCache.shared.prefetch(uids: uids)
        }
        .overlay {
            if showMyStoryViewer, !storyService.myStories.isEmpty {
                let myUID = Auth.auth().currentUser?.uid ?? ""
                let myEntry = UserStories(uid: myUID, username: "Me",
                                         stories: storyService.myStories, hasUnseenStory: false)
                StoryViewerView(
                    allUserStories: [myEntry],
                    currentUserIndex: .constant(0),
                    onDismiss: { showMyStoryViewer = false },
                    onMarkSeen: { _ in }
                )
                .ignoresSafeArea()
            }
        }
        .overlay {
            if let idx = activeStoryUserIndex,
               !storyService.userStories.isEmpty,
               idx < storyService.userStories.count {
                StoryViewerView(
                    allUserStories: storyService.userStories,
                    currentUserIndex: Binding(
                        get: { idx },
                        set: { activeStoryUserIndex = $0 }
                    ),
                    onDismiss: { activeStoryUserIndex = nil },
                    onMarkSeen: { storyService.markSeen(storyID: $0) }
                )
                .ignoresSafeArea()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: showStoryCamera) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) { hideTabBar.wrappedValue = new }
        }
        .onChange(of: showMyStoryViewer) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) { hideTabBar.wrappedValue = new }
        }
        .onChange(of: activeStoryUserIndex) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) { hideTabBar.wrappedValue = new != nil }
        }
    }
}

// MARK: - Friend Search Page

struct FriendSearchView: View {
    let friends: [Friend]
    let onSelectFriend: (Friend) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var recentUIDs: [String] = []
    @FocusState private var searchFocused: Bool

    private let recentsKey = "recentFriendSearchUIDs"

    var recentFriends: [Friend] {
        recentUIDs.compactMap { uid in friends.first { $0.uid == uid } }
    }

    var filteredFriends: [Friend] {
        let sorted = friends.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: down-chevron dismiss + search bar
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(UIColor.systemGray5), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Recents ─────────────────────────────────────────
                    if !recentFriends.isEmpty && searchText.isEmpty {
                        HStack {
                            Text("Recents")
                                .font(.title3).fontWeight(.bold)
                                .padding(.leading, 16)
                            Spacer()
                            Button("Clear All") {
                                recentUIDs = []
                                UserDefaults.standard.removeObject(forKey: recentsKey)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 16)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(recentFriends) { friend in
                                    RecentFriendCard(friend: friend)
                                        .onTapGesture { selectFriend(friend) }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }

                    // ── Friends list ─────────────────────────────────────
                    HStack {
                        Text(searchText.isEmpty ? "Friends" : "Results")
                            .font(.title3).fontWeight(.bold)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                    if filteredFriends.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.slash.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("No friends found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredFriends) { friend in
                                FriendRow(friend: friend)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectFriend(friend) }
                                if friend.uid != filteredFriends.last?.uid {
                                    Divider().padding(.leading, 74)
                                }
                            }
                        }
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            recentUIDs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    private func selectFriend(_ friend: Friend) {
        var recents = recentUIDs.filter { $0 != friend.uid }
        recents.insert(friend.uid, at: 0)
        recentUIDs = Array(recents.prefix(10))
        UserDefaults.standard.set(recentUIDs, forKey: recentsKey)
        onSelectFriend(friend)
        dismiss()
    }
}

// MARK: - Recent Friend Card

struct RecentFriendCard: View {
    let friend: Friend
    @State private var profileImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.name))
                    .frame(width: 64, height: 64)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(friend.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 76)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .task(id: friend.uid) {
            profileImage = await AvatarCache.shared.fetch(uid: friend.uid)
        }
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Friend Requests Inbox

struct FriendRequestsInboxView: View {
    var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with glass back button
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(GlassBackground(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                Spacer()

                Text("Friend Requests")
                    .font(.headline)

                Spacer()

                // Invisible mirror of back button to keep title centred
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(UIColor.systemGray5))

            if viewModel.pendingRequests.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No pending friend requests")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(GlassBackground(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.pendingRequests) { user in
                            FriendRequestRow(user: user) {
                                viewModel.acceptRequest(from: user.id)
                            } onDecline: {
                                viewModel.declineRequest(from: user.id)
                            }
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
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

    @State private var profileImage: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 52, height: 52)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                }
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
        .task(id: user.id) {
            profileImage = await AvatarCache.shared.fetch(uid: user.id)
        }
    }

    func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Friend Row
struct FriendRow: View {
    let friend: Friend
    @State private var profileImage: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.name))
                    .frame(width: 64, height: 64)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
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

            if friend.streak > 0 {
                StreakBadge(streak: friend.streak)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(UIColor.systemBackground))
        .task(id: friend.uid) {
            profileImage = await AvatarCache.shared.fetch(uid: friend.uid)
        }
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
    @State private var profileImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Enlarged profile picture
            ZStack {
                Circle()
                    .fill(avatarColor(for: friend.name))
                    .frame(width: 100, height: 100)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Text(String(friend.name.prefix(1)).uppercased())
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 30)
            .task(id: friend.uid) {
                profileImage = await AvatarCache.shared.fetch(uid: friend.uid)
            }

            Text(friend.name)
                .font(.title2)
                .fontWeight(.bold)

            // Step score
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
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
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    private let profileManager = ProfileImageManager.shared

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
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(UIColor.systemGray3))
                            .frame(width: 58, height: 58)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 26))
                            )
                    }
                }
                .confirmationDialog("", isPresented: $showProfileMenu, titleVisibility: .hidden) {
                    Button("Edit Profile") { showEditProfile = true }
                    Button("Sign Out", role: .destructive) {
                        ProfileImageManager.shared.clearImage()
                        do { try FirebaseManager.shared.signOut() } catch {}
                    }
                }

                // Search bar
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(GlassBackground(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
                .padding(24)
                .background(GlassBackground(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
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
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .dismissKeyboardOnTap()
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
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
    }
}

struct MapView: View {
    var viewModel: MapViewModel
    var body: some View {
        MapScreen(viewModel: viewModel)
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
    @State private var profileImage: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 52, height: 52)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
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
        .task(id: user.id) {
            profileImage = await AvatarCache.shared.fetch(uid: user.id)
        }
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
    @State private var profileImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(avatarColor(for: user.username))
                    .frame(width: 100, height: 100)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
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
        .task(id: user.id) {
            profileImage = await AvatarCache.shared.fetch(uid: user.id)
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
    @State private var chartEntries: [LeaderboardEntry] = []
    @State private var errorMessage: String? = nil
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    @Environment(\.tabBarCompact) private var tabBarCompact

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // Scroll-offset probe
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("profileScroll")).minY
                            )
                        }
                    )

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

                // MARK: Username + step score
                if !username.isEmpty {
                    VStack(spacing: 4) {
                        Text(username)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(stepManager.totalStepScore.formatted()) step score")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: Step metrics — daily steps card
                StepMetricCard(
                    value: stepManager.dailySteps.formatted(),
                    label: "Daily Steps",
                    icon: "figure.walk",
                    color: .green
                )
                .padding(.horizontal, 24)

                // MARK: Today's steps comparison chart
                DailyStepsChartView(entries: chartEntries)
                    .padding(.horizontal, 24)

                // MARK: Apple Health
                AppleHealthCard()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

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
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }
        .coordinateSpace(name: "profileScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                tabBarCompact.wrappedValue = offset < -50
            }
        }
        .task {
            do {
                if let user = try await UserService.shared.fetchCurrentUser() {
                    username = user.username
                }
                chartEntries = try await LeaderboardService.shared.fetchEntries()
            } catch {
                errorMessage = error.localizedDescription
            }
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

// MARK: - Leaderboard View

struct LeaderboardView: View {
    @State private var leaderboardType: LeaderboardType = .daily
    @State private var leaderboardEntries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var firstPlaceImage: UIImage? = nil
    @Environment(\.tabBarCompact) private var tabBarCompact

    private var sorted: [LeaderboardEntry] {
        leaderboardEntries.sorted { $0.value(for: leaderboardType) > $1.value(for: leaderboardType) }
    }

    var body: some View {
        ZStack {
            // First-place user's story as full-screen background
            if let img = firstPlaceImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                    .transition(.opacity)
            }

            ScrollView {
                VStack(spacing: 16) {

                    // Scroll-offset probe
                    Color.clear
                        .frame(height: 0)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("leaderboardScroll")).minY
                                )
                            }
                        )

                    // MARK: Header row — title pill + picker pill
                    HStack(spacing: 12) {
                        Text("\(leaderboardType.rawValue) Leaderboard")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(GlassBackground(cornerRadius: 20))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

                        Spacer()

                        Picker("", selection: $leaderboardType) {
                            ForEach(LeaderboardType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(GlassBackground(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // MARK: Rows
                    if isLoading {
                        ProgressView().padding(.vertical, 40)
                    } else if leaderboardEntries.isEmpty {
                        Text(loadFailed
                             ? "Couldn't load leaderboard — check your connection"
                             : "Add friends to see the leaderboard")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 40)
                            .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, entry in
                                LeaderboardRowView(placing: idx + 1, entry: entry, type: leaderboardType)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 90) }
        .coordinateSpace(name: "leaderboardScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                tabBarCompact.wrappedValue = offset < -50
            }
        }
        .task(id: leaderboardType) {
            isLoading = true
            loadFailed = false
            do {
                leaderboardEntries = try await LeaderboardService.shared.fetchEntries()
            } catch {
                loadFailed = true
                leaderboardEntries = []
            }
            isLoading = false
            await loadFirstPlaceStory()
        }
        .onChange(of: leaderboardType) {
            Task { await loadFirstPlaceStory() }
        }
    }

    private func loadFirstPlaceStory() async {
        guard let firstPlace = sorted.first else {
            firstPlaceImage = nil
            return
        }
        let storyService = StoryService.shared
        let story: Story?
        if firstPlace.isCurrentUser {
            story = storyService.myStories.first
        } else {
            story = storyService.userStories.first { $0.uid == firstPlace.id }?.stories.first
        }
        guard let story else {
            firstPlaceImage = nil
            return
        }
        let image = await storyService.loadImage(for: story)
        withAnimation(.easeInOut(duration: 0.4)) {
            firstPlaceImage = image
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
                LeaderboardAvatarView(entry: entry)
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

}

// MARK: - Leaderboard Avatar

struct LeaderboardAvatarView: View {
    let entry: LeaderboardEntry
    @State private var friendImage: UIImage?
    private let profileManager = ProfileImageManager.shared

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: entry.username))
                .frame(width: 34, height: 34)

            if entry.isCurrentUser, let img = profileManager.profileImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else if !entry.isCurrentUser, let img = friendImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else {
                Text(String(entry.username.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .task(id: entry.id) {
            guard !entry.isCurrentUser else { return }
            friendImage = await AvatarCache.shared.fetch(uid: entry.id)
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Keyboard Helpers

extension View {
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}

// MARK: - Glass Background

struct GlassBackground: View {
    let cornerRadius: CGFloat
    var showReflection: Bool = false

    var body: some View {
        ZStack {
            // Base frosted blur
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            if showReflection {
                // Angled light reflection – consistent screen-space direction on every element.
                // GeometryReader is used so the gradient angle stays at 35° below horizontal
                // in screen space regardless of the element's aspect ratio.
                GeometryReader { geo in
                    let angleRad = 35.0 * Double.pi / 180
                    let dist    = 150.0                                // pixels along the ray
                    let endX    = dist * cos(angleRad) / geo.size.width
                    let endY    = dist * sin(angleRad) / geo.size.height
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.6),
                                        .white.opacity(0.1),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: UnitPoint(x: endX, y: endY)
                                )
                            )
                            .blendMode(.screen)
                        // Edge shine
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.8),
                                        .white.opacity(0.2),
                                        .clear,
                                        .white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                }
            } else {
                // Subtle uniform border without reflection
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            }
            // Inner shadow for depth
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
                .blur(radius: 4)
                .offset(x: 2, y: 2)
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
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
        .background(GlassBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

// MARK: - Daily Steps Chart

struct StepChartPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let cumulativeSteps: Int
    let label: String
}

struct DailyStepsChartView: View {
    let entries: [LeaderboardEntry]

    @State private var chartPoints: [StepChartPoint] = []
    @State private var isLoading = true
    private let stepManager = StepCounterManager.shared

    // Pick the two comparison users based on the current user's rank.
    // Rank 1 → compare 2nd & 3rd. Rank 2 → compare 1st & 3rd.
    // Rank 3 → compare 1st & 2nd. Rank 4+ → compare 1st & 2nd.
    private var comparisonEntries: [LeaderboardEntry] {
        let sorted = entries.sorted { $0.dailySteps > $1.dailySteps }
        guard let myIdx = sorted.firstIndex(where: { $0.isCurrentUser }) else { return [] }
        switch myIdx {
        case 0:  return Array(sorted.dropFirst().prefix(2))
        case 1:  return sorted.count > 2 ? [sorted[0], sorted[2]] : [sorted[0]]
        case 2:  return [sorted[0], sorted[1]]
        default: return Array(sorted.prefix(2))
        }
    }

    private var seriesLabels: [String] {
        ["You"] + comparisonEntries.map { $0.username }
    }

    private var seriesColors: [Color] {
        [.green] + [Color.blue, Color.orange].prefix(comparisonEntries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Steps", point.cumulativeSteps)
                    )
                    .foregroundStyle(by: .value("Person", point.label))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartForegroundStyleScale(
                    domain: seriesLabels,
                    range: seriesColors
                )
                .chartXScale(domain: 0...24)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                        if let hour = value.as(Int.self) {
                            AxisValueLabel { Text(hourLabel(hour)).font(.caption2) }
                            AxisGridLine()
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxis {
                    AxisMarks { value in
                        if let steps = value.as(Int.self) {
                            AxisValueLabel {
                                Text(steps >= 1000 ? "\(steps / 1000)k" : "\(steps)")
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .task { await buildChartData() }
        .onChange(of: entries.count) { _, _ in Task { await buildChartData() } }
        .onChange(of: stepManager.dailySteps) { _, _ in Task { await buildChartData() } }
    }

    private func buildChartData() async {
        isLoading = true
        let hourlyMine = await StepCounterManager.shared.fetchHourlySteps()

        // Always anchor midnight at 0. Each hourly reading covers startOfDay→(hour+1)am,
        // so shift it forward by 1 on the x-axis so hour-0 data plots at x=1, not x=0.
        var points: [StepChartPoint] = [StepChartPoint(hour: 0, cumulativeSteps: 0, label: "You")]
        for reading in hourlyMine {
            points.append(StepChartPoint(hour: reading.hour + 1, cumulativeSteps: reading.steps, label: "You"))
        }

        let currentHour = Calendar.current.component(.hour, from: Date())
        for entry in comparisonEntries {
            // Anchor friends at midnight too
            points.append(StepChartPoint(hour: 0, cumulativeSteps: 0, label: entry.username))
            for hour in 0...currentHour {
                let fraction = Double(hour + 1) / Double(currentHour + 1)
                let projected = Int(Double(entry.dailySteps) * fraction)
                points.append(StepChartPoint(hour: hour + 1, cumulativeSteps: projected, label: entry.username))
            }
        }
        chartPoints = points
        isLoading = false
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 24 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
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
                    Text("Connect Apple Watch for step precision")
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

// MARK: - Explore Stories Section

struct ExploreStoriesSection: View {
    let myStories: [Story]
    let friendStories: [UserStories]
    let onTapMyStory: () -> Void
    let onTapFriendStory: (Int) -> Void
    let onAddStory: () -> Void

    private let profileManager = ProfileImageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("Explore Stories")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
                    .padding(.vertical, 6)
                Spacer()
            }
            .background(Color(UIColor.systemGray6))

            // Horizontal story bubbles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    // My Story bubble (always present)
                    MyStoryBubble(
                        profileImage: profileManager.profileImage,
                        hasStory: !myStories.isEmpty,
                        // No active story → open camera. Active story → view it.
                        // Long-press is intentionally absent: one story per 24 h.
                        onTap: { myStories.isEmpty ? onAddStory() : onTapMyStory() }
                    )

                    // Friend story bubbles
                    ForEach(Array(friendStories.enumerated()), id: \.element.uid) { idx, userStory in
                        StoryBubble(userStories: userStory)
                            .onTapGesture { onTapFriendStory(idx) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(Color(UIColor.systemBackground))
        }
    }
}

// MARK: - My Story Bubble

struct MyStoryBubble: View {
    let profileImage: UIImage?
    let hasStory: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        // Green ring once a story is active
                        if hasStory {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.green, .mint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 92, height: 92)
                        }

                        // Profile image or placeholder
                        if let img = profileImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: hasStory ? 84 : 88, height: hasStory ? 84 : 88)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor.systemGray3))
                                .frame(width: hasStory ? 84 : 88, height: hasStory ? 84 : 88)
                            Image(systemName: "person.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 92, height: 92)

                    // + badge only while there is no active story
                    if !hasStory {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                Text("My Story")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Story Bubble

struct StoryBubble: View {
    let userStories: UserStories

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Ring — rainbow for unseen, gray for seen
                Circle()
                    .stroke(
                        userStories.hasUnseenStory
                            ? LinearGradient(
                                colors: [.purple, .pink, .orange, .yellow],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color(UIColor.systemGray3), Color(UIColor.systemGray3)],
                                startPoint: .top, endPoint: .bottom
                              ),
                        lineWidth: 3
                    )
                    .frame(width: 92, height: 92)

                StoryAvatarImage(uid: userStories.uid, username: userStories.username)
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
            }

            Text(userStories.username)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(width: 96)
    }
}

// MARK: - Story Avatar Image (cached)

struct StoryAvatarImage: View {
    let uid: String
    let username: String
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: username))
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(username.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .task(id: uid) {
            image = await AvatarCache.shared.fetch(uid: uid)
        }
    }

    private func avatarColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
        return colors[abs(name.hashValue) % colors.count]
    }
}

// MARK: - Story Viewer

struct StoryViewerView: View {
    let allUserStories: [UserStories]
    @Binding var currentUserIndex: Int
    let onDismiss: () -> Void
    let onMarkSeen: (String) -> Void

    @State private var currentStoryIndex: Int = 0
    @State private var progress: CGFloat = 0
    @State private var storyImage: UIImage? = nil
    @State private var isLoadingImage = true
    @GestureState private var dragY: CGFloat = 0
    @GestureState private var isPaused: Bool = false

    private let storyDuration: TimeInterval = 5.0

    private var currentUser: UserStories { allUserStories[currentUserIndex] }
    private var currentStory: Story { currentUser.stories[currentStoryIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Story image
            if let img = storyImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingImage {
                ProgressView().tint(.white)
            }

            // Tap zones: left = previous, right = next
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToNext() }
            }

            // Header: progress bars + user info
            VStack(spacing: 0) {
                // Progress bars
                HStack(spacing: 4) {
                    ForEach(0..<currentUser.stories.count, id: \.self) { i in
                        StoryProgressBar(
                            progress: i < currentStoryIndex ? 1.0
                                      : i == currentStoryIndex ? progress
                                      : 0.0
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 56)
                .padding(.bottom, 8)

                // Username row
                HStack(spacing: 10) {
                    StoryAvatarImage(uid: currentUser.uid, username: currentUser.username)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(currentUser.username)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(timeAgo(currentStory.createdAt))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 14)

                Spacer()
            }
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            )
        }
        .offset(y: dragY)
        .animation(.interactiveSpring(), value: dragY)
        .gesture(
            DragGesture()
                .updating($dragY) { value, state, _ in
                    if value.translation.height > 0 { state = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 { onDismiss() }
                }
        )
        // Hold anywhere to pause the progress bar; auto-resumes on release.
        // simultaneousGesture lets this run alongside the dismiss drag and
        // the left/right tap-zone gestures without blocking either.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPaused) { _, state, _ in state = true }
        )
        .task(id: "\(currentUserIndex)-\(currentStoryIndex)") {
            await loadAndRunStory()
        }
    }

    // MARK: - Navigation

    private func goToNext() {
        if currentStoryIndex < currentUser.stories.count - 1 {
            currentStoryIndex += 1
        } else if currentUserIndex < allUserStories.count - 1 {
            currentUserIndex += 1
            currentStoryIndex = 0
        } else {
            onDismiss()
        }
    }

    private func goToPrevious() {
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
        } else if currentUserIndex > 0 {
            currentUserIndex -= 1
            currentStoryIndex = max(0, allUserStories[currentUserIndex].stories.count - 1)
        }
    }

    // MARK: - Story Loading + Timer

    private func loadAndRunStory() async {
        isLoadingImage = true
        progress = 0
        storyImage = nil
        storyImage = await StoryService.shared.loadImage(for: currentStory)
        onMarkSeen(currentStory.id)
        isLoadingImage = false

        // Animate progress bar over storyDuration.
        // Each step waits for any active hold to be released before counting.
        let steps = 200
        let stepInterval = storyDuration / Double(steps)
        for step in 1...steps {
            guard !Task.isCancelled else { return }
            // Spin in 50 ms increments while the user is holding down.
            while isPaused {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            progress = CGFloat(step) / CGFloat(steps)
        }
        guard !Task.isCancelled else { return }
        goToNext()
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 3600 { return "\(max(1, secs / 60))m ago" }
        return "\(secs / 3600)h ago"
    }
}

// MARK: - Story Progress Bar

struct StoryProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.35))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: geo.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: 3)
    }
}

#Preview {
    ContentView()
}
