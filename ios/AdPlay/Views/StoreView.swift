import SwiftUI

struct StoreView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var store = AdSlotStore()

    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    holdSummary
                    extraSlots
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(AtmosphereBackground())
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(red: 0.055, green: 0.059, blue: 0.102), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await store.load()
                await creditTransactions(await store.unfinishedTransactionIds(), restoring: false)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var progress: PlayerProgress { session.progress }

    private var holdSummary: some View {
        panel(title: "Your hold") {
            Text("\(session.state.adsRemainingToday) / \(progress.adBank.max)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color("BrandInk"))
                .monospacedDigit()
            Text("Boost ads you can hold right now. Extra slots raise the max permanently.")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
        }
    }

    private var extraSlots: some View {
        let maxed = progress.iapAdsPurchased >= progress.iapBonusAdsMax
        return panel(title: "Extra ad slots") {
            Text("Buy +1 permanent hold, one at a time. \(progress.iapAdsPurchased) / \(progress.iapBonusAdsMax) purchased.")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
            if let err = store.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let status = store.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(Color("BrandFill"))
            }
            Button {
                Task { await buySlot() }
            } label: {
                Text(maxed ? "All extra slots owned" : "Buy +1 ad slot")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color("BrandAccent"), Color("BrandAccentHot")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .opacity(maxed || store.isBusy ? 0.45 : 1)
            }
            .disabled(maxed || store.isBusy || session.isLoading)
            Button {
                Task { await restorePurchases() }
            } label: {
                Text("Restore purchases")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("BrandAccent"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(store.isBusy || session.isLoading)
            Text("Uses this Apple ID. Extra slots you already bought are credited again on this device.")
                .font(.caption)
                .foregroundStyle(Color("BrandMuted"))
        }
    }

    private func buySlot() async {
        guard let tx = await store.purchase() else { return }
        await creditTransactions([tx], restoring: false)
    }

    private func restorePurchases() async {
        let ids = await store.restoreTransactionIds()
        await creditTransactions(ids, restoring: true)
    }

    private func creditTransactions(_ ids: [String], restoring: Bool) async {
        guard !ids.isEmpty else {
            if restoring {
                store.statusMessage = "No extra-slot purchases found for this Apple ID."
            }
            return
        }
        do {
            let added = try await session.restoreAdSlots(transactionIds: ids)
            if restoring {
                store.statusMessage = added > 0
                    ? "Restored \(added) extra slot\(added == 1 ? "" : "s")."
                    : "Purchases already on this account."
            }
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(panelBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
