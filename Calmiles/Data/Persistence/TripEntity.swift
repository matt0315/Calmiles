import Foundation
import SwiftData

@Model
final class TripEntity {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    var classificationRaw: String
    var purpose: String
    var notes: String
    var isManual: Bool
    var isAutoDetected: Bool
    var routeData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        classification: TripClassification = .undecided,
        purpose: String = "",
        notes: String = "",
        isManual: Bool = false,
        isAutoDetected: Bool = true,
        routePoints: [CoordinatePoint] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.classificationRaw = classification.rawValue
        self.purpose = purpose
        self.notes = notes
        self.isManual = isManual
        self.isAutoDetected = isAutoDetected
        self.routeData = try? JSONEncoder().encode(routePoints)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var classification: TripClassification {
        get { TripClassification(rawValue: classificationRaw) ?? .undecided }
        set { classificationRaw = newValue.rawValue }
    }

    var routePoints: [CoordinatePoint] {
        get {
            guard let routeData else { return [] }
            return (try? JSONDecoder().decode([CoordinatePoint].self, from: routeData)) ?? []
        }
        set {
            routeData = try? JSONEncoder().encode(newValue)
        }
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}
