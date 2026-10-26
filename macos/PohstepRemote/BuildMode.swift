import Foundation

enum BuildMode {
    /// Set by scripts/build-local.sh when SANDBOX=1. The sandboxed build hides
    /// global keyboard capture; that API is not available inside the App Sandbox.
    static let sandbox: Bool = {
        #if SANDBOX_BUILD
        return true
        #else
        return false
        #endif
    }()
}
