import AishowCore
import Foundation

/// `aishow summon` — 実装は docs/steps/ の該当 Step で行う。
enum SummonCommand {
    static func run(_ args: [String]) -> Int32 {
        FileHandle.standardError.write("aishow summon: not implemented yet (see docs/steps/)\n".data(using: .utf8)!)
        return 70
    }
}
