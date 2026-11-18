import Foundation
import StoreKit

@MainActor
final class ProStore: ObservableObject {
    @Published private(set) var unlocked = false
    private var updates: Task<Void, Never>?

    func start() {
        updates?.cancel()
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.absorb(update)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = verified(entitlement) else { continue }
            if transaction.productID == ProProduct.id && transaction.revocationDate == nil {
                found = true
            }
        }
        unlocked = found
    }

    func purchase() async {
        guard let product = try? await Product.products(for: [ProProduct.id]).first else { return }
        guard let result = try? await product.purchase() else { return }
        switch result {
        case .success(let verification):
            guard let transaction = verified(verification) else { return }
            unlocked = transaction.revocationDate == nil
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    private func absorb(_ result: VerificationResult<Transaction>) async {
        guard let transaction = verified(result) else { return }
        if transaction.productID == ProProduct.id {
            unlocked = transaction.revocationDate == nil
        }
        await transaction.finish()
    }

    private func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            return nil
        }
    }
}
