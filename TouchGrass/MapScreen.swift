//
//  MapScreen.swift
//  TouchGrass
//

import SwiftUI
import MapKit
import CoreLocation
import Observation

// MARK: - Friend Model
struct Friend: Identifiable {
    let id = UUID()
    let name: String
    var coordinate: CLLocationCoordinate2D
    var stepScore: Int = 0
    var isPinned: Bool = false
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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        // Example friends (replace with backend data)
        friends = [
            Friend(name: "Alice", coordinate: CLLocationCoordinate2D(latitude: 37.7799, longitude: -122.4294)),
            Friend(name: "Bob", coordinate: CLLocationCoordinate2D(latitude: 37.7699, longitude: -122.4094))
        ]
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            self.position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
}

// MARK: - Map View
struct MapScreen: View {
    @State private var viewModel = MapViewModel()
    private let stepManager = StepCounterManager.shared

    var body: some View {
        ZStack {
            Map(position: $viewModel.position) {
                UserAnnotation()
                ForEach(viewModel.friends) { friend in
                    Annotation(friend.name, coordinate: friend.coordinate) {
                        VStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title)
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
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            // You can later fetch friend locations from your server here
        }
    }
}

// MARK: - Preview
#Preview {
    MapScreen()
}
