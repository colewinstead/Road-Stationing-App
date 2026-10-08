import SwiftUI

struct HelpAboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    var body: some View {
        List {
            Section {
                Text("Roadway station and offset on your iPhone.").font(.headline)
                Text(version).foregroundStyle(.secondary).accessibilityIdentifier("app-version")
            }
            Section("Get started") {
                Text("1. Import a .xml or .landxml file from Files. RoadStation keeps a local copy for return visits.")
                Text("2. Confirm the coordinate system and project units. Use the EPSG supplied by your project; nearby recommendations do not establish the correct CRS.")
                Text("3. Choose an alignment, then open Field Position. Allow location while using the app to read station, LT/RT offset, accuracy and fix status.")
                Text("For manual coordinates, open Inspect Alignment → Entry. X is Easting; Y is Northing. LT is positive and RT is negative relative to increasing alignment direction.")
                Link("Sample project & worked example", destination: URL(string: "https://vericivil.com/roadstation/support")!)
                    .accessibilityIdentifier("help-sample")
            }
            Section("Positioning limits") {
                Text("Phone GPS is approximate. RoadStation does not provide survey-grade positioning. Check accuracy, CRS, units and stale/last-known warnings before using a result.")
                Text("Calculations are horizontal (2D). Satellite imagery and the drawn line are context, not control measurements. Use Engineering View when map imagery is unavailable.")
                Text("Location stops when Field Position closes or the app becomes inactive. Never use the phone in a way that puts you or others at risk near traffic.")
            }
            Section("Privacy & support") {
                Link("Privacy policy", destination: URL(string: "https://vericivil.com/roadstation/privacy")!)
                    .accessibilityIdentifier("help-privacy")
                Link("Support & troubleshooting", destination: URL(string: "https://vericivil.com/roadstation/support")!)
                    .accessibilityIdentifier("help-support")
                Link("Email support", destination: URL(string: "mailto:support@vericivil.com?subject=RoadStation%20support")!)
                    .accessibilityIdentifier("help-email")
                Text("support@vericivil.com").textSelection(.enabled)
                Text("Projects stay in this app's storage. Live fixes and query histories are not saved. Deleting a project removes its app-owned files; original files and device backups are managed separately.")
            }
            Section {
                DisclosureGroup("Third-party acknowledgments") {
                    Text(acknowledgments).font(.footnote).textSelection(.enabled)
                }.accessibilityIdentifier("help-acknowledgments")
                Link("RoadStation on VeriCivil", destination: URL(string: "https://vericivil.com/roadstation")!)
            }
        }.navigationTitle("Help & About").navigationBarTitleDisplayMode(.inline)
    }

    private var acknowledgments: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgments", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Acknowledgments could not be loaded. Contact support@vericivil.com."
        }
        return text
    }
}
