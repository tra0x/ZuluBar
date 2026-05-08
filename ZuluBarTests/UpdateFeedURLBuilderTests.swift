import XCTest
@testable import ZuluBar

final class UpdateFeedURLBuilderTests: XCTestCase {
    func testBuildAddsKeyQuery() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml", key: "customer-key")

        XCTAssertEqual(url, "https://zulubar.app/appcast.xml?key=customer-key")
    }

    func testBuildKeepsExistingNonKeyQueryItems() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml?channel=paid", key: "customer-key")

        XCTAssertEqual(url, "https://zulubar.app/appcast.xml?channel=paid&key=customer-key")
    }

    func testBuildReplacesExistingKeyQuery() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml?key=old&channel=paid", key: "new")

        XCTAssertEqual(url, "https://zulubar.app/appcast.xml?channel=paid&key=new")
    }

    func testBuildEncodesSpecialCharactersInKey() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml", key: "a+b&c=d?")

        XCTAssertEqual(url, "https://zulubar.app/appcast.xml?key=a+b%26c%3Dd?")
    }

    func testBuildReturnsNilForEmptyKey() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml", key: "")

        XCTAssertNil(url)
    }

    func testBuildReturnsNilForMissingKey() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "https://zulubar.app/appcast.xml", key: nil)

        XCTAssertNil(url)
    }

    func testBuildReturnsNilForInvalidBaseURL() {
        let url = UpdateFeedURLBuilder.build(baseURLString: "", key: "customer-key")

        XCTAssertNil(url)
    }
}
