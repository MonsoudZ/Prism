import SwiftUI

/// Root composition for the app: wires major panes together and listens to global commands.
struct CompositionRoot: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    @State private var showingHelp = false
    @State private var showingSettings = false
    @State private var showingOnboarding = false

    var body: some View {
        // Use a unique local shell view to avoid name collisions with your DesignSystem
        RootShellView()
            // Help
            .sheet(isPresented: $showingHelp, content: {
                // This references the single canonical HelpView in Features/Help/Views/HelpView.swift
                HelpView()
            })
            // Settings
            .sheet(isPresented: $showingSettings, content: {
                SettingsSheetView()
            })
            // Onboarding (local placeholder so we don't depend on a missing type)
            .sheet(isPresented: $showingOnboarding, content: {
                OnboardingSheetView()
            })
            // Notifications → sheet toggles
            .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
                showingHelp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
                showingSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                showingOnboarding = true
            }
    }
}

/// Keep this simple and uniquely named to avoid conflicts with `DesignSystem/Layouts/ContentContainer`.
private struct RootShellView: View {
    var body: some View {
        // Replace with your real 3-pane layout once wired:
        Text("Prism")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Local, uniquely named settings sheet to avoid clashes with any future Settings view.
private struct SettingsSheetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title2).bold()
            Text("Add your preferences UI here.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }
}

/// Local, uniquely named onboarding sheet so the file compiles even if `OnboardingView` isn't in target.
private struct OnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Prism").font(.title2).bold()
            Text("Onboarding content goes here.")
                .foregroundStyle(.secondary)
            Button("Get Started") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }
}
