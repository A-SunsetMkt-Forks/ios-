// MARK: - ItemListAction

/// Actions that can be processed by a `ItemListProcessor`.
enum ItemListAction: Equatable {
    /// The url has been opened so clear the value in the state.
    case clearURL

    /// The copy TOTP Code button was pressed.
    ///
    case copyTOTPCode(_ code: String)

    /// An item in the vault group was tapped.
    ///
    /// - Parameter item: The item that was tapped.
    ///
    case itemPressed(_ item: ItemListItem)

    /// The toast was shown or hidden.
    case toastShown(Toast?)
}
