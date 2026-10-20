import Foundation
import AppKit

// MARK: - Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, notes: String, downloadURL: URL)
    case downloading(progress: Double)
    case readyToRelaunch(stagedAppURL: URL)
    case error(message: String)
}

// MARK: - UpdateService

@MainActor
final class UpdateService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateService()

    private let repoOwner = "dendyadinirwana"
    private let repoName = "nilaikinerja"

    @Published var status: UpdateStatus = .idle
    @Published var lastChecked: Date? = nil
    @Published var downloadProgress: Double = 0.0

    private var activeDownloadTask: URLSessionDownloadTask?
    private var stagedAppURL: URL?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Version Comparison

    /// Returns true if `v1` is strictly newer than `v2` using semantic versioning.
    static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let num1 = i < parts1.count ? parts1[i] : 0
            let num2 = i < parts2.count ? parts2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }

    // MARK: - Check For Updates

    func checkForUpdates(explicit: Bool = true) {
        guard status != .checking else { return }
        if case .downloading = status { return }
        if case .readyToRelaunch = status { return }

        status = .checking
        NKLog("[Update] Checking for updates at GitHub: \(repoOwner)/\(repoName)")

        let endpointString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: endpointString) else {
            status = .error(message: "URL endpoint rilis tidak valid")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NilaiKinerja-macOS-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    self.status = .error(message: "Gagal memverifikasi respons server")
                    return
                }

                if http.statusCode == 404 {
                    // No releases published yet on this repository
                    self.lastChecked = Date()
                    self.status = .upToDate
                    return
                }

                guard http.statusCode == 200 else {
                    if http.statusCode == 403 {
                        self.status = .error(message: "Batas request GitHub tercapai, coba lagi nanti")
                    } else {
                        self.status = .error(message: "Server merespons kode: HTTP \(http.statusCode)")
                    }
                    return
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.lastChecked = Date()

                if Self.isVersion(release.tagName, newerThan: self.currentVersion) {
                    // Find dmg or zip package asset
                    let packageAsset = release.assets.first { asset in
                        asset.name.hasSuffix(".dmg")
                    } ?? release.assets.first { asset in
                        asset.name.hasSuffix(".zip")
                    }

                    if let asset = packageAsset, let downloadURL = URL(string: asset.browserDownloadUrl) {
                        self.status = .available(
                            version: release.tagName,
                            notes: release.body ?? "Pembaruan versi \(release.tagName) tersedia.",
                            downloadURL: downloadURL
                        )
                    } else if let htmlUrl = URL(string: release.htmlUrl) {
                        // Fallback: no direct package uploaded, point to release page
                        self.status = .available(
                            version: release.tagName,
                            notes: release.body ?? "Pembaruan versi \(release.tagName) tersedia.",
                            downloadURL: htmlUrl
                        )
                    } else {
                        self.status = .upToDate
                    }
                } else {
                    self.status = .upToDate
                }
            } catch {
                NKLog("[Update] Check failed: \(error.localizedDescription)")
                self.status = .error(message: "Tidak dapat terhubung ke GitHub (\(error.localizedDescription))")
            }
        }
    }

    // MARK: - Download & Staging

    func downloadAndInstall() {
        guard case .available(let version, _, let downloadURL) = status else { return }

        // If URL points to browser htmlUrl (no direct dmg or zip), open in browser
        let ext = downloadURL.pathExtension.lowercased()
        let isDirect = ext == "dmg" || ext == "zip" || downloadURL.lastPathComponent.contains(".dmg") || downloadURL.lastPathComponent.contains(".zip")
        if !isDirect {
            NSWorkspace.shared.open(downloadURL)
            return
        }

        status = .downloading(progress: 0.0)
        downloadProgress = 0.0

        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: .main)
        let task = session.downloadTask(with: downloadURL)
        activeDownloadTask = task
        task.resume()
        NKLog("[Update] Downloading asset for \(version) from \(downloadURL)")
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0
        Task { @MainActor in
            self.downloadProgress = min(1.0, max(0.0, progress))
            self.status = .downloading(progress: self.downloadProgress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let reqURL = downloadTask.originalRequest?.url
        let isDmg = reqURL?.pathExtension.lowercased() == "dmg"
            || reqURL?.lastPathComponent.lowercased().contains(".dmg") == true
            || downloadTask.response?.suggestedFilename?.lowercased().hasSuffix(".dmg") == true

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NilaiKinerja-Staging-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            if isDmg {
                let tempDmg = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NilaiKinerja-OTA-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: location, to: tempDmg)
                defer { try? FileManager.default.removeItem(at: tempDmg) }

                let mountDir = stagingDir.appendingPathComponent("mount", isDirectory: true)
                try FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)

                let attach = Process()
                attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                attach.arguments = ["attach", "-nobrowse", "-readonly", tempDmg.path, "-mountpoint", mountDir.path]
                try attach.run()
                attach.waitUntilExit()

                let appInMount = mountDir.appendingPathComponent("NilaiKinerja.app")
                let extractedApp = stagingDir.appendingPathComponent("NilaiKinerja.app")

                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = [appInMount.path, extractedApp.path]
                try ditto.run()
                ditto.waitUntilExit()

                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountDir.path, "-force"]
                try? detach.run()
                detach.waitUntilExit()
            } else {
                let tempZip = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NilaiKinerja-OTA-\(UUID().uuidString).zip")
                try FileManager.default.moveItem(at: location, to: tempZip)
                defer { try? FileManager.default.removeItem(at: tempZip) }

                // Extract using macOS ditto to preserve symlinks and app bundle signatures
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", tempZip.path, stagingDir.path]
                try ditto.run()
                ditto.waitUntilExit()
            }

            let extractedApp = stagingDir.appendingPathComponent("NilaiKinerja.app")
            guard FileManager.default.fileExists(atPath: extractedApp.path) else {
                Task { @MainActor in
                    self.status = .error(message: "Paket pembaruan tidak berisi NilaiKinerja.app yang valid")
                }
                return
            }

            Task { @MainActor in
                self.stagedAppURL = extractedApp
                self.status = .readyToRelaunch(stagedAppURL: extractedApp)
                NKLog("[Update] Successfully staged new app at \(extractedApp.path)")
            }
        } catch {
            Task { @MainActor in
                self.status = .error(message: "Gagal memproses pembaruan: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            self.status = .error(message: "Unduhan gagal: \(error.localizedDescription)")
        }
    }

    // MARK: - Relaunch Execution

    func relaunchApp() {
        guard case .readyToRelaunch(let newAppURL) = status else { return }

        let currentAppPath = Bundle.main.bundleURL.path
        let targetAppPath = currentAppPath.hasPrefix("/Applications") ? currentAppPath : "/Applications/NilaiKinerja.app"
        let pid = ProcessInfo.processInfo.processIdentifier

        let scriptPath = "/tmp/nk_relaunch_\(pid).sh"
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.15; done
        rm -rf "\(targetAppPath)"
        /usr/bin/ditto "\(newAppURL.path)" "\(targetAppPath)"
        /usr/bin/xattr -cr "\(targetAppPath)"
        /usr/bin/open "\(targetAppPath)"
        rm -f "\(scriptPath)"
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()

            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/bash")
            relauncher.arguments = [scriptPath]
            try relauncher.run()

            NKLog("[Update] Relauncher dispatched, terminating current app...")
            NSApp.terminate(nil)
        } catch {
            status = .error(message: "Gagal merestart aplikasi: \(error.localizedDescription)")
        }
    }
}
