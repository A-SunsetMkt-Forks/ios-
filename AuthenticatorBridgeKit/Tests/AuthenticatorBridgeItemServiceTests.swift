import AuthenticatorBridgeKit
import AuthenticatorBridgeKitMocks
import BitwardenKit
import BitwardenKitMocks
import Foundation
import TestHelpers
import XCTest

// swiftlint:disable file_length type_body_length

final class AuthenticatorBridgeItemServiceTests: AuthenticatorBridgeKitTestCase {
    // MARK: Properties

    let accessGroup = "group.com.example.bitwarden-authenticator"
    var cryptoService: MockSharedCryptographyService!
    var dataStore: AuthenticatorBridgeDataStore!
    var errorReporter: ErrorReporter!
    var keychainRepository: MockSharedKeychainRepository!
    var sharedTimeoutService: MockSharedTimeoutService!
    var subject: AuthenticatorBridgeItemService!

    // MARK: Setup & Teardown

    override func setUp() {
        super.setUp()
        cryptoService = MockSharedCryptographyService()
        errorReporter = MockErrorReporter()
        dataStore = AuthenticatorBridgeDataStore(
            errorReporter: errorReporter,
            groupIdentifier: accessGroup,
            storeType: .memory
        )
        keychainRepository = MockSharedKeychainRepository()
        sharedTimeoutService = MockSharedTimeoutService()
        subject = DefaultAuthenticatorBridgeItemService(
            cryptoService: cryptoService,
            dataStore: dataStore,
            sharedKeychainRepository: keychainRepository,
            sharedTimeoutService: sharedTimeoutService
        )
    }

    override func tearDown() {
        cryptoService = nil
        dataStore = nil
        errorReporter = nil
        keychainRepository = nil
        sharedTimeoutService = nil
        subject = nil
        super.tearDown()
    }

    // MARK: Tests

    /// `deleteAll()` deletes all items for all users in the shared store,
    /// and deletes the authenticator key.
    ///
    func test_deleteAll_success() async throws {
        try await subject.insertItems(
            AuthenticatorBridgeItemDataView.fixtures(),
            forUserId: "userID 1"
        )

        try await subject.insertItems(
            AuthenticatorBridgeItemDataView.fixtures(),
            forUserId: "userID 2"
        )

        keychainRepository.authenticatorKey = keychainRepository.generateMockKeyData()

        try await subject.deleteAll()

        // Verify items were deleted
        let fetchResultOne = try await subject.fetchAllForUserId("userID 1")
        XCTAssertNotNil(fetchResultOne)
        XCTAssertEqual(fetchResultOne.count, 0)

        let fetchResultTwo = try await subject.fetchAllForUserId("userID 2")
        XCTAssertNotNil(fetchResultTwo)
        XCTAssertEqual(fetchResultTwo.count, 0)

        XCTAssertNil(keychainRepository.authenticatorKey)
    }

    /// `deleteAll()` rethrows errors.
    ///
    func test_deleteAll_error() async throws {
        try await subject.insertItems(
            AuthenticatorBridgeItemDataView.fixtures(),
            forUserId: "userID 1"
        )

        try await subject.insertItems(
            AuthenticatorBridgeItemDataView.fixtures(),
            forUserId: "userID 2"
        )

        keychainRepository.errorToThrow = BitwardenTestError.example

        await assertAsyncThrows(error: BitwardenTestError.example) {
            try await subject.deleteAll()
        }
    }

    /// Verify that the `deleteAllForUserId` method successfully deletes all of the data for a given
    /// userId from the store. Verify that it does NOT delete the data for a different userId
    ///
    func test_deleteAllForUserId_success() async throws {
        let items = AuthenticatorBridgeItemDataView.fixtures()

        // First Insert for "userId"
        try await subject.insertItems(items, forUserId: "userId")

        // Separate Insert for "differentUserId"
        try await subject.insertItems(AuthenticatorBridgeItemDataView.fixtures(),
                                      forUserId: "differentUserId")

        // Remove the items for "differentUserId"
        try await subject.deleteAllForUserId("differentUserId")

        // Verify items are removed for "differentUserId"
        let deletedFetchResult = try await subject.fetchAllForUserId("differentUserId")

        XCTAssertNotNil(deletedFetchResult)
        XCTAssertEqual(deletedFetchResult.count, 0)

        // Verify items are still present for "userId"
        let result = try await subject.fetchAllForUserId("userId")

        XCTAssertNotNil(result)
        XCTAssertEqual(result.count, items.count)
    }

    /// Verify that the `fetchAllForUserId` method successfully fetches the data for the given user id, and does not
    /// include data for a different user id.
    ///
    func test_fetchAllForUserId_success() async throws {
        // Insert items for "userId"
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(expectedItems, forUserId: "userId")

        // Separate Insert for "differentUserId"
        let differentUserItem = AuthenticatorBridgeItemDataView.fixture()
        try await subject.insertItems([differentUserItem], forUserId: "differentUserId")

        // Fetch should return only the expectedItem
        let result = try await subject.fetchAllForUserId("userId")

        XCTAssertTrue(cryptoService.decryptCalled,
                      "Items should have been decrypted when calling fetchAllForUser!")
        XCTAssertNotNil(result)
        XCTAssertEqual(result.count, expectedItems.count)
        XCTAssertEqual(result, expectedItems)

        // None of the items for userId should contain the item inserted for differentUserId
        let emptyResult = result.filter { $0.id == differentUserItem.id }
        XCTAssertEqual(emptyResult.count, 0)
    }

    /// When no temporary item has been stored,  `fetchTemporaryItem()` returns `nil`
    ///
    func test_fetchTemporaryItem_emptyResult() async throws {
        let result = try await subject.fetchTemporaryItem()
        XCTAssertNil(result)
    }

    /// Verify that the `fetchTemporaryItem()` is able to fetch the temporary item that was inserted
    /// and removes it after fetching.
    ///
    func test_fetchTemporaryItem_success() async throws {
        let expectedItem = AuthenticatorBridgeItemDataView.fixture()
        try await subject.insertTemporaryItem(expectedItem)
        let result = try await subject.fetchTemporaryItem()
        XCTAssertEqual(result, expectedItem)

        let retryResult = try await subject.fetchTemporaryItem()
        XCTAssertNil(retryResult)
    }

    /// Verify that the `insertItems(_:forUserId:)` method successfully inserts the list of items
    /// for the given user id.
    ///
    func test_insertItemsForUserId_success() async throws {
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(expectedItems, forUserId: "userId")
        let result = try await subject.fetchAllForUserId("userId")

        XCTAssertTrue(cryptoService.encryptCalled,
                      "Items should have been encrypted before inserting!!")
        XCTAssertEqual(result, expectedItems)
    }

    /// When `insertTemporaryItem(_)` is called multiple times, it should replace the temporary
    /// item - i.e. only the last item will end up stored.
    ///
    func test_insertTemporaryItem_replacesItem() async throws {
        let initialItem = AuthenticatorBridgeItemDataView.fixture(name: "Initial Insert")
        let expectedItem = AuthenticatorBridgeItemDataView.fixture()
        try await subject.insertTemporaryItem(initialItem)
        try await subject.insertTemporaryItem(expectedItem)
        let result = try await subject.fetchTemporaryItem()

        XCTAssertEqual(result, expectedItem)
    }

    /// Verify that the `insertTemporaryItem(_)` method successfully inserts a temporary item that is
    /// then able to be retrieved by `fetchTemporaryItem()`.
    ///
    func test_insertTemporaryItem_success() async throws {
        let expectedItem = AuthenticatorBridgeItemDataView.fixture()
        try await subject.insertTemporaryItem(expectedItem)
        let result = try await subject.fetchTemporaryItem()

        XCTAssertTrue(cryptoService.encryptCalled,
                      "Items should have been encrypted before inserting!!")
        XCTAssertEqual(result, expectedItem)
    }

    /// Verify that `isSyncOn` returns false when the key is not present in the keychain.
    ///
    func test_isSyncOn_false() async throws {
        try keychainRepository.deleteAuthenticatorKey()
        let sync = await subject.isSyncOn()
        XCTAssertFalse(sync)
    }

    /// Verify that `isSyncOn` returns true when the key is present in the keychain.
    ///
    func test_isSyncOn_true() async throws {
        let key = keychainRepository.generateMockKeyData()
        try await keychainRepository.setAuthenticatorKey(key)
        let sync = await subject.isSyncOn()
        XCTAssertTrue(sync)
    }

    /// Verify the `replaceAllItems` correctly deletes all of the items in the store previously when given
    /// an empty list of items to insert for the given userId.
    ///
    func test_replaceAllItems_emptyInsertDeletesExisting() async throws {
        // Insert initial items for "userId"
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(expectedItems, forUserId: "userId")

        // Replace with empty list, deleting all
        try await subject.replaceAllItems(with: [], forUserId: "userId")

        let result = try await subject.fetchAllForUserId("userId")
        XCTAssertEqual(result, [])
    }

    /// Verify the `replaceAllItems` correctly replaces all of the items in the store previously with the new
    /// list of items for the given userId
    ///
    func test_replaceAllItems_replacesExisting() async throws {
        // Insert initial items for "userId"
        let initialItems = [AuthenticatorBridgeItemDataView.fixture()]
        try await subject.insertItems(initialItems, forUserId: "userId")

        // Replace items for "userId"
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.replaceAllItems(with: expectedItems, forUserId: "userId")

        let result = try await subject.fetchAllForUserId("userId")

        XCTAssertTrue(cryptoService.encryptCalled,
                      "Items should have been encrypted before inserting!!")
        XCTAssertEqual(result, expectedItems)
        XCTAssertFalse(result.contains { $0 == initialItems.first })
    }

    /// Verify the `replaceAllItems` correctly inserts items when a userId doesn't contain any
    /// items in the store previously.
    ///
    func test_replaceAllItems_startingFromEmpty() async throws {
        // Insert items for "userId"
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.replaceAllItems(with: expectedItems, forUserId: "userId")

        let result = try await subject.fetchAllForUserId("userId")

        XCTAssertTrue(cryptoService.encryptCalled,
                      "Items should have been encrypted before inserting!!")
        XCTAssertEqual(result, expectedItems)
    }

    /// Verify that the shared items publisher publishes items for all users at once.
    ///
    func test_sharedItemsPublisher_containsAllUsers() async throws {
        let initialItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        let otherUserItems = [AuthenticatorBridgeItemDataView.fixture(name: "New Item")]
        try await subject.insertItems(initialItems, forUserId: "userId")
        try await subject.replaceAllItems(with: otherUserItems, forUserId: "differentUser")

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        waitFor(results.count == 1)
        let combined = (otherUserItems + initialItems)
        XCTAssertEqual(results[0], combined)
    }

    /// Verify that the shared items publisher does not publish any temporary items
    ///
    func test_sharedItemsPublisher_noTemporaryItems() async throws {
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(expectedItems, forUserId: "userId")
        try await subject.insertTemporaryItem(.fixture())

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        try await subject.insertTemporaryItem(.fixture())

        waitFor(results.count == 1)
        XCTAssertEqual(results[0], expectedItems)
    }

    /// Verify that the shared items publisher publishes all the items inserted initially.
    ///
    func test_sharedItemsPublisher_success() async throws {
        let expectedItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(expectedItems, forUserId: "userId")

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        waitFor(results.count == 1)
        XCTAssertEqual(results[0], expectedItems)
    }

    /// Verify that the shared items publisher publishes new lists when items are deleted.
    ///
    func test_sharedItemsPublisher_withDeletes() async throws {
        let initialItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(initialItems, forUserId: "userId")

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        try await subject.replaceAllItems(with: [], forUserId: "userId")

        waitFor(results.count == 2)
        XCTAssertEqual(results[0], initialItems)
        XCTAssertEqual(results[1], [])
    }

    /// Verify that the shared items publisher publishes items that are inserted/replaced later.
    ///
    func test_sharedItemsPublisher_withUpdates() async throws {
        let initialItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(initialItems, forUserId: "userId")

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        let replacedItems = [AuthenticatorBridgeItemDataView.fixture(name: "New Item")]
        try await subject.replaceAllItems(with: replacedItems, forUserId: "userId")

        waitFor(results.count == 2)
        XCTAssertEqual(results[0], initialItems)
        XCTAssertEqual(results[1], replacedItems)
    }

    /// The shared items publisher deletes items if the user is timed out.
    ///
    func test_sharedItemsPublisher_deletesItemsOnTimeout() async throws {
        let pastTimeoutItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        let withinTimeoutItems = [AuthenticatorBridgeItemDataView.fixture(name: "New Item")]
        try await subject.insertItems(pastTimeoutItems, forUserId: "pastTimeoutUserId")
        try await subject.replaceAllItems(with: withinTimeoutItems, forUserId: "withinTimeoutUserId")

        sharedTimeoutService.hasPassedTimeoutResult = .success([
            "pastTimeoutUserId": true,
            "withinTimeoutUserId": false,
        ])

        var results: [[AuthenticatorBridgeItemDataView]] = []
        let publisher = try await subject.sharedItemsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { value in
                    results.append(value)
                }
            )
        defer { publisher.cancel() }

        // Verify items are removed for "userId"
        let itemsForPastTimeoutUser = try await subject.fetchAllForUserId("pastTimeoutUserId")

        XCTAssertNotNil(itemsForPastTimeoutUser)
        XCTAssertEqual(itemsForPastTimeoutUser.count, 0)

        // Verify items are still present for "differentUserId"
        let itemsForWithinTimeoutUser = try await subject.fetchAllForUserId("withinTimeoutUserId")

        XCTAssertNotNil(itemsForWithinTimeoutUser)
        XCTAssertEqual(itemsForWithinTimeoutUser.count, withinTimeoutItems.count)
    }

    /// `sharedItemsPublisher()` throws if checking for logout throws
    ///
    func test_sharedItemsPublisher_logoutError() async throws {
        let initialItems = AuthenticatorBridgeItemDataView.fixtures().sorted { $0.id < $1.id }
        try await subject.insertItems(initialItems, forUserId: "userId")

        sharedTimeoutService.hasPassedTimeoutResult = .failure(BitwardenTestError.example)

        await assertAsyncThrows(error: BitwardenTestError.example) {
            var results: [[AuthenticatorBridgeItemDataView]] = []
            let publisher = try await subject.sharedItemsPublisher()
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { value in
                        results.append(value)
                    }
                )
            publisher.cancel()
        }

        XCTAssertFalse(cryptoService.decryptCalled)
    }
}

// swiftlint:enable file_length type_body_length
