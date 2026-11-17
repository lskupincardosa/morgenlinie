import SwiftUI
import UIKit

/// The app icons bundled with the app. `nil` asset name means the primary icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case boardM = "AppIcon"
    case routeLine = "AppIcon-RouteLine"
    case stopBadge = "AppIcon-StopBadge"
    case sunrise = "AppIcon-Sunrise"
    case boardLight = "AppIcon-BoardLight"
    case routeGermany = "AppIcon-RouteGermany"
    case badgeRail = "AppIcon-BadgeRail"

    var id: String { rawValue }
    /// The name UIKit expects: nil for the primary icon.
    var alternateName: String? { self == .boardM ? nil : rawValue }
    var preview: String { "IconPreview/\(rawValue)" }

    var label: String {
        switch self {
        case .boardM: "Board"
        case .routeLine: "Route"
        case .stopBadge: "Stop 1"
        case .sunrise: "Sunrise"
        case .boardLight: "Light board"
        case .routeGermany: "Red route"
        case .badgeRail: "Stop 4"
        }
    }

    @MainActor static var current: AppIconChoice {
        UIApplication.shared.alternateIconName.flatMap(AppIconChoice.init(rawValue:)) ?? .boardM
    }
}

struct AppIconPicker: View {
    @State private var selected = AppIconChoice.current
    @State private var error: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 16)], spacing: 16) {
            ForEach(AppIconChoice.allCases) { choice in
                Button { select(choice) } label: {
                    VStack(spacing: 6) {
                        Image(choice.preview)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(choice == selected ? Color.accentColor : .clear, lineWidth: 3)
                                    .padding(-4)
                            }
                        Text(choice.label)
                            .font(.caption)
                            .foregroundStyle(choice == selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(choice == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        if let error {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                selected = choice
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
