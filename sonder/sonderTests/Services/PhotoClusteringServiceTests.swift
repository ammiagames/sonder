import Testing
import Foundation
import CoreLocation
@testable import sonder

@Suite
struct PhotoClusteringServiceTests {

    // MARK: - Helpers

    private func makePhoto(
        id: String = UUID().uuidString,
        lat: Double? = nil,
        lon: Double? = nil,
        date: Date? = nil
    ) -> PhotoMetadata {
        let coord: CLLocationCoordinate2D? = if let lat, let lon {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            nil
        }
        return PhotoMetadata(id: id, coordinate: coord, creationDate: date)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Basic Clustering

    @Test func emptyInput_returnsEmptyClusters() {
        let (clusters, unlocated) = PhotoClusteringService.cluster(photos: [])
        #expect(clusters.isEmpty)
        #expect(unlocated.isEmpty)
    }

    @Test func singlePhoto_createsSingleCluster() {
        let photo = makePhoto(lat: 40.7128, lon: -74.0060, date: date(2025, 6, 15))
        let (clusters, unlocated) = PhotoClusteringService.cluster(photos: [photo])

        #expect(clusters.count == 1)
        #expect(clusters[0].photoMetadata.count == 1)
        #expect(unlocated.isEmpty)
    }

    @Test func sameLocationSameDay_singleCluster() {
        let day = date(2025, 6, 15)
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: day),
            makePhoto(id: "b", lat: 40.7129, lon: -74.0061, date: day), // ~14m away
            makePhoto(id: "c", lat: 40.7130, lon: -74.0059, date: day), // ~22m away
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 1)
        #expect(clusters[0].photoMetadata.count == 3)
    }

    @Test func sameLocationDifferentDays_separateClusters() {
        let day1 = date(2025, 6, 15)
        let day2 = date(2025, 6, 16)
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: day1),
            makePhoto(id: "b", lat: 40.7129, lon: -74.0061, date: day2),
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 2)
        #expect(clusters[0].photoMetadata.count == 1)
        #expect(clusters[1].photoMetadata.count == 1)
    }

    @Test func farApartSameDay_separateClusters() {
        let day = date(2025, 6, 15)
        // NYC and Brooklyn (~5km apart)
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: day),  // Manhattan
            makePhoto(id: "b", lat: 40.6892, lon: -73.9857, date: day),  // Brooklyn
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 2)
    }

    @Test func noGPSPhotos_allUnlocated() {
        let photos = [
            makePhoto(id: "a", date: date(2025, 6, 15)),
            makePhoto(id: "b", date: date(2025, 6, 15)),
        ]

        let (clusters, unlocated) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.isEmpty)
        #expect(unlocated.count == 2)
    }

    @Test func mixedGPSAndNoGPS_separatesCorrectly() {
        let day = date(2025, 6, 15)
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: day),
            makePhoto(id: "b", date: day), // no GPS
            makePhoto(id: "c", lat: 40.7129, lon: -74.0061, date: day),
        ]

        let (clusters, unlocated) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 1)
        #expect(clusters[0].photoMetadata.count == 2)
        #expect(unlocated.count == 1)
        #expect(unlocated[0].id == "b")
    }

    // MARK: - Centroid Calculation

    @Test func centroid_isAverageOfCoordinates() {
        let day = date(2025, 6, 15)
        let photos = [
            makePhoto(id: "a", lat: 40.0, lon: -74.0, date: day),
            makePhoto(id: "b", lat: 40.0002, lon: -74.0002, date: day),
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 1)

        let centroid = clusters[0].centroid!
        // Centroid should be approximately the average
        #expect(abs(centroid.latitude - 40.0001) < 0.001)
        #expect(abs(centroid.longitude - (-74.0001)) < 0.001)
    }

    // MARK: - Custom Radius

    @Test func customRadius_respectsThreshold() {
        let day = date(2025, 6, 15)
        // Two points ~150m apart
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: day),
            makePhoto(id: "b", lat: 40.7140, lon: -74.0060, date: day), // ~133m north
        ]

        // With 200m radius (default) → single cluster
        let (clusters200, _) = PhotoClusteringService.cluster(photos: photos, radiusMeters: 200)
        #expect(clusters200.count == 1)

        // With 50m radius → two clusters
        let (clusters50, _) = PhotoClusteringService.cluster(photos: photos, radiusMeters: 50)
        #expect(clusters50.count == 2)
    }

    // MARK: - Date Assignment

    @Test func clusterDate_isEarliestPhotoDate() {
        let early = date(2025, 6, 15, hour: 9)
        let late = date(2025, 6, 15, hour: 18)
        let photos = [
            makePhoto(id: "a", lat: 40.7128, lon: -74.0060, date: late),
            makePhoto(id: "b", lat: 40.7129, lon: -74.0061, date: early),
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 1)
        #expect(clusters[0].date == early)
    }

    // MARK: - Multi-cluster Scenario

    @Test func multipleLocationsMultipleDays_correctGrouping() {
        let day1 = date(2025, 6, 15)
        let day2 = date(2025, 6, 16)
        let photos = [
            // Day 1, Location A (Times Square area)
            makePhoto(id: "a1", lat: 40.7580, lon: -73.9855, date: day1),
            makePhoto(id: "a2", lat: 40.7581, lon: -73.9856, date: day1),
            // Day 1, Location B (Central Park, ~1.5km away)
            makePhoto(id: "b1", lat: 40.7712, lon: -73.9741, date: day1),
            // Day 2, Location A again (Times Square)
            makePhoto(id: "c1", lat: 40.7580, lon: -73.9855, date: day2),
        ]

        let (clusters, _) = PhotoClusteringService.cluster(photos: photos)
        #expect(clusters.count == 3)

        // Find the cluster with 2 photos (Times Square day 1)
        let bigCluster = clusters.first { $0.photoMetadata.count == 2 }
        #expect(bigCluster != nil)
        let ids = bigCluster!.photoMetadata.map(\.id)
        #expect(ids.contains("a1"))
        #expect(ids.contains("a2"))
    }
}
