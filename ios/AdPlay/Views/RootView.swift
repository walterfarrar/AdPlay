import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isReady {
                HomeView()
            } else {
                VStack(spacing: 18) {
                    Text("AdPlay")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color("BrandInk"))
                        .shadow(color: Color("BrandAccent").opacity(0.4), radius: 24, y: 6)
                    if session.isLoading {
                        ProgressView()
                            .tint(Color("BrandAccent"))
                    }
                    if let err = session.errorMessage {
                        Text(err)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color("BrandMuted"))
                            .multilineTextAlignment(.center)
                            .padding()
                        Button {
                            Task { await session.start() }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color("BrandAccent"))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .overlay(
                                    Capsule().stroke(Color("BrandAccent").opacity(0.6), lineWidth: 1)
                                )
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
