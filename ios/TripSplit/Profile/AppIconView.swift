import SwiftUI
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case d1 = "D1", d2 = "D2", d3 = "D3", d4 = "D4"

    var id: Self { self }
    var alternateName: String? { self == .d1 ? nil : "AppIcon\(rawValue)" }
    var previewName: String { "IconPreview\(rawValue)" }
    var title: String {
        switch self {
        case .d1: "Blue road (default)"
        case .d2: "Purple plane"
        case .d3: "Round teal plane"
        case .d4: "Three stamps"
        }
    }
}

struct AppIconView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentName = UIApplication.shared.alternateIconName
    @State private var changing = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(AppIconChoice.allCases) { icon in
                    Button {
                        guard !changing, currentName != icon.alternateName else { return }
                        changing = true
                        Task {
                            do {
                                try await UIApplication.shared.setAlternateIconName(icon.alternateName)
                                currentName = UIApplication.shared.alternateIconName
                            } catch { self.error = error.localizedDescription }
                            changing = false
                        }
                    } label: {
                        HStack(spacing: Spacing.lg) {
                            Image(icon.previewName).resizable().scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(.rect(cornerRadius: Radius.lg))
                                .accessibilityHidden(true)
                            Text(icon.title).foregroundStyle(.primary)
                            Spacer()
                            if currentName == icon.alternateName {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(currentName == icon.alternateName ? .isSelected : [])
                }
            } footer: {
                Text(UIApplication.shared.supportsAlternateIcons
                     ? "Choose the icon shown on this iPhone."
                     : "Changing the app icon isn’t available on this device.")
            }
        }
        .disabled(changing || !UIApplication.shared.supportsAlternateIcons)
        .navigationTitle("App icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { currentName = UIApplication.shared.alternateIconName }
        .onChange(of: scenePhase) { if scenePhase == .active { currentName = UIApplication.shared.alternateIconName } }
        .alert("Couldn’t change the app icon", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}
