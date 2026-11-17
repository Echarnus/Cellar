import CellarDomain
import Foundation

/// Asking macOS whether a file is signed by who it should be.
enum CodeSignature {
    /// Apple's D3DMetal as Apple signs it, by file name: the framework and the library beside it.
    static let d3dMetal = [
        "D3DMetal.framework": #"identifier "com.apple.D3DMetal" and anchor apple"#,
        "libd3dshared.dylib": #"identifier "com.apple.libd3dshared" and anchor apple"#,
    ]

    /// Whether `file` has a valid signature that meets `requirement`, in codesign's own language.
    static func satisfies(_ file: URL, _ requirement: String) -> Bool {
        Shell.run("/usr/bin/codesign", ["--verify", "--strict", "-R=\(requirement)", file.path]).succeeded
    }

    /// Throw unless every D3DMetal under `root` (a freshly unpacked runner) is Apple's own, and,
    /// when the runner is meant to have one, unless there is one. It comes out of a third party's
    /// archive, wherever that archive keeps it, and it is native code loaded into every game.
    static func requireAppleD3DMetal(under root: URL, expected: Bool,
                                     satisfies: (URL, String) -> Bool = satisfies) throws {
        var found = false
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard let requirement = d3dMetal[file.lastPathComponent] else { continue }
            found = true
            files?.skipDescendants()
            guard satisfies(file, requirement) else {
                throw CellarError.ioFailure("\(file.lastPathComponent) in this download is not signed by Apple, "
                    + "so Cellar won't use it. Nothing was installed.")
            }
        }
        if expected, !found {
            throw CellarError.ioFailure("This download has no D3DMetal in it. Nothing was installed.")
        }
    }
}
