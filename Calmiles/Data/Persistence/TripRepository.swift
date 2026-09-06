import Foundation
import SwiftData

@MainActor
final class TripRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [TripEntity] {
        var descriptor = FetchDescriptor<TripEntity>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(in interval: DateInterval) throws -> [TripEntity] {
        let predicate = #Predicate<TripEntity> { trip in
            trip.startDate >= interval.start && trip.startDate < interval.end
        }
        var descriptor = FetchDescriptor<TripEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func add(_ trip: TripEntity) throws {
        context.insert(trip)
        try context.save()
    }

    func update(_ trip: TripEntity) throws {
        trip.updatedAt = Date()
        try context.save()
    }

    func delete(_ trip: TripEntity) throws {
        context.delete(trip)
        try context.save()
    }

    func deleteAll() throws {
        try fetchAll().forEach { context.delete($0) }
        try context.save()
    }

    func weeklySummary(reference: Date = Date(), calendar: Calendar = .current) throws -> WeeklySummary {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? reference
        let trips = try fetch(in: DateInterval(start: weekStart, end: weekEnd))
        let business = trips.filter { $0.classification == .business }
        let personal = trips.filter { $0.classification == .personal }
        let undecided = trips.filter { $0.classification == .undecided }
        return WeeklySummary(
            weekStart: weekStart,
            tripCount: trips.count,
            businessMeters: business.reduce(0) { $0 + $1.distanceMeters },
            personalMeters: personal.reduce(0) { $0 + $1.distanceMeters },
            undecidedCount: undecided.count,
            businessCount: business.count
        )
    }
}

struct WeeklySummary: Hashable, Sendable {
    var weekStart: Date
    var tripCount: Int
    var businessMeters: Double
    var personalMeters: Double
    var undecidedCount: Int
    var businessCount: Int
}
