import Foundation

/// Outcome of parsing the bytes received so far on one HTTP/1.1 connection.
enum HTTPParseResult {
    /// More bytes are needed.
    case incomplete
    /// A full request (request line, headers, and a `Content-Length` body).
    case complete(HTTPRequestLite)
    /// The request is rejected with this status (then the connection closes).
    case failure(status: Int)
}

/// Minimal HTTP/1.1 request parsing and response encoding for Bunny's loopback MCP server.
/// One request per connection: no keep-alive, no pipelining, no chunked bodies.
enum HTTPMessageCodec {
    /// Largest accepted body (1 MB); bigger bodies get 413.
    static let maxBodyBytes = 1_048_576
    /// Largest accepted request line plus headers; bigger heads get 431.
    static let maxHeadBytes = 32_768

    private static let headTerminator = Data("\r\n\r\n".utf8)

    /// Parses `buffer`, the bytes received so far. Header names are lowercased; the path excludes
    /// any query string.
    static func parse(_ buffer: Data) -> HTTPParseResult {
        guard let terminator = buffer.range(of: headTerminator) else {
            return buffer.count > maxHeadBytes ? .failure(status: 431) : .incomplete
        }
        let headLength = terminator.lowerBound - buffer.startIndex
        guard headLength <= maxHeadBytes else { return .failure(status: 431) }
        guard let head = String(data: buffer[buffer.startIndex..<terminator.lowerBound], encoding: .utf8) else {
            return .failure(status: 400)
        }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, !requestLine[0].isEmpty, requestLine[1].hasPrefix("/"),
              requestLine[2].hasPrefix("HTTP/1.")
        else { return .failure(status: 400) }
        let method = String(requestLine[0])
        let target = requestLine[1]
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(status: 400) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" ") else { return .failure(status: 400) }
            if let existing = headers[name] {
                // Conflicting duplicate lengths are a request-smuggling shape; reject them.
                if name == "content-length" && existing != value { return .failure(status: 400) }
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        // No chunked (or any other transfer coding) bodies.
        if headers["transfer-encoding"] != nil { return .failure(status: 400) }

        var contentLength = 0
        if let raw = headers["content-length"] {
            let value = raw.components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber),
                  let length = Int(value)
            else { return .failure(status: 400) }
            guard length <= maxBodyBytes else { return .failure(status: 413) }
            contentLength = length
        }

        let bodyStart = terminator.upperBound
        let available = buffer.endIndex - bodyStart
        guard available >= contentLength else { return .incomplete }
        let body = Data(buffer[bodyStart..<(bodyStart + contentLength)])
        return .complete(HTTPRequestLite(method: method, path: path, headers: headers, body: body))
    }

    /// Encodes `response` as HTTP/1.1 with `Content-Length` and `Connection: close`.
    static func encode(_ response: HTTPResponseLite) -> Data {
        var head = "HTTP/1.1 \(response.status) \(reasonPhrase(response.status))\r\n"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key })
        where name.lowercased() != "content-length" && name.lowercased() != "connection" {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        return data
    }

    /// An empty-bodied response with just a status (used for parse failures).
    static func statusResponse(_ status: Int) -> HTTPResponseLite {
        HTTPResponseLite(status: status, headers: [:], body: Data())
    }

    static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 413: return "Content Too Large"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}
