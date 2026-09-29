import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(AppIdentity.name)
                    .font(.largeTitle.weight(.semibold))
                Text("Local image conversion")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("File import is coming in the next phase.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    ContentView()
}
