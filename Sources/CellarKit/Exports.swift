// The domain types (`GameStore`, `StoreDescriptor`, `LaunchStage`, `InstallProgress`, `GameEvent`,
// `CommandEvent`, `LaunchRoute`) live in `CellarDomain`, a module with no I/O in it, which the
// compiler checks in Swift 6 mode. Re-exported so every `import CellarKit` keeps seeing them.
@_exported import CellarDomain
