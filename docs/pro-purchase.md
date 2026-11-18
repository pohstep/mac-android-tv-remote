# Zapbar Pro purchase

Zapbar stays free. Zapbar Pro is one non-consumable in-app purchase.

- Product id: `app.pohstep.remote.pro`
- Reference name: Zapbar Pro
- Price: $1.99 in the US. App Store Connect equalises the other storefronts.
- Type: Non-Consumable. There is no subscription and no introductory offer.
- Trial: none. The free remote is the way to try pairing.
- Family Sharing: on. In App Store Connect this is the Family Sharing switch on the in-app purchase. `macos/PohstepRemote/Products.storekit` sets `familyShareable` to true for local StoreKit tests.
- Restore: Settings shows Restore Purchase, which calls `AppStore.sync()` and reads `Transaction.currentEntitlements`.
- Offline: StoreKit 2 keeps the signed transaction on the Mac. No Zapbar server and no account.
- Revocation: a transaction with a revocation date is not treated as unlocked.
- App Store Connect product creation waits on the Apple Developer account. That account is not part of this milestone.

The local configuration file is for StoreKit Testing in Xcode. It does not create the live product.
