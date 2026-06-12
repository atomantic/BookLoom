import Foundation

/// The shelf filter shared by the iOS (`LibraryTabView`) and macOS
/// (`DesktopLibraryView`) library screens. Both platforms previously declared
/// their own identical `MobileLibraryFilter` / `LibraryFilter` enums; this is
/// the single source of truth.
enum LibraryBookFilter: String, CaseIterable, Identifiable {
    case all
    case owned
    case wishlist
    case loaned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .owned: return "Owned"
        case .wishlist: return "Wishlist"
        case .loaned: return "Loaned"
        }
    }
}
