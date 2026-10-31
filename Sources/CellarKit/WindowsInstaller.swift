import CellarDomain
import Foundation

/// Shared helper for the Windows installers the stores hand us.
public enum WindowsInstaller {
    /// Whether a downloaded file really is a Windows executable. A CDN answers an outage with a
    /// perfectly valid HTML error page; feeding that to Wine fails in a baffling way, so every
    /// store installer is checked for the `MZ` magic before it is executed.
    public static func isPortableExecutable(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 2) == Data([0x4D, 0x5A])   // "MZ"
    }
}
