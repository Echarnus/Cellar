import CellarDomain
import Foundation

/// A node in Steam's binary key-values (binKV) format used by shortcuts.vdf.
public indirect enum VDFValue {
    case map([(String, VDFValue)])
    case string(String)
    case uint32(UInt32)
}
