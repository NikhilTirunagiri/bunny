import Foundation
import Testing
@testable import BunnyCore

struct JSONLineBufferTests {
    @Test func splitAcrossChunks() {
        var buffer = JSONLineBuffer()

        #expect(buffer.append(Data("{\"one\":".utf8)).isEmpty)
        let lines = buffer.append(Data("1}\n".utf8))

        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["{\"one\":1}"])
    }

    @Test func handlesCRLFAndMultipleLines() {
        var buffer = JSONLineBuffer()

        let lines = buffer.append(Data("first\r\nsecond\nthird\r\n".utf8))

        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["first", "second", "third"])
    }

    @Test func skipsEmptyLinesAndKeepsTrailingPartialLine() {
        var buffer = JSONLineBuffer()

        let first = buffer.append(Data("\nalpha\n\npart".utf8))
        let second = buffer.append(Data("ial\n\n".utf8))

        #expect(first.map { String(decoding: $0, as: UTF8.self) } == ["alpha"])
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == ["partial"])
    }
}
