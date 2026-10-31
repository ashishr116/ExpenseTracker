//
//  DataBackupView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Export your data as CSV files, or save and restore a full backup that can live in iCloud Drive.
struct DataBackupView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var loans: [Loan]
    @Query private var accounts: [Account]

    @AppStorage(BackupManager.lastBackupKey) private var lastBackup = 0.0

    @State private var backupDocument = BackupDocument()
    @State private var isExportingBackup = false
    @State private var isChoosingRestoreFile = false
    @State private var pendingRestore: Data?
    @State private var message: Message?

    private struct Message: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Expenses", value: expenses.count, format: .number)
                LabeledContent("Income", value: incomes.count, format: .number)
                LabeledContent("Loans", value: loans.count, format: .number)
                LabeledContent("Accounts", value: accounts.count, format: .number)
            } header: {
                Text("What's Stored on This Device")
            }

            Section {
                Button("Export CSV Files", systemImage: "tablecells") {
                    exportCSV()
                }
            } header: {
                Text("Spreadsheet")
            } footer: {
                Text("Creates one file for each list: expenses, income, loans, repayments, EMIs, insurance, investments, accounts, transfers and saved cards. Choose Save to Files, then iCloud Drive, or send them by email. Full card numbers and CVV are never exported.")
            }

            Section {
                Button("Back Up to Files or iCloud Drive", systemImage: "icloud.and.arrow.up") {
                    makeBackup()
                }
                if lastBackup > 0 {
                    LabeledContent("Last Backup") {
                        Text(Date(timeIntervalSince1970: lastBackup), format: .dateTime.day().month().year().hour().minute())
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves everything in one file you can restore later. In the save sheet, choose iCloud Drive to keep it in iCloud. Backups are not automatic, so make one after big changes. You'll be reminded after 30 days without one. Full card numbers, expiry and CVV are not included.")
            }

            Section {
                Button("Restore from Backup", systemImage: "icloud.and.arrow.down", role: .destructive) {
                    isChoosingRestoreFile = true
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Replaces everything on this device with the contents of a backup file. Reminders and the month-end savings choices are not part of a backup. Set them again if needed.")
            }
        }
        .navigationTitle("Backup & Export")
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "ExpenseTracker-Backup-\(Date.now.fileNameStamp)"
        ) { result in
            switch result {
            case .success:
                lastBackup = Date.now.timeIntervalSince1970
                // The 30 days start again, so the reminder moves to match.
                Task { await BackupNudge.scheduleReminder() }
                message = Message(title: "Backup Saved", text: "Your backup was saved. Keep it somewhere safe, such as iCloud Drive.")
            case .failure(let error):
                message = Message(title: "Backup Failed", text: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isChoosingRestoreFile, allowedContentTypes: [.json]) { result in
            readRestoreFile(result)
        }
        .confirmationDialog(
            "Replace all data on this device?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace Everything", role: .destructive) { restore() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Everything currently in the app is deleted and replaced by the backup. This can't be undone.")
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Actions

    private func exportCSV() {
        do {
            let files = try CSVExporter.makeFiles(from: modelContext)
            SharePresenter.present(urls: files)
        } catch {
            message = Message(title: "Export Failed", text: error.localizedDescription)
        }
    }

    private func makeBackup() {
        do {
            backupDocument = BackupDocument(data: try BackupManager.makeBackup(from: modelContext))
            isExportingBackup = true
        } catch {
            message = Message(title: "Backup Failed", text: error.localizedDescription)
        }
    }

    private func readRestoreFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = Message(title: "Couldn't Open the File", text: error.localizedDescription)
        case .success(let url):
            // Files outside the app's own folder need permission to be read.
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // Check the file is a real backup before asking to replace anything.
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard (try? decoder.decode(BackupFile.self, from: data)) != nil else { throw BackupError.unreadable }
                pendingRestore = data
            } catch {
                message = Message(title: "Couldn't Open the File", text: error.localizedDescription)
            }
        }
    }

    private func restore() {
        guard let data = pendingRestore else { return }
        pendingRestore = nil
        do {
            try BackupManager.restore(data, into: modelContext)
            message = Message(title: "Restored", text: "Your data was restored from the backup.")
        } catch {
            message = Message(title: "Restore Failed", text: error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        DataBackupView()
    }
    .modelContainer(for: [Expense.self, Income.self, Loan.self, Account.self], inMemory: true)
}
