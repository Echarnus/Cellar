import CellarDomain
import Foundation
import Testing
@testable import CellarKit

/// A download left running after its parent died keeps taking back the default logon id that every
/// download shares — so every later install failed with "Lost connection to Steam". Only the
/// orphan may be reaped: a run another Cellar process still drives is not ours to stop.
struct DepotOrphanTests {
    private let binary = "/Users/me/Library/Application Support/Cellar/tools/depotdownloader/DepotDownloader"

    @Test("An orphaned download is found; one with a live parent and other programs are not")
    func onlyOrphansMatch() {
        // Shape of the real incident: PPID 1, a path with a space in it, arguments after.
        let listing = """
          501     1 \(binary) -app 489830 -os windows -dir /x
          502   900 \(binary) -app 489830 -os windows -dir /x
          503     1 \(binary)
          504     1 /usr/bin/other-tool \(binary) -app 1
          505     1 \(binary)-old -app 1
        """
        #expect(DepotTool.orphanedPIDs(in: listing, binary: binary) == [501, 503])
    }

    @Test("Nothing is found in an empty listing or garbage")
    func emptyAndGarbage() {
        #expect(DepotTool.orphanedPIDs(in: "", binary: binary).isEmpty)
        #expect(DepotTool.orphanedPIDs(in: "not a ps line\n\n", binary: binary).isEmpty)
    }
}
