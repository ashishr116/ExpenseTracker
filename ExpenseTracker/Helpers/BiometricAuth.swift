//
//  BiometricAuth.swift
//  ExpenseTracker
//

import LocalAuthentication

/// Asks the person to prove it's them with Face ID, falling back to the device passcode.
enum BiometricAuth {
    enum Outcome {
        /// They passed Face ID or entered the passcode.
        case success
        /// They cancelled or didn't pass.
        case failed
        /// The device has no Face ID and no passcode set, so there is nothing to check against.
        case unavailable
    }

    /// Shows the system Face ID prompt. Passcode is offered if Face ID fails or isn't set up.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable
        }
        do {
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return passed ? .success : .failed
        } catch {
            return .failed
        }
    }
}
