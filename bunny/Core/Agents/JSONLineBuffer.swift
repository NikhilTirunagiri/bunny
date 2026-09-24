import Foundation

struct JSONLineBuffer {
    private var buffer = Data()

    /// Appends bytes; returns complete non-empty lines (without "\n" / "\r\n"). Keeps a partial trailing line.
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)

            if line.last == 0x0D {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }
}
