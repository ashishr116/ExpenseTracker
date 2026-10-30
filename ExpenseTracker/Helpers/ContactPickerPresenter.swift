//
//  ContactPickerPresenter.swift
//  ExpenseTracker
//

import ContactsUI
import UIKit

/// Shows the system contact picker on top of whatever is on screen.
///
/// The picker is presented directly with UIKit. Wrapping it in a SwiftUI sheet made choosing a contact
/// close the sheet underneath as well, so the whole form (and what was typed in it) disappeared.
/// The picker needs no Contacts permission: the app only receives the contact that is chosen.
@MainActor
final class ContactPickerPresenter: NSObject, CNContactPickerDelegate {
    static let shared = ContactPickerPresenter()

    private var onSelect: ((CNContact) -> Void)?

    /// Presents the picker. Only contacts with a phone number can be chosen.
    func present(onSelect: @escaping (CNContact) -> Void) {
        guard let presenter = Self.topViewController() else { return }
        self.onSelect = onSelect

        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        presenter.present(picker, animated: true)
    }

    // MARK: CNContactPickerDelegate

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        // The picker closes itself after a selection.
        Task { @MainActor in
            let callback = onSelect
            onSelect = nil
            callback?(contact)
        }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        Task { @MainActor in onSelect = nil }
    }

    // MARK: Finding where to present

    /// The view controller currently on top, including any sheets, so the picker appears above them.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
