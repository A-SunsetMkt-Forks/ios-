// MARK: - VaultListEffect

/// Effects that can be processed by a `VaultListProcessor`.
enum VaultListEffect: Equatable {
    /// The vault list appeared on screen.
    case appeared

    /// Check if the user is eligible for an app review prompt.
    case checkAppReviewEligibility

    /// The flight recorder toast banner was dismissed.
    case dismissFlightRecorderToastBanner

    /// The user tapped the dismiss button on the import logins action card.
    case dismissImportLoginsActionCard

    /// The more button on an item in the vault group was tapped.
    ///
    /// - Parameter item: The item associated with the more button that was tapped.
    ///
    case morePressed(_ item: VaultListItem)

    /// A Profile Switcher Effect.
    case profileSwitcher(ProfileSwitcherEffect)

    /// Refreshes the account profiles.
    case refreshAccountProfiles

    /// Refresh the vault list's data.
    case refreshVault

    /// Searches based on the keyword.
    case search(String)

    /// Stream the user's accounts setup progress.
    case streamAccountSetupProgress

    /// Stream the active flight recorder log.
    case streamFlightRecorderLog

    /// Stream the list of organizations for the user.
    case streamOrganizations

    /// Stream the show web icons setting.
    case streamShowWebIcons

    /// Stream the vault list for the user.
    case streamVaultList

    /// The try again button was tapped on the error view.
    case tryAgainTapped
}
