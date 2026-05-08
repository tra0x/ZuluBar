import XCTest
@testable import ZuluBar

final class UpdateKeyStoreTests: XCTestCase {
    private var store: UpdateKeyStore!

    override func setUp() {
        super.setUp()
        store = UpdateKeyStore(service: "app.zulubar.tests.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.delete()
        store = nil
        super.tearDown()
    }

    func testLoadReturnsNilWhenNoKeyExists() {
        XCTAssertNil(store.load())
    }

    func testSaveAndLoadRoundTrip() throws {
        try store.save("customer-key-123")

        XCTAssertEqual(store.load(), "customer-key-123")
    }

    func testSaveOverwritesExistingKey() throws {
        try store.save("old-key")
        try store.save("new-key")

        XCTAssertEqual(store.load(), "new-key")
    }

    func testDeleteRemovesKey() throws {
        try store.save("customer-key-123")
        try store.delete()

        XCTAssertNil(store.load())
    }
}
