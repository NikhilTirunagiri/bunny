import AppKit
import SwiftUI

/// The four-page first-run flow (spec §5). Shown by `WindowManager` when
/// `UserDefaults` key `onboarding.completed` is false; reopenable from Settings → General.
struct OnboardingView: View {
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 24) {
            Group {
                switch page {
                case 0: WelcomePage()
                case 1: TaskContextPage()
                case 2: AgentsPage()
                default: FinishPage()
                }
            }
            .transition(.push(from: .trailing))
            .animation(.default, value: page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .padding(32)
        .frame(width: 640, height: 520)
    }

    private var bottomBar: some View {
        HStack {
            pageIndicator

            Spacer()

            Button("Back") { page -= 1 }
                .buttonStyle(.glass)
                .disabled(page == 0)

            Button(page == pageCount - 1 ? "Start using Bunny" : "Continue") {
                if page == pageCount - 1 {
                    finish()
                } else {
                    page += 1
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        WindowManager.shared.closeOnboarding()
        (NSApp.delegate as? AppDelegate)?.statusBarController.openPopover()
    }
}
