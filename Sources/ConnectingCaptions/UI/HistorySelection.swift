import Foundation

enum HistorySelection {
    static func resolve(_ selectedID: UUID?, availableIDs: [UUID]) -> UUID? {
        if let selectedID, availableIDs.contains(selectedID) {
            return selectedID
        }
        return availableIDs.first
    }
}
