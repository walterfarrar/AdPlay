import SwiftUI

struct RedeemView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var invoice = ""
    @State private var history: [Withdrawal] = []
    @State private var didSubmit = false

    private let pageBg = Color(red: 0.055, green: 0.059, blue: 0.102) // #0E0F1A
    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149) // #171826
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239) // #2B2D3D
    private let fieldBg = Color(red: 0.043, green: 0.047, blue: 0.078) // #0B0C14
    private let fieldBorder = Color(red: 0.196, green: 0.204, blue: 0.278) // #323548
    private let onAccent = Color(red: 0.043, green: 0.047, blue: 0.078) // dark text on orange

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balancePanel
                    requestPanel
                    historyPanel
                }
                .padding(20)
            }
            .background(AtmosphereBackground())
            .navigationTitle("Redeem")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(pageBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Color("BrandInk"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color("BrandInk"))
                }
            }
            .task { await loadHistory() }
        }
        .preferredColorScheme(.dark)
    }

    private var balancePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(session.state.satsBalance) sats")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color("BrandInk"))
            Text("Available balance")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
            Text("Minimum withdrawal: \(session.state.minWithdrawSats) sats")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("BrandInk"))
            Text("Paste a Lightning invoice. An admin pays it manually from a Lightning wallet.")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request")
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))

            labeledField(title: "Amount (sats)") {
                TextField("e.g. 1000", text: $amountText)
                    .keyboardType(.numberPad)
                    .foregroundStyle(Color("BrandInk"))
                    .tint(Color("BrandAccent"))
            }

            labeledField(title: "BOLT11 invoice") {
                TextField("lnbc…", text: $invoice, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Color("BrandInk"))
                    .tint(Color("BrandAccent"))
            }

            Button {
                Task {
                    guard let amount = Int(amountText) else {
                        session.errorMessage = "Enter a valid amount"
                        return
                    }
                    didSubmit = await session.withdraw(amountSats: amount, bolt11: invoice)
                    if didSubmit {
                        await loadHistory()
                        amountText = ""
                        invoice = ""
                    }
                }
            } label: {
                Text("Submit withdrawal")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(onAccent)
                    .background(
                        LinearGradient(
                            colors: [Color("BrandAccent"), Color("BrandAccentHot")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color("BrandAccent").opacity(0.35), radius: 14, y: 5)
            }
            .disabled(amountText.isEmpty || invoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let err = session.errorMessage {
                Text(err).foregroundStyle(.red).font(.footnote)
            }
            if didSubmit {
                Text("Request queued. Status updates after the Lightning payment is marked paid.")
                    .font(.footnote)
                    .foregroundStyle(Color("BrandMuted"))
            }
        }
        .padding(16)
        .background(panelBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))
            if history.isEmpty {
                Text("No withdrawals yet")
                    .foregroundStyle(Color("BrandMuted"))
            } else {
                ForEach(history) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(w.sats) sats · \(w.status)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color("BrandInk"))
                        if let created = w.createdAt ?? w.created_at {
                            Text(created)
                                .font(.caption)
                                .foregroundStyle(Color("BrandMuted"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(fieldBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(fieldBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(panelBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func labeledField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("BrandMuted"))
            content()
                .padding(12)
                .background(fieldBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(fieldBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadHistory() async {
        history = (try? await session.api.myWithdrawals()) ?? []
    }
}
