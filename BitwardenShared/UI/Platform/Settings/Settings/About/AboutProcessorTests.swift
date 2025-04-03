import BitwardenKitMocks
import InlineSnapshotTesting
import TestHelpers
import XCTest

@testable import BitwardenShared

class AboutProcessorTests: BitwardenTestCase {
    // MARK: Properties

    var appInfoService: MockAppInfoService!
    var configService: MockConfigService!
    var coordinator: MockCoordinator<SettingsRoute, SettingsEvent>!
    var environmentService: MockEnvironmentService!
    var errorReporter: MockErrorReporter!
    var pasteboardService: MockPasteboardService!
    var subject: AboutProcessor!

    // MARK: Setup and Teardown

    override func setUp() {
        super.setUp()

        appInfoService = MockAppInfoService()
        configService = MockConfigService()
        coordinator = MockCoordinator<SettingsRoute, SettingsEvent>()
        environmentService = MockEnvironmentService()
        errorReporter = MockErrorReporter()
        pasteboardService = MockPasteboardService()

        subject = AboutProcessor(
            coordinator: coordinator.asAnyCoordinator(),
            services: ServiceContainer.withMocks(
                appInfoService: appInfoService,
                configService: configService,
                environmentService: environmentService,
                errorReporter: errorReporter,
                pasteboardService: pasteboardService,
                systemDevice: MockSystemDevice()
            ),
            state: AboutState()
        )
    }

    override func tearDown() {
        super.tearDown()

        coordinator = nil
        configService = nil
        environmentService = nil
        errorReporter = nil
        pasteboardService = nil
        subject = nil
    }

    // MARK: Tests

    /// `init` sets the correct crash logs setting and app info.
    @MainActor
    func test_init_loadsValues() {
        errorReporter.isEnabled = true

        subject = AboutProcessor(
            coordinator: coordinator.asAnyCoordinator(),
            services: ServiceContainer.withMocks(
                appInfoService: appInfoService,
                errorReporter: errorReporter,
                systemDevice: MockSystemDevice()
            ),
            state: AboutState()
        )

        XCTAssertEqual(subject.state.copyrightText, "© Bitwarden Inc. 2015–2025")
        XCTAssertTrue(subject.state.isSubmitCrashLogsToggleOn)
        XCTAssertEqual(subject.state.version, "1.0 (1)")
    }

    /// `perform(_:)` with `.loadData` loads the flight recorder feature flag.
    @MainActor
    func test_perform_loadData_flightRecorderFeatureFlag() async {
        configService.featureFlagsBool[.flightRecorder] = true
        await subject.perform(.loadData)
        XCTAssertTrue(subject.state.isFlightRecorderFeatureFlagEnabled)

        configService.featureFlagsBool[.flightRecorder] = false
        await subject.perform(.loadData)
        XCTAssertFalse(subject.state.isFlightRecorderFeatureFlagEnabled)
    }

    /// `receive(_:)` with `.clearAppReviewURL` clears the app review URL in the state.
    @MainActor
    func test_receive_clearAppReviewURL() {
        subject.state.appReviewUrl = .example
        subject.receive(.clearAppReviewURL)
        XCTAssertNil(subject.state.appReviewUrl)
    }

    /// `receive(_:)` with `.clearURL` clears the URL in the state.
    @MainActor
    func test_receive_clearURL() {
        subject.state.url = .example
        subject.receive(.clearURL)
        XCTAssertNil(subject.state.url)
    }

    /// `receive(_:)` with `.helpCenterTapped` set the URL to open in the state.
    @MainActor
    func test_receive_helpCenterTapped() {
        subject.receive(.helpCenterTapped)
        XCTAssertEqual(subject.state.url, ExternalLinksConstants.helpAndFeedback)
    }

    /// `receive(_:)` with `.learnAboutOrganizationsTapped` shows an alert for navigating to the website
    /// When `Continue` is tapped on the alert, sets the URL to open in the state.
    @MainActor
    func test_receive_learnAboutOrganizationsTapped() async throws {
        subject.receive(.learnAboutOrganizationsTapped)

        let alert = try XCTUnwrap(coordinator.alertShown.last)
        try await alert.tapAction(title: Localizations.continue)
        XCTAssertEqual(subject.state.url, ExternalLinksConstants.aboutOrganizations)
    }

    /// `receive(_:)` with `.privacyPolicyTapped` shows an alert for navigating to the Privacy Policy
    /// When `Continue` is tapped on the alert, sets the URL to open in the state.
    @MainActor
    func test_receive_privacyPolicyTapped() async throws {
        subject.receive(.privacyPolicyTapped)

        let alert = try XCTUnwrap(coordinator.alertShown.last)
        try await alert.tapAction(title: Localizations.continue)
        XCTAssertEqual(subject.state.url, ExternalLinksConstants.privacyPolicy)
    }

    /// `receive(_:)` with `.rateTheAppTapped` shows an alert for navigating to the app store.
    /// When `Continue` is tapped on the alert, the `appReviewUrl` is populated.
    @MainActor
    func test_receive_rateTheAppTapped() async throws {
        subject.receive(.rateTheAppTapped)

        let alert = try XCTUnwrap(coordinator.alertShown.last)
        try await alert.tapAction(title: Localizations.continue)
        XCTAssertEqual(
            subject.state.appReviewUrl?.absoluteString,
            "https://itunes.apple.com/us/app/id1137397744?action=write-review"
        )
    }

    /// `receive(_:)` with `.toastShown` updates the state's toast value.
    @MainActor
    func test_receive_toastShown() {
        let toast = Toast(title: "toast!")
        subject.receive(.toastShown(toast))
        XCTAssertEqual(subject.state.toast, toast)

        subject.receive(.toastShown(nil))
        XCTAssertNil(subject.state.toast)
    }

    /// `receive(_:)` with action `.isFlightRecorderToggleOn` updates the toggle value in the state.
    @MainActor
    func test_receive_toggleFlightRecorder() {
        XCTAssertFalse(subject.state.isFlightRecorderToggleOn)

        subject.receive(.toggleFlightRecorder(true))

        XCTAssertTrue(subject.state.isFlightRecorderToggleOn)
    }

    /// `receive(_:)` with action `.isSubmitCrashLogsToggleOn` updates the toggle value in the state.
    @MainActor
    func test_receive_toggleSubmitCrashLogs() {
        errorReporter.isEnabled = false
        XCTAssertFalse(subject.state.isSubmitCrashLogsToggleOn)

        subject.receive(.toggleSubmitCrashLogs(true))

        XCTAssertTrue(subject.state.isSubmitCrashLogsToggleOn)
        XCTAssertTrue(errorReporter.isEnabled)
    }

    /// `receive(_:)` with action `.versionTapped` copies the copyright, the version string
    /// and device info to the pasteboard..
    @MainActor
    func test_receive_versionTapped() {
        subject.receive(.versionTapped)
        XCTAssertEqual(
            pasteboardService.copiedString,
            """
            © Bitwarden Inc. 2015–2025

            Version: 1.0 (1)
            📱 iPhone14,2 🍏 iOS 16.4 📦 Production
            """
        )
        XCTAssertEqual(subject.state.toast, Toast(title: Localizations.valueHasBeenCopied(Localizations.appInfo)))
    }

    /// `receive(_:)` with `.webVaultTapped` shows an alert for navigating to the web vault
    /// When `Continue` is tapped on the alert, sets the URL to open in the state.
    @MainActor
    func test_receive_webVaultTapped() async throws {
        subject.receive(.webVaultTapped)

        let alert = try XCTUnwrap(coordinator.alertShown.last)
        try await alert.tapAction(title: Localizations.continue)
        XCTAssertEqual(subject.state.url, environmentService.webVaultURL)
    }
}
