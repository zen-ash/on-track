import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDelete = false
    @State private var isShowingTrash = false

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    quickCaptureGuide
                    accountSection
                    calendarSection
                    dataSection
                    statusSection
                    about
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .alert("Delete your account?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) {
                Task { await model.deleteAccount() }
            }
        } message: {
            Text("Your account and every task will be permanently deleted from the server. This can't be undone.")
        }
        .sheet(isPresented: $isShowingTrash) {
            TrashView().presentationBackground(Ink.paper)
        }
    }

    private var header: some View {
        HStack {
            Text("Setup")
                .inkTitle(24)
                .posterCase(tracking: -0.8)
                .foregroundStyle(Ink.ink)
            Spacer()
            InkIconButton(systemName: "xmark", seed: 1001, accessibilityLabel: "Close") { dismiss() }
        }
    }

    // MARK: - Quick capture

    /// The four triggers, spelled out. iPhone will not let an app bind the power
    /// button or power+volume combos — those are reserved by the system — so
    /// these are the real ways to get to voice capture in one gesture.
    private var quickCaptureGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionRule(title: "One-gesture capture", seed: 1010)

            Text("Set these up once. All four open the same voice capture.")
                .inkBodySmall()
                .foregroundStyle(Ink.inkSoft)

            triggerCard(
                number: "01",
                title: "Triple-tap the back",
                detail: "Settings → Accessibility → Touch → Back Tap → Triple Tap → pick the On Track shortcut. Works on iPhone 8 and newer.",
                systemImage: "hand.tap.fill",
                seed: 1011
            )

            triggerCard(
                number: "02",
                title: "Action Button",
                detail: "Settings → Action Button → swipe to Shortcut → choose Capture with On Track. iPhone 15 Pro and newer.",
                systemImage: "button.horizontal.top.press.fill",
                seed: 1012
            )

            triggerCard(
                number: "03",
                title: "Control Centre & Lock Screen",
                detail: "Swipe down → + → Add a control → On Track. Add the Lock Screen widget from the wallpaper editor too.",
                systemImage: "switch.2",
                seed: 1013
            )

            triggerCard(
                number: "04",
                title: "Just ask Siri",
                detail: "“Hey Siri, capture with On Track”, or “Hey Siri, add a task to On Track”. No buttons at all.",
                systemImage: "mic.fill",
                seed: 1014
            )

            InkCard(seed: 1015) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why not the power button?")
                        .inkHeading(15)
                        .foregroundStyle(Ink.ink)
                    Text("iOS reserves the side button and every power+volume combination for screenshots, Emergency SOS and force restart. No app can claim them. Back Tap is the closest equivalent, and it's faster than you'd think.")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func triggerCard(number: String, title: String, detail: String, systemImage: String, seed: UInt64) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(number)
                    .inkStamp(11)
                    .foregroundStyle(Ink.inkSoft)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Ink.ink)
            }
            .frame(width: 30)
            // The number and icon are visual sequencing/decoration; title and
            // detail already say everything they'd add.
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .inkHeading(16)
                    .foregroundStyle(Ink.ink)
                Text(detail)
                    .inkBodySmall()
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule(title: "Account", seed: 1020)

            if !AppConfig.isBackendConfigured {
                InkCard(seed: 1021) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Running on this phone only")
                            .inkHeading(16)
                            .foregroundStyle(Ink.ink)
                        Text("Tasks are saved locally and capture uses on-device parsing. Add your Supabase URL and anon key in AppConfig.swift to turn on sync, planning and chat.")
                            .inkBodySmall()
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if model.session == nil {
                VStack(alignment: .leading, spacing: 10) {
                    AppleSignInButton()

                    Button("Continue without an account") {
                        Task { await model.continueWithoutAccount() }
                    }
                    .buttonStyle(InkOutlineButtonStyle(seed: 1022))

                    Text("Signing in syncs your list and unlocks planning and chat. Anything you've already captured comes with you.")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        StampLabel(text: model.session?.isAnonymous == true ? "guest" : "signed in", filled: true, seed: 1023)
                        Spacer()
                    }
                    Button("Sign out") {
                        Task { await model.signOut() }
                    }
                    .buttonStyle(InkOutlineButtonStyle(seed: 1024))

                    RoughDivider(seed: 1025, opacity: 0.25).padding(.vertical, 4)

                    Button {
                        isConfirmingDelete = true
                    } label: {
                        HStack(spacing: 8) {
                            if model.isDeletingAccount {
                                ProgressView().tint(Ink.alarm).scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.fill").font(.system(size: 12, weight: .black))
                            }
                            Text(model.isDeletingAccount ? "Deleting…" : "Delete account and all data")
                        }
                        .inkStamp(11)
                        .stampCase()
                        .foregroundStyle(Ink.alarm)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isDeletingAccount)
                    .accessibilityLabel(model.isDeletingAccount ? "Deleting account" : "Delete account and all data")

                    Text(model.session?.isAnonymous == true
                         ? "Permanently deletes your account and every task. You're signed in as a guest, so there is no way to get any of it back."
                         : "Permanently deletes your account and every task on the server. This cannot be undone.")
                        .inkBodySmall()
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule(title: "Calendar", seed: 1050)

            Toggle(isOn: Binding(
                get: { model.calendarAwarenessEnabled },
                set: { newValue in Task { await model.setCalendarAwareness(enabled: newValue) } }
            )) {
                Text("Plan around my calendar").inkBody().foregroundStyle(Ink.ink)
            }
            .tint(Ink.ink)

            Text("Read-only. On Track only reads what's already on your calendar so the daily plan can avoid stacking a task on top of a meeting — it never creates, edits, or deletes anything there. Only start and end times are used, never titles.")
                .inkBodySmall()
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if model.calendarAwarenessEnabled && model.calendarAccessState == .denied {
                InkCard(seed: 1051) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Access was declined")
                            .inkHeading(15)
                            .foregroundStyle(Ink.alarm)
                        Text("Turn it on from Settings → On Track → Calendars to actually use this.")
                            .inkBodySmall()
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule(title: "Data", seed: 1035)

            Button {
                isShowingTrash = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text("Trash")
                        .inkBody()
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    Text("30 days")
                        .inkStamp(10)
                        .stampCase()
                        .foregroundStyle(Ink.inkSoft)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Ink.inkFaint)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trash")
            .accessibilityHint("Deleted tasks are kept for 30 days before they're gone for good.")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRule(title: "What's on", seed: 1030)

            statusRow("Tasks", on: true, detail: model.isLocalMode ? "on device" : "synced")
            statusRow("Voice capture", on: true, detail: "on device")
            statusRow("Smart parsing", on: model.isFullyCapable, detail: model.isFullyCapable ? "model" : "on-device rules")
            statusRow("Daily planning", on: model.isFullyCapable, detail: model.isFullyCapable ? "model" : "heuristic")
            statusRow("Chat", on: model.isFullyCapable, detail: model.isFullyCapable ? "ready" : "needs backend")
            statusRow("Calendar", on: model.calendarAwarenessEnabled && model.calendarAccessState == .authorized, detail: calendarStatusDetail)
        }
    }

    private var calendarStatusDetail: String {
        guard model.calendarAwarenessEnabled else { return "off" }
        switch model.calendarAccessState {
        case .authorized: return "reading"
        case .denied: return "blocked"
        case .notDetermined: return "pending"
        }
    }

    private func statusRow(_ title: String, on: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            // Redundant with `detail` (which already spells out on/off/etc.)
            // for anything but sighted glancing.
            Image(systemName: on ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(on ? Ink.ink : Ink.inkFaint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title)
                .inkBody()
                .foregroundStyle(on ? Ink.ink : Ink.inkSoft)
            Spacer()
            Text(detail)
                .inkStamp(10)
                .stampCase()
                .foregroundStyle(Ink.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoughDivider(seed: 1040, opacity: 0.3)
            HStack(spacing: 10) {
                // Static branding, not a mood report — nothing for VoiceOver
                // to add beyond the tagline text right next to it.
                MascotView(mood: .watching, animated: false)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                Text("On Track — say it, and it's on the list.")
                    .inkStamp(10)
                    .stampCase()
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .padding(.top, 6)
    }
}
