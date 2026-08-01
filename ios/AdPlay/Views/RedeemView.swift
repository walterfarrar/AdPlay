import SwiftUI

struct RedeemView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var invoice = ""
    @State private var history: [Withdrawal] = []
    @State private var didSubmit = false
    @State private var localError: String?
    @State private var showHowTo = false

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
                    requestForm
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showHowTo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("How to redeem")
                    .foregroundStyle(Color("BrandInk"))
                }
            }
            .sheet(isPresented: $showHowTo) {
                RedeemHowToView()
            }
            .task { await loadHistory() }
        }
        .preferredColorScheme(.dark)
    }

    private var balancePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatSatsAsBtc(session.state.satsBalance))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color("BrandInk"))
                .monospacedDigit()
            Text("BTC available to redeem")
                .font(.footnote)
                .foregroundStyle(Color("BrandMuted"))
            Text(
                "This balance only increases when a progress bar fills completely. " +
                    "Watching ads speeds up earning on the home screen — partial fills don’t count here yet."
            )
            .font(.footnote)
            .foregroundStyle(Color("BrandMuted"))
            Text("Minimum withdrawal: \(formatSatsAsBtc(session.state.minWithdrawSats)) BTC")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color("BrandInk"))
                .monospacedDigit()
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

    private var requestForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request")
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))

            labeledField(title: "Amount (BTC)") {
                TextField("e.g. 0.00001000", text: $amountText)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Color("BrandInk"))
                    .tint(Color("BrandAccent"))
                    .monospacedDigit()
                    .onChange(of: amountText) { _, newValue in
                        let filtered = filterBtcInput(newValue)
                        if filtered != newValue { amountText = filtered }
                    }
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
                    localError = nil
                    session.errorMessage = nil
                    guard let amount = parseBtcToSats(amountText) else {
                        localError = "Enter a valid BTC amount"
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

            if let err = localError ?? session.errorMessage {
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
                        Text("\(formatSatsAsBtc(w.sats)) BTC · \(w.status)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color("BrandInk"))
                            .monospacedDigit()
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

/// Player-facing guide for Lightning redeem (shared copy with Android / web).
struct RedeemHowToView: View {
    @Environment(\.dismiss) private var dismiss

    private let pageBg = Color(red: 0.055, green: 0.059, blue: 0.102)
    private let panelBg = Color(red: 0.090, green: 0.094, blue: 0.149)
    private let panelBorder = Color(red: 0.169, green: 0.176, blue: 0.239)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    howToSection(
                        title: "What you need",
                        body: "AdPlay pays Bitcoin over the Lightning Network. " +
                            "You’ll need a Lightning wallet that can create a receive invoice " +
                            "(a BOLT11 string starting with lnbc)."
                    )
                    howToSection(
                        title: "Steps",
                        body: "1. Earn sats by filling the progress bar completely on the home screen.\n" +
                            "2. Open a Lightning wallet and create a receive invoice for the exact amount you want.\n" +
                            "3. Copy the BOLT11 invoice from your wallet.\n" +
                            "4. In AdPlay Redeem, enter that amount, paste the invoice, and submit.\n" +
                            "5. We pay invoices manually. Watch History for pending → paid " +
                            "(or rejected / refunded)."
                    )
                    howToSection(
                        title: "Apps you can use",
                        body: "Any Lightning wallet that creates BOLT11 invoices works. Popular options:\n" +
                            "• Wallet of Satoshi — simple, good for beginners\n" +
                            "• Phoenix — self-custodial Lightning wallet\n" +
                            "• Zeus — full-featured Lightning wallet\n" +
                            "• Alby — browser and mobile Lightning wallet\n" +
                            "• Muun — Bitcoin + Lightning\n" +
                            "• Strike — Bitcoin payments with Lightning\n" +
                            "• Cash App — Lightning receive where available"
                    )
                    howToSection(
                        title: "Tips",
                        body: "Match the invoice amount to what you enter here. " +
                            "Invoices expire, so create a fresh one when you’re ready to submit. " +
                            "Only one pending withdrawal is allowed at a time."
                    )
                }
                .padding(20)
            }
            .background(AtmosphereBackground())
            .navigationTitle("How to redeem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(Color("BrandInk"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                        .foregroundStyle(Color("BrandInk"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func howToSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color("BrandInk"))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Color("BrandMuted"))
                .fixedSize(horizontal: false, vertical: true)
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
}

/// Whole-sat balances as BTC (8 dp — 1 sat = 0.00000001).
func formatSatsAsBtc(_ sats: Int) -> String {
    String(format: "%.8f", Double(sats) * 1e-8)
}

/// Parse a BTC string into whole sats (nearest sat).
func parseBtcToSats(_ text: String) -> Int? {
    guard let btc = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), btc > 0 else {
        return nil
    }
    let sats = (btc * 1e8).rounded()
    guard sats > 0, sats <= Double(Int.max) else { return nil }
    return Int(sats)
}

private let btcInputDecimals = 8

func filterBtcInput(_ raw: String) -> String {
    var result = ""
    var sawDot = false
    for ch in raw {
        if ch.isNumber {
            result.append(ch)
        } else if ch == ".", !sawDot {
            sawDot = true
            result.append(ch)
        }
    }
    if let dot = result.firstIndex(of: ".") {
        let decimals = result.distance(from: result.index(after: dot), to: result.endIndex)
        if decimals > btcInputDecimals {
            let end = result.index(result.index(after: dot), offsetBy: btcInputDecimals)
            result = String(result[..<end])
        }
    }
    return result
}
