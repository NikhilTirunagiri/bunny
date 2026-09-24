import Foundation
import Testing
@testable import BunnyCore

struct HTTPMessageCodecTests {

    private func request(_ head: String, body: String = "") -> Data {
        var data = Data(head.utf8)
        data.append(Data(body.utf8))
        return data
    }

    private func completed(_ result: HTTPParseResult) -> HTTPRequestLite? {
        if case .complete(let request) = result { return request }
        return nil
    }

    private func failureStatus(_ result: HTTPParseResult) -> Int? {
        if case .failure(let status) = result { return status }
        return nil
    }

    private func isIncomplete(_ result: HTTPParseResult) -> Bool {
        if case .incomplete = result { return true }
        return false
    }

    @Test func parsesPostWithBody() {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let head = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        let parsed = completed(HTTPMessageCodec.parse(request(head, body: body)))
        #expect(parsed?.method == "POST")
        #expect(parsed?.path == "/mcp")
        #expect(parsed?.headers["authorization"] == "Bearer abc")
        #expect(parsed?.body == Data(body.utf8))
    }

    @Test func missingContentLengthMeansEmptyBody() {
        let parsed = completed(HTTPMessageCodec.parse(request("GET /mcp HTTP/1.1\r\nHost: x\r\n\r\n")))
        #expect(parsed?.method == "GET")
        #expect(parsed?.body.isEmpty == true)
    }

    @Test func incompleteHeadIsIncomplete() {
        #expect(isIncomplete(HTTPMessageCodec.parse(request("POST /mcp HTTP/1.1\r\nHost: x\r\n"))))
    }

    @Test func incompleteBodyIsIncomplete() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
        #expect(isIncomplete(HTTPMessageCodec.parse(request(head, body: "12345"))))
    }

    @Test func extraBytesAfterBodyAreIgnored() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: 3\r\n\r\n"
        let parsed = completed(HTTPMessageCodec.parse(request(head, body: "abcdef")))
        #expect(parsed?.body == Data("abc".utf8))
    }

    @Test func chunkedIsRejected() {
        let head = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
        #expect(failureStatus(HTTPMessageCodec.parse(request(head, body: "3\r\nabc\r\n0\r\n\r\n"))) == 400)
    }

    @Test func oversizedBodyIsRejected() {
        let tooBig = HTTPMessageCodec.maxBodyBytes + 1
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: \(tooBig)\r\n\r\n"
        #expect(failureStatus(HTTPMessageCodec.parse(request(head))) == 413)
    }

    @Test func invalidContentLengthIsRejected() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
        #expect(failureStatus(HTTPMessageCodec.parse(request(head))) == 400)
    }

    @Test func conflictingContentLengthsAreRejected() {
        let head = "POST /mcp HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"
        #expect(failureStatus(HTTPMessageCodec.parse(request(head, body: "ab"))) == 400)
    }

    @Test func malformedRequestLineIsRejected() {
        #expect(failureStatus(HTTPMessageCodec.parse(request("NONSENSE\r\n\r\n"))) == 400)
    }

    @Test func headerWithoutColonIsRejected() {
        #expect(failureStatus(HTTPMessageCodec.parse(request("POST /mcp HTTP/1.1\r\nBogus\r\n\r\n"))) == 400)
    }

    @Test func oversizedHeadIsRejected() {
        let filler = String(repeating: "a", count: HTTPMessageCodec.maxHeadBytes + 1)
        #expect(failureStatus(HTTPMessageCodec.parse(request("POST /mcp HTTP/1.1\r\nX: \(filler)"))) == 431)
    }

    @Test func encodesResponseWithLengthAndClose() {
        let response = HTTPResponseLite(status: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        let text = String(data: HTTPMessageCodec.encode(response), encoding: .utf8)
        let expected = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
        #expect(text == expected)
    }

    @Test func encodesEmptyStatusResponse() {
        let text = String(data: HTTPMessageCodec.encode(HTTPMessageCodec.statusResponse(401)), encoding: .utf8)
        let expected = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        #expect(text == expected)
    }
}
