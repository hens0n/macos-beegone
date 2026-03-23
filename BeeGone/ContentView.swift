import SwiftUI

enum AppTab: String, CaseIterable {
    case secureDelete = "Secure Delete"
    case freeSpace = "Wipe Free Space"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .secureDelete

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) {
                        selectedTab = tab
                    }
                    .buttonStyle(TabButtonStyle(isSelected: selectedTab == tab))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            switch selectedTab {
            case .secureDelete:
                SecureDeleteView()
            case .freeSpace:
                FreespaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)))
        .preferredColorScheme(.dark)
    }
}

struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isSelected ? Color(red: 0.96, green: 0.65, blue: 0.14) : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .cornerRadius(8)
    }
}
