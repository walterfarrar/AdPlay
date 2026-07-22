import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isReady {
                HomeView()
            } else {
                VStack(spacing: 16) {
                    Text("AdPlay")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    if session.isLoading {
                        ProgressView()
                    }
                    if let err = session.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry") {
                            Task { await session.start() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AtmosphereBackground())
            }
        }
        .task {
            await session.start()
        }
    }
}
