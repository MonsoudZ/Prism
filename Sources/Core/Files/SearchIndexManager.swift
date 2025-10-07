//
//  OnboardingView.swift
//  Prism
//
//  A lightweight, keyboard-friendly onboarding flow for macOS.
//  - Shows once (persisted via @AppStorage)
//  - Works great with VoiceOver and keyboard
//  - No 3rd-party deps
//
//  Created by Monsoud Zanaty on 10/4/25.
//  Updated by ChatGPT-5 Thinking.
//

import SwiftUI

/// Top-level onboarding view shown modally at first launch (or when triggered from Help/About).
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    // Persisted flag so we don't show onboarding again unless reset.
    @AppStorage("prism.didSeeOnboarding") private var didSeeOnboarding = false

    // Current page index.
    @State private var currentStep = 0

    // Static steps for now; can be localized/replaced via factory methods below.
    private let steps: [OnboardingStep] = OnboardingStepFactory.createDefaultSteps()

    var body: some View {
        ZStack {
            // Background uses system window color to match macOS chrome
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                header

                Spacer(minLength: 0)

                content

                Spacer(minLength: 0)

                indicators

                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(minWidth: 640, minHeight: 520) // Good baseline for 16" MBP
        .accessibilityElement(children: .contain)
        .toolbar {
            // Optional Skip in titlebar area (macOS-y)
            ToolbarItem(placement: .automatic) {
                Button("Skip") { completeAndDismiss() }
                    .keyboardShortcut(.escape, modifiers: []) // Esc to skip
                    .accessibilityLabel("Skip onboarding")
            }
        }
        // Keyboard handling: arrows to navigate; Return to next/finish.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // No-op: keeps view responsive when first presented
        }
        .onAppear {
            // IMPORTANT: Do NOT mark didSeeOnboarding here.
            // We only set it when the user completes or skips.
            if steps.isEmpty { currentStep = 0 }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Prism")
                    .font(.largeTitle).fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text("Fast reading • Reliable notes • Comfortable on large PDFs")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Secondary "Skip" button for mouse users; toolbar also has Skip and Esc shortcut.
            Button("Skip") { completeAndDismiss() }
                .buttonStyle(.bordered)
                .accessibilityHint("Skip onboarding and start using Prism")
        }
    }

    private var content: some View {
        // Defensive: guard against empty steps
        let step = steps.indices.contains(currentStep) ? steps[currentStep] : OnboardingStep.placeholder()

        return VStack(spacing: 24) {
            // Icon
            Image(systemName: step.icon)
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(.blue)
                .symbolEffect(.bounce, value: currentStep) // macOS 14+; harmless no-op earlier
                .accessibilityLabel(step.accessibilityLabel)
                .accessibilityHint(step.accessibilityHint)

            // Copy
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(step.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(step.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.25), value: currentStep)
        }
        .frame(maxWidth: .infinity)
    }

    private var indicators: some View {
        HStack(spacing: 10) {
            ForEach(steps.indices, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { currentStep = index }
                } label: {
                    Circle()
                        .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
                        .accessibilityHint(index == currentStep ? "Current step" : "Go to this step")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack {
            // Back
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.25)) { currentStep = max(0, currentStep - 1) }
            }
            .disabled(currentStep == 0)
            .buttonStyle(.bordered)
            .keyboardShortcut(.leftArrow, modifiers: []) // ←
            .accessibilityLabel("Go to previous step")

            Spacer()

            // Next / Get Started
            if currentStep < steps.count - 1 {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.25)) { currentStep = min(steps.count - 1, currentStep + 1) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.rightArrow, modifiers: []) // →
                .keyboardShortcut(.return, modifiers: [])      // ⏎
                .accessibilityLabel("Go to next step")
            } else {
                Button("Get Started") { completeAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Finish onboarding and start using Prism")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func completeAndDismiss() {
        didSeeOnboarding = true
        dismiss()
    }
}

// MARK: - Model

/// One onboarding page/step.
struct OnboardingStep {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let accessibilityLabel: String
    let accessibilityHint: String

    init(
        title: String,
        subtitle: String,
        description: String,
        icon: String,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel ?? "Onboarding step icon"
        self.accessibilityHint = accessibilityHint ?? "Visual indicator for the current onboarding step"
    }

    static func placeholder() -> OnboardingStep {
        OnboardingStep(
            title: "Welcome",
            subtitle: "Let’s get started",
            description: "If you see this placeholder, steps failed to load. Continue to start using Prism.",
            icon: "sparkles"
        )
    }
}

// MARK: - Factory

enum OnboardingStepFactory {
    /// Default English copy; swap with localized versions when ready.
    static func createDefaultSteps() -> [OnboardingStep] {
        [
            OnboardingStep(
                title: "Welcome to Prism",
                subtitle: "A focused PDF experience for builders",
                description: "Prism makes large PDFs feel light: smooth navigation, dependable notes, and a clean macOS UI.",
                icon: "doc.text.fill",
                accessibilityLabel: "Document icon",
                accessibilityHint: "Represents document reading"
            ),
            OnboardingStep(
                title: "Smart Notes",
                subtitle: "Highlights → Notes in one move",
                description: "Select text, press ⌘⇧H, and Prism captures a note with page context. Add page notes in Markdown anytime.",
                icon: "highlighter",
                accessibilityLabel: "Highlighter icon",
                accessibilityHint: "Represents note-taking"
            ),
            OnboardingStep(
                title: "Code & Web Side-by-Side",
                subtitle: "Stay in flow",
                description: "Open a code pane or web pane next to your PDF. Keep docs, code snippets, and references together.",
                icon: "terminal.fill",
                accessibilityLabel: "Terminal icon",
                accessibilityHint: "Represents code tools"
            ),
            OnboardingStep(
                title: "Bring Your Library",
                subtitle: "Import or drag & drop",
                description: "Use “Import PDFs…” or drop files into the Library pane. Prism remembers pages and notes per document.",
                icon: "plus.circle.fill",
                accessibilityLabel: "Plus circle icon",
                accessibilityHint: "Represents importing"
            )
        ]
    }

    /// Placeholders for future localization hooks.
    static func createLocalizedSteps(for locale: Locale) -> [OnboardingStep] {
        // TODO: Inject localized strings here.
        createDefaultSteps()
    }

    static func createCustomSteps(_ custom: [OnboardingStep]) -> [OnboardingStep] {
        custom
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .frame(width: 740, height: 560)
    }
}
#endif
