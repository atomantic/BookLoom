import Foundation
import Testing
@testable import BookLoom

struct MeetingDirectionsTests {
    @Test func directionsURLIsNilForBlankLocation() {
        #expect(MeetingDirections.directionsURL(for: "   ") == nil)
    }

    @Test func directionsURLOpensAppleMapsWithDestination() throws {
        let url = try #require(MeetingDirections.directionsURL(for: "Riverside Library Room B"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "http")
        #expect(components.host == "maps.apple.com")
        #expect(components.queryItems?.contains(URLQueryItem(name: "daddr", value: "Riverside Library Room B")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "dirflg", value: "d")) == true)
    }
}
