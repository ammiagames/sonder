//
//  InviteFriendsGateView.swift
//  sonder
//

import SwiftUI
import MessageUI
import Contacts
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "InviteFriendsGateView")

/// Hard gate: invite 3 unique friends before accessing the app.
struct InviteFriendsGateView: View {
    let onComplete: () -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(InviteService.self) private var inviteService
    @Environment(ContactsService.self) private var contactsService

    @State private var showContactsPicker = false
    @State private var manualPhoneDigits = ""
    @State private var showManualEntry = false
    @State private var smsPhoneNumber: String?
    @State private var toastMessage: String?
    @State private var showCelebration = false

    private let requiredInvites = 3

    private var encouragingCopy: String {
        switch inviteService.inviteCount {
        case 0: return "Invite your first friend to get started"
        case 1: return "1 down, 2 to go!"
        case 2: return "Almost there!"
        default: return "You're in!"
        }
    }

    /// Formatted manual phone: (xxx) xxx-xxxx
    private var formattedManualPhone: String {
        let d = manualPhoneDigits
        switch d.count {
        case 0: return ""
        case 1...3: return "(\(d)"
        case 4...6:
            let area = d.prefix(3)
            let mid = d.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = d.prefix(3)
            let mid = d.dropFirst(3).prefix(3)
            let last = d.dropFirst(6).prefix(4)
            return "(\(area)) \(mid)-\(last)"
        }
    }

    private var manualPhoneValid: Bool { manualPhoneDigits.count == 10 }

    var body: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()

            // Header
            VStack(spacing: SonderSpacing.sm) {
                Text("Bring your crew")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)

                Text("Sonder is better with friends.\nInvite \(requiredInvites) people to get started.")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }

            // Progress circles
            HStack(spacing: SonderSpacing.md) {
                ForEach(0..<requiredInvites, id: \.self) { index in
                    Circle()
                        .fill(index < inviteService.inviteCount
                              ? SonderColors.terracotta
                              : SonderColors.warmGray)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if index < inviteService.inviteCount {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .animation(.spring(response: 0.4), value: inviteService.inviteCount)
                }
            }

            // Encouraging copy
            Text(encouragingCopy)
                .font(SonderTypography.subheadline)
                .foregroundStyle(SonderColors.terracotta)
                .animation(.easeInOut, value: inviteService.inviteCount)

            Spacer()

            // Invite methods
            VStack(spacing: SonderSpacing.md) {
                // From Contacts
                if SMSInviteView.canSendText {
                    Button {
                        showContactsPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.rectangle.stack")
                            Text("From Contacts")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WarmButtonStyle(isPrimary: true))

                    // Manual entry toggle
                    Button {
                        withAnimation { showManualEntry.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "phone")
                            Text("Enter a number")
                        }
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.terracotta)
                    }
                    .buttonStyle(.plain)
                }

                // Manual phone entry
                if showManualEntry || !SMSInviteView.canSendText {
                    manualEntrySection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, SonderSpacing.lg)

            // Toast
            if let toast = toastMessage {
                Text(toast)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.dustyRose)
                    .transition(.opacity)
            }

            Spacer()

            // Start exploring button
            Button(action: finishGate) {
                Text("Start Exploring")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle(isPrimary: true))
            .disabled(!inviteService.hasMetRequirement)
            .opacity(inviteService.hasMetRequirement ? 1 : 0.4)
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.bottom, SonderSpacing.xxl)
        }
        .background(SonderColors.cream)
        .sheet(isPresented: $showContactsPicker) {
            ContactInvitePickerView { phoneNumber in
                showContactsPicker = false
                // Send SMS to selected contact
                smsPhoneNumber = phoneNumber
            }
        }
        .sheet(item: $smsPhoneNumber) { phone in
            InviteSMSComposer(phoneNumber: phone) { result in
                smsPhoneNumber = nil
                if result == .sent {
                    recordInvite(phoneNumber: phone)
                }
            }
        }
        .task {
            if let userID = authService.currentUser?.id {
                await inviteService.loadInviteCount(for: userID)
            }
        }
        .overlay {
            if showCelebration {
                celebrationOverlay
            }
        }
    }

    // MARK: - Manual Entry

    private var manualEntrySection: some View {
        VStack(spacing: SonderSpacing.sm) {
            HStack(spacing: SonderSpacing.sm) {
                Text("+1")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkDark)
                    .padding(.leading, SonderSpacing.md)

                Divider().frame(height: 24)

                TextField("(555) 123-4567", text: Binding(
                    get: { formattedManualPhone },
                    set: { newValue in
                        let digits = newValue.filter(\.isNumber)
                        manualPhoneDigits = String(digits.prefix(10))
                    }
                ))
                .font(SonderTypography.body)
                .keyboardType(.phonePad)

                if manualPhoneValid {
                    Button {
                        let fullPhone = "+1\(manualPhoneDigits)"
                        if inviteService.isAlreadyInvited(phoneNumber: fullPhone) {
                            showToast("You already invited this person")
                        } else {
                            smsPhoneNumber = fullPhone
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SonderColors.terracotta)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, SonderSpacing.md)
            .padding(.trailing, SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
    }

    // MARK: - Celebration

    private var celebrationOverlay: some View {
        VStack {
            Spacer()
            VStack(spacing: SonderSpacing.md) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SonderColors.terracotta)

                Text("You're in!")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SonderColors.cream.opacity(0.95))
        .transition(.opacity)
    }

    // MARK: - Actions

    private func recordInvite(phoneNumber: String) {
        guard let userID = authService.currentUser?.id else { return }

        Task {
            do {
                let newCount = try await inviteService.recordInvite(
                    phoneNumber: phoneNumber,
                    userID: userID
                )
                SonderHaptics.impact(.medium)
                manualPhoneDigits = ""

                // Check if we hit the requirement
                if newCount >= requiredInvites {
                    SonderHaptics.notification(.success)
                    withAnimation(.spring(response: 0.5)) {
                        showCelebration = true
                    }
                    // Auto-advance after celebration
                    try? await Task.sleep(for: .seconds(1.5))
                    finishGate()
                }
            } catch let error as InviteError where error == .alreadyInvited {
                showToast("You already invited this person")
            } catch {
                logger.error("Failed to record invite: \(error.localizedDescription)")
                showToast("Something went wrong. Try again.")
            }
        }
    }

    private func finishGate() {
        guard inviteService.hasMetRequirement else { return }
        onComplete()
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - SMS Composer with Result

/// Wraps MFMessageComposeViewController and reports whether the SMS was actually sent.
private struct InviteSMSComposer: UIViewControllerRepresentable {
    let phoneNumber: String
    let onResult: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [phoneNumber]
        controller.body = "Hey! Come join me on Sonder — it's a fun way to remember your favorite places and discover where friends go. https://apps.apple.com/app/sonder"
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onResult: (MessageComposeResult) -> Void

        init(onResult: @escaping (MessageComposeResult) -> Void) {
            self.onResult = onResult
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) { [weak self] in
                self?.onResult(result)
            }
        }
    }
}

// MARK: - Contact Picker for Invite

/// Lets the user pick a contact with a phone number, then returns it.
private struct ContactInvitePickerView: View {
    let onSelect: (String) -> Void

    @Environment(ContactsService.self) private var contactsService
    @Environment(\.dismiss) private var dismiss

    @State private var contacts: [SimpleContact] = []
    @State private var isLoading = true
    @State private var searchText = ""

    struct SimpleContact: Identifiable {
        let id = UUID()
        let name: String
        let phoneNumber: String
    }

    private var filteredContacts: [SimpleContact] {
        if searchText.isEmpty { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if contactsService.authorizationStatus == .notDetermined {
                    // Need to request permission
                    VStack(spacing: SonderSpacing.lg) {
                        Spacer()
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(SonderColors.terracotta)

                        Text("Access your contacts to invite friends")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                            .multilineTextAlignment(.center)

                        Button {
                            Task { await contactsService.requestAccess() }
                        } label: {
                            Text("Allow Contacts Access")
                        }
                        .buttonStyle(WarmButtonStyle(isPrimary: true))
                        .padding(.horizontal, SonderSpacing.xxl)
                        Spacer()
                    }
                } else if isLoading {
                    ProgressView("Loading contacts...")
                        .tint(SonderColors.terracotta)
                } else if contacts.isEmpty {
                    VStack(spacing: SonderSpacing.md) {
                        Text("No contacts with phone numbers found")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                } else {
                    List(filteredContacts) { contact in
                        Button {
                            onSelect(contact.phoneNumber)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(SonderTypography.headline)
                                    .foregroundStyle(SonderColors.inkDark)
                                Text(contact.phoneNumber)
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search contacts")
                }
            }
            .navigationTitle("Choose a contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .task {
                if contactsService.authorizationStatus == .authorized {
                    await loadContacts()
                }
            }
            .onChange(of: contactsService.authorizationStatus) { _, newStatus in
                if newStatus == .authorized {
                    Task { await loadContacts() }
                }
            }
        }
    }

    @MainActor
    private func loadContacts() async {
        isLoading = true
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var loaded: [SimpleContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard !name.isEmpty else { return }
                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    loaded.append(SimpleContact(name: name, phoneNumber: phone))
                }
            }
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
        }

        contacts = loaded.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        isLoading = false
    }
}

// MARK: - String Identifiable for sheet binding

extension String: @retroactive Identifiable {
    public var id: String { self }
}
