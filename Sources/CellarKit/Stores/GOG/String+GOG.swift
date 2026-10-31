import CellarDomain
import Foundation

extension String {
    init(decoding data: Data) { self = String(data: data, encoding: .utf8) ?? "" }
}
