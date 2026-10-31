import Foundation

/// One downloadable artifact of a runner and where its payload lands inside the runner root.
public struct RunnerArtifact: Sendable {
    public enum Kind: Sendable {
        /// A Wine engine tarball. `payloadPath` is the directory inside the archive that holds
        /// `bin/wine` (e.g. `wswine.bundle`); it is moved to `<runner>/wine`.
        case wineEngine
        /// A Sikarugir/Wineskin wrapper template. Its `Contents/Frameworks` (renderers, D3DMetal,
        /// MoltenVK, GStreamer, dylibs) is moved to `<runner>/Frameworks`.
        case wrapperFrameworks
        /// A GPTK-style `.app` archive that already contains `Contents/Resources/wine/bin`.
        case gptkApp
        /// A `.dmg` holding a Wine tree at `payloadPath` (relative to the mount point); copied to `<runner>/wine`.
        case wineDMG
        /// A Sikarugir/Wineskin wrapper template whose `Contents/Frameworks/renderer/d3dmetal` is
        /// grafted into `<runner>/wine/lib/d3dmetal` — the layout WineForge reads via D3DMETAL_RUNTIME_DIR.
        case d3dmetalFromTemplate
    }
    public let kind: Kind
    public let url: String
    public let payloadPath: String
    /// The SHA-256 of the file at `url`, lowercase hex. Pinned because the file is somebody
    /// else's GitHub release asset, which its owner can replace at any time, and what is inside runs
    /// every game — so a download that does not match is refused before it is unpacked
    /// (`Checksum.verify`). Bumping a pin is a deliberate change, made in a reviewed PR.
    public let sha256: String

    public init(kind: Kind, url: String, payloadPath: String, sha256: String) {
        self.kind = kind
        self.url = url
        self.payloadPath = payloadPath
        self.sha256 = sha256
    }
}
