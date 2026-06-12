import Foundation

enum MeetingDirections {
    static func directionsURL(for location: String) -> URL? {
        let destination = location.trimmed
        guard !destination.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components.url
    }
}
