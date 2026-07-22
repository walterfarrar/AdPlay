import SwiftUI

struct RedeemView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var invoice = ""
    @State private var history: [Withdrawal] = []
    @State private var didSubmit = false

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
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.92),
                        Color(red: 0.93, green: 0.95, blue: 0.97),
                        Color(red: 0.90, green: 0.93, blue: 0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Redeem")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadHistory() }
        }
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
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.85, green: 0.82, blue: 0.78), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request")
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))
            TextField("Amount (sats)", text: $amountText)
                .keyboardType(.numberPad)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            TextField("BOLT11 invoice", text: $invoice, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color("BrandInk"))
                    .background(Color("BrandAccent"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.85, green: 0.82, blue: 0.78), lineWidth: 1)
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
                        if let created = w.created_at {
                            Text(created)
                                .font(.caption)
                                .foregroundStyle(Color("BrandMuted"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.85, green: 0.82, blue: 0.78), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func loadHistory() async {
        history = (try? await session.api.myWithdrawals()) ?? []
    }
}
