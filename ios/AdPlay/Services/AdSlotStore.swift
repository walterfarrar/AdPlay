import Foundation
import StoreKit

enum AdSlotProduct {
    static let id = "com.adplay.app.adslot"
}

@MainActor
final class AdSlotStore: ObservableObject {
    @Published var product: Product?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    func load() async {
        listenForUpdates()
        do {
            let products = try await Product.products(for: [AdSlotProduct.id])
            product = products.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase() async -> String? {
        guard let product else {
            errorMessage = "Ad Token purchase is not available yet."
            return nil
        }
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let id = String(transaction.id)
                await transaction.finish()
                return id
            case .userCancelled, .pending:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// StoreKit 2 restore: sync the Apple ID, then return every verified ad-slot transaction.
    func restoreTransactionIds() async -> [String] {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
        return await collectAdSlotTransactionIds()
    }

    func unfinishedTransactionIds() async -> [String] {
        await collectAdSlotTransactionIds()
    }

    private func collectAdSlotTransactionIds() async -> [String] {
        var seen = Set<UInt64>()
        var ids: [String] = []

        func take(_ result: VerificationResult<Transaction>) async {
            guard let transaction = try? checkVerified(result) else { return }
            guard transaction.productID == AdSlotProduct.id else { return }
            guard transaction.revocationDate == nil else { return }
            guard seen.insert(transaction.id).inserted else { return }
            ids.append(String(transaction.id))
            await transaction.finish()
        }

        if let latest = await product?.latestTransaction {
            await take(latest)
        }

        // Transaction.all / currentEntitlements stay open for new events.
        // Take the current snapshot, then stop so Restore cannot hang.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await result in Transaction.currentEntitlements {
                    guard !Task.isCancelled else { break }
                    await take(result)
                }
            }
            group.addTask { @MainActor in
                for await result in Transaction.all {
                    guard !Task.isCancelled else { break }
                    await take(result)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            await group.next()
            group.cancelAll()
        }
        return ids
    }

    private func listenForUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.checkVerified(result) else { continue }
                guard transaction.productID == AdSlotProduct.id else { continue }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw APIError.message("Purchase could not be verified")
        case .verified(let value):
            return value
        }
    }
}
