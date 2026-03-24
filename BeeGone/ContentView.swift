import SwiftUI

enum AppTab: String, CaseIterable {
    case secureDelete = "Secure Delete"
    case freeSpace = "Wipe Free Space"
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .secureDelete

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
