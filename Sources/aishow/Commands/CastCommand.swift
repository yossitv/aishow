import AishowCore
import Foundation

/// `aishow cast` — 実装は docs/steps/ の該当 Step で行う。
enum CastCommand {
    static func run(_ args: [String]) -> Int32 {
        FileHandle.standardError.write("aishow cast: not implemented yet (see docs/steps/)\n".data(using: .utf8)!)
        return 70
    }
}
