import BitwardenSdk
import Foundation

// MARK: - ItemListProcessor

/// A `Processor` that can process `ItemListAction` and `ItemListEffect` objects.
final class ItemListProcessor: StateProcessor<ItemListState, ItemListAction, ItemListEffect> {
    // MARK: Types

    typealias Services = HasCameraService
        & HasErrorReporter
        & HasPasteboardService
        & HasTOTPService
        & HasTimeProvider
        & HasTokenRepository

    // MARK: Private Properties

    /// The `Coordinator` for this processor.
    private var coordinator: any Coordinator<ItemListRoute, ItemListEvent>

    /// The services for this processor.
    private var services: Services

    /// An object to manage TOTP code expirations and batch refresh calls for the group.
    private var groupTotpExpirationManager: TOTPExpirationManager?

    // MARK: Initialization

    /// Creates a new `ItemListProcessor`.
    ///
    /// - Parameters:
    ///   - coordinator: The `Coordinator` for this processor.
    ///   - services: The services for this processor.
    ///   - state: The initial state of this processor.
    ///
    init(
        coordinator: any Coordinator<ItemListRoute, ItemListEvent>,
        services: Services,
        state: ItemListState
    ) {
        self.coordinator = coordinator
        self.services = services

        super.init(state: state)
        groupTotpExpirationManager = .init(
            timeProvider: services.timeProvider,
            onExpiration: { [weak self] expiredItems in
                guard let self else { return }
                Task {
                    await self.refreshTOTPCodes(for: expiredItems)
                }
            }
        )
    }

    // MARK: Methods

    override func perform(_ effect: ItemListEffect) async {
        switch effect {
        case .addItemPressed:
            await setupTotp()
        case .appeared:
            await streamItemList()
        case .refresh:
            await streamItemList()
        case .streamVaultList:
            await streamItemList()
        }
    }

    override func receive(_ action: ItemListAction) {
        switch action {
        case .clearURL:
            break
        case let .copyTOTPCode(code):
            services.pasteboardService.copy(code)
            state.toast = Toast(text: Localizations.valueHasBeenCopied(Localizations.verificationCode))
        case let .itemPressed(item):
            coordinator.navigate(to: .viewToken(id: item.id))
        case .morePressed:
            break
        case let .toastShown(newValue):
            state.toast = newValue
        }
    }

    // MARK: Private Methods

    /// Refreshes the vault group's TOTP Codes.
    ///
    private func refreshTOTPCodes(for items: [ItemListItem]) async {
        guard case .data = state.loadingState else { return }
        let refreshedItems = await items.asyncMap { item in
            do {
                let refreshedCode = try await services.tokenRepository.refreshTotpCode(for: item.token.key)
                return ItemListItem(
                    id: item.id,
                    name: item.name,
                    token: item.token,
                    totpCode: refreshedCode
                )
            } catch {
                services.errorReporter.log(error: TOTPServiceError
                    .unableToGenerateCode("Unable to refresh TOTP code for list view item: \(item.id)"))
                return item
            }
        }
        groupTotpExpirationManager?.configureTOTPRefreshScheduling(for: refreshedItems)
        state.loadingState = .data(refreshedItems)
    }

    /// Kicks off the TOTP setup flow.
    ///
    private func setupTotp() async {
        guard services.cameraService.deviceSupportsCamera() else {
            coordinator.navigate(to: .setupTotpManual, context: self)
            return
        }
        let status = await services.cameraService.checkStatusOrRequestCameraAuthorization()
        if status == .authorized {
            await coordinator.handleEvent(.showScanCode, context: self)
        } else {
            coordinator.navigate(to: .setupTotpManual, context: self)
        }
    }

    /// Stream the items list.
    private func streamItemList() async {
        do {
            for try await tokenList in try await services.tokenRepository.tokenPublisher() {
                let itemList = try await tokenList.asyncMap { token in
                    let code = try await services.tokenRepository.refreshTotpCode(for: token.key)
                    return ItemListItem(id: token.id, name: token.name, token: token, totpCode: code)
                }
                groupTotpExpirationManager?.configureTOTPRefreshScheduling(for: itemList)
                state.loadingState = .data(itemList)
            }
        } catch {
            services.errorReporter.log(error: error)
        }
    }
}

/// A class to manage TOTP code expirations for the ItemListProcessor and batch refresh calls.
///
private class TOTPExpirationManager {
    // MARK: Properties

    /// A closure to call on expiration
    ///
    var onExpiration: (([ItemListItem]) -> Void)?

    // MARK: Private Properties

    /// All items managed by the object, grouped by TOTP period.
    ///
    private(set) var itemsByInterval = [UInt32: [ItemListItem]]()

    /// A model to provide time to calculate the countdown.
    ///
    private var timeProvider: any TimeProvider

    /// A timer that triggers `checkForExpirations` to manage code expirations.
    ///
    private var updateTimer: Timer?

    /// Initializes a new countdown timer
    ///
    /// - Parameters
    ///   - timeProvider: A protocol providing the present time as a `Date`.
    ///         Used to calculate time remaining for a present TOTP code.
    ///   - onExpiration: A closure to call on code expiration for a list of vault items.
    ///
    init(
        timeProvider: any TimeProvider,
        onExpiration: (([ItemListItem]) -> Void)?
    ) {
        self.timeProvider = timeProvider
        self.onExpiration = onExpiration
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true,
            block: { _ in
                self.checkForExpirations()
            }
        )
    }

    /// Clear out any timers tracking TOTP code expiration
    deinit {
        cleanup()
    }

    // MARK: Methods

    /// Configures TOTP code refresh scheduling
    ///
    /// - Parameter items: The vault list items that may require code expiration tracking.
    ///
    func configureTOTPRefreshScheduling(for items: [ItemListItem]) {
        var newItemsByInterval = [UInt32: [ItemListItem]]()
        items.forEach { item in
            newItemsByInterval[item.totpCode.period, default: []].append(item)
        }
        itemsByInterval = newItemsByInterval
    }

    /// A function to remove any outstanding timers
    ///
    func cleanup() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func checkForExpirations() {
        var expired = [ItemListItem]()
        var notExpired = [UInt32: [ItemListItem]]()
        itemsByInterval.forEach { period, items in
            let sortedItems: [Bool: [ItemListItem]] = TOTPExpirationCalculator.listItemsByExpiration(
                items,
                timeProvider: timeProvider
            )
            expired.append(contentsOf: sortedItems[true] ?? [])
            notExpired[period] = sortedItems[false]
        }
        itemsByInterval = notExpired
        guard !expired.isEmpty else { return }
        onExpiration?(expired)
    }
}

extension ItemListProcessor: AuthenticatorKeyCaptureDelegate {
    func didCompleteCapture(
        _ captureCoordinator: AnyCoordinator<AuthenticatorKeyCaptureRoute, AuthenticatorKeyCaptureEvent>,
        with value: String
    ) {
        let dismissAction = DismissAction(action: { [weak self] in
            self?.parseAndValidateCapturedAuthenticatorKey(value)
        })
        captureCoordinator.navigate(to: .dismiss(dismissAction))
    }

    func parseAndValidateCapturedAuthenticatorKey(_ key: String) {
        do {
            let authKeyModel = try services.totpService.getTOTPConfiguration(key: key)
            let loginTotpState = LoginTOTPState(authKeyModel: authKeyModel)
            guard let key = loginTotpState.rawAuthenticatorKeyString,
                  let newToken = Token(name: "Example", authenticatorKey: key)
            else { return }
            Task {
                try await services.tokenRepository.addToken(newToken)
                await perform(.refresh)
            }
            state.toast = Toast(text: Localizations.authenticatorKeyAdded)
        } catch {
            // Replace with better alerts later
//            coordinator.navigate(to: .alert(.totpScanFailureAlert()))
        }
    }

    func showCameraScan(
        _ captureCoordinator: AnyCoordinator<AuthenticatorKeyCaptureRoute, AuthenticatorKeyCaptureEvent>
    ) {
        guard services.cameraService.deviceSupportsCamera() else { return }
        let dismissAction = DismissAction(action: { [weak self] in
            guard let self else { return }
            Task {
                await self.coordinator.handleEvent(.showScanCode, context: self)
            }
        })
        captureCoordinator.navigate(to: .dismiss(dismissAction))
    }

    func showManualEntry(
        _ captureCoordinator: AnyCoordinator<AuthenticatorKeyCaptureRoute, AuthenticatorKeyCaptureEvent>
    ) {
        let dismissAction = DismissAction(action: { [weak self] in
            self?.coordinator.navigate(to: .setupTotpManual, context: self)
        })
        captureCoordinator.navigate(to: .dismiss(dismissAction))
    }
}
