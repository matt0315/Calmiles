import Foundation

struct CoordinatePoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var speed: Double?
    var horizontalAccuracy: Double?

    init(latitude: Double, longitude: Double, timestamp: Date = Date(), speed: Double? = nil, horizontalAccuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }
}
