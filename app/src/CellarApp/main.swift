import CellarDomain
import AppKit
import CellarKit
import CellarInfrastructure
import CellarUI
import SwiftUI

// Top-level code is not main-actor isolated in the Swift 5 language mode, though it does run on the
// main thread; say so, so the main-actor AppDelegate can be made here.
// The app is a composition root, like the CLI's `main`: it reads the library, the bottles and the
// store clients' state in-process, and that goes through CellarKit's `StoreAdapter` port, so the
// real adapters are wired in before anything can ask. This file is the only one in the app that
// imports CellarInfrastructure (ArchitectureTests holds it to that).
CellarInfrastructure.install()

MainActor.assumeIsolated {
    // The store marks show each store's real icon when it is installed; finding it is the engine's
    // job, so the UI library is told where to ask rather than importing CellarKit.
    StoreIcons.use(InstalledStoreArtwork())
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
