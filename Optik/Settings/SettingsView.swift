import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Genel", systemImage: "gearshape")
                }
        }
        .frame(width: 440)
    }
}

private struct GeneralSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            LabeledContent("Sürüm", value: version)
            Text("Diğer ayarlar sonraki aşamalarda gelecek.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
}
