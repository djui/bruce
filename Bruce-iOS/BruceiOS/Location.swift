import SwiftUI

/// Glass "Use my location" prompt (LocationProvider lives in Shared/BruceCore).
struct UseLocationButton: View {
    @EnvironmentObject var loc: LocationProvider
    var text = "Use my location"
    var body: some View {
        if !loc.authorized {
            Button { loc.request() } label: {
                Label(loc.denied ? "Allow location in Settings" : text, systemImage: "location.fill")
                    .bruceFont(14, weight: .semibold)
            }
            .buttonStyle(.glass)
        }
    }
}
