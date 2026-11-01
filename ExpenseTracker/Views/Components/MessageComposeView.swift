//
//  MessageComposeView.swift
//  ExpenseTracker
//

import MessageUI
import SwiftUI

/// SwiftUI wrapper around the system Messages composer.
///
/// iOS doesn't let apps send texts silently: this shows the standard compose screen with the
/// recipient and body pre-filled, and the person taps Send. Messages then delivers it via
/// iMessage or SMS through the phone's carrier (e.g. Airtel / Jio).
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    /// Called when the composer closes, with whether the message was sent.
    var onFinish: (_ sent: Bool) -> Void

    /// Whether this device can send text messages (false on the Simulator).
    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish(result == .sent)
        }
    }
}

/// Presents the Messages composer for a reminder, or — on devices that can't send texts
/// (like the Simulator) — a preview with Share and Copy options instead.
struct ReminderSheet: View {
    let reminder: LoanReminder
    var onSent: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if MessageComposeView.canSendText {
            MessageComposeView(
                recipients: reminder.phone.isEmpty ? [] : [reminder.phone],
                body: reminder.messageBody
            ) { sent in
                if sent { onSent() }
                dismiss()
            }
            .ignoresSafeArea()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        NavigationStack {
            List {
                Section {
                    Text(reminder.messageBody)
                        .textSelection(.enabled)
                } header: {
                    Text(reminder.phone.isEmpty ? "To \(reminder.friendName)" : "To \(reminder.friendName) · \(reminder.phone)")
                } footer: {
                    Text("This device can't send text messages. Share or copy the reminder instead.")
                }

                Section {
                    ShareLink(item: reminder.messageBody) {
                        Label("Share Reminder", systemImage: "square.and.arrow.up")
                    }
                    Button("Copy Text", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = reminder.messageBody
                    }
                }
            }
            .navigationTitle("Payment Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Presents the Messages composer for a borrowing confirmation message, or fallback preview.
struct BorrowingMessageSheet: View {
    let message: BorrowingMessage
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if MessageComposeView.canSendText {
            MessageComposeView(
                recipients: message.phone.isEmpty ? [] : [message.phone],
                body: message.messageBody
            ) { _ in
                dismiss()
                onDismiss()
            }
            .ignoresSafeArea()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        NavigationStack {
            List {
                Section {
                    Text(message.messageBody)
                        .textSelection(.enabled)
                } header: {
                    Text(message.phone.isEmpty ? "To \(message.friendName)" : "To \(message.friendName) · \(message.phone)")
                } footer: {
                    Text("This device can't send text messages. Share or copy the confirmation instead.")
                }

                Section {
                    ShareLink(item: message.messageBody) {
                        Label("Share Confirmation", systemImage: "square.and.arrow.up")
                    }
                    Button("Copy Text", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = message.messageBody
                    }
                }
            }
            .navigationTitle("Borrow Confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }
}
