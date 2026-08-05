import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    quickCaptureGuide
                    accountSection
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
    }

    private var header: some View {
        HStack {
            Text("Setup")
                .font(InkType.title(24))
                .posterCase(tracking: -0.8)
                .foregroundStyle(Ink.ink)
            Spacer()
            InkIconButton(systemName: "xmark", seed: 1001) { dismiss() }
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
                .font(InkType.bodySmall)
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
                        .font(InkType.heading(15))
                        .foregroundStyle(Ink.ink)
                    Text("iOS reserves the side button and every power+volume combination for screenshots, Emergency SOS and force restart. No app can claim them. Back Tap is the closest equivalent, and it's faster than you'd think.")
                        .font(InkType.bodySmall)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func triggerCard(number: String, title: String, detail: String, systemImage: String, seed: UInt64) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text(number)
                    .font(InkType.stamp(11))
                    .foregroundStyle(Ink.inkSoft)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Ink.ink)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(InkType.heading(16))
                    .foregroundStyle(Ink.ink)
                Text(detail)
                    .font(InkType.bodySmall)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule(title: "Account", seed: 1020)

            if !AppConfig.isBackendConfigured {
                InkCard(seed: 1021) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Running on this phone only")
                            .font(InkType.heading(16))
                            .foregroundStyle(Ink.ink)
                        Text("Tasks are saved locally and capture uses on-device parsing. Add your Supabase URL and anon key in AppConfig.swift to turn on sync, planning and chat.")
                            .font(InkType.bodySmall)
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
                        .font(InkType.bodySmall)
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
                        .font(InkType.stamp(11))
                        .stampCase()
                        .foregroundStyle(Ink.alarm)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isDeletingAccount)

                    Text(model.session?.isAnonymous == true
                         ? "Permanently deletes your account and every task. You're signed in as a guest, so there is no way to get any of it back."
                         : "Permanently deletes your account and every task on the server. This cannot be undone.")
                        .font(InkType.bodySmall)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
        }
    }

    private func statusRow(_ title: String, on: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(on ? Ink.ink : Ink.inkFaint)
                .frame(width: 16)
            Text(title)
                .font(InkType.body)
                .foregroundStyle(on ? Ink.ink : Ink.inkSoft)
            Spacer()
            Text(detail)
                .font(InkType.stamp(10))
                .stampCase()
                .foregroundStyle(Ink.inkSoft)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoughDivider(seed: 1040, opacity: 0.3)
            HStack(spacing: 10) {
                MascotView(mood: .watching, animated: false)
                    .frame(width: 34, height: 34)
                Text("On Track — say it, and it's on the list.")
                    .font(InkType.stamp(10))
                    .stampCase()
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .padding(.top, 6)
    }
}
