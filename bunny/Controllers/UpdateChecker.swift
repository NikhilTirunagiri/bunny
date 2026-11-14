import Foundation
import Observation

/// "Check for updates" on Settings → About. Asks GitHub for the latest release only when the button
/// is clicked, never by itself, and sends nothing about the user. Nothing is downloaded or installed:
/// a newer version is offered as a link to its release page.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    static let repositoryPage = URL(string: "https://github.com/NikhilTirunagiri/bunny")!
    private static let releasesPage = repositoryPage.appendingPathComponent("releases")
    private static let latestRelease = URL(string: "https://api.github.com/repos/NikhilTirunagiri/bunny/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private(set) var state: State = .idle

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bunny", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // No cookies, cache or credentials are kept or sent.
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            let release = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let tag = release?["tag_name"] as? String
            let page = release?["html_url"] as? String
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    UpdateChecker.shared.state = Self.result(status: status, tag: tag, page: page)
                }
            }
        }.resume()
        session.finishTasksAndInvalidate()
    }

    private static func result(status: Int?, tag: String?, page: String?) -> State {
        if status == 404 { return .failed("No release has been published yet.") }
        guard status == 200, let tag else { return .failed("Couldn't check for updates. Try again later.") }
        guard VersionRules.isNewer(tag, than: currentVersion) else { return .upToDate }
        // Only ever open a GitHub page, whatever the response says.
        let link = page.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host == "github.com" ? $0 : nil }
        return .available(version: VersionRules.display(tag), page: link ?? releasesPage)
    }
}
