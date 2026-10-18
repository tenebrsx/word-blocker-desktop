import Foundation

/// Keeps a short buffer of what you just typed and runs it through the shared Word Block engine
/// (same engine + test vectors as the iOS browser).
final class TypingBuffer {
    private(set) var text = ""
    private let maxLen = 120

    /// Returns the number of characters to erase, or nil.
    func type(_ s: String, engine: WordBlockEngine) -> Int? {
        text += s
        if text.count > maxLen { text = String(text.suffix(maxLen)) }
        return check(engine: engine, isFinal: false)
    }

    func check(engine: WordBlockEngine, isFinal: Bool) -> Int? {
        let out = engine.sanitize(text, isFinal: isFinal)
        guard out != text else { return nil }
        let prefix = text.commonPrefix(with: out)
        let delete = text.count - prefix.count
        text = prefix
        return delete > 0 ? delete : nil
    }

    func backspace() { if !text.isEmpty { text.removeLast() } }
    func reset() { text = "" }
}

