import Foundation
import Darwin

/// Listens on a Unix domain socket for JSON events from `doneko-notify`.
final class SocketServer: @unchecked Sendable {
    static let shared = SocketServer()

    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.yiming.doneko.socket", qos: .userInitiated)
    private var onEvent: ((Data) -> Void)?

    var socketPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Doneko", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("doneko.sock").path
    }

    func start(handler: @escaping (Data) -> Void) {
        onEvent = handler
        queue.async { [weak self] in
            self?.bindAndListen()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func bindAndListen() {
        let path = socketPath
        try? FileManager.default.removeItem(atPath: path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count + 1 <= maxPath else {
            close(fd)
            serverFD = -1
            return
        }

        // sun_path is a C fixed array exposed as a Swift tuple — write via .0 pointer.
        memset(&addr.sun_path, 0, maxPath)
        path.withCString { cString in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dst in
                strncpy(dst, cString, maxPath - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            serverFD = -1
            return
        }

        chmod(path, S_IRUSR | S_IWUSR)

        guard Darwin.listen(fd, 16) == 0 else {
            close(fd)
            serverFD = -1
            return
        }

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source = src
        src.resume()
    }

    private func acceptClient() {
        let client = Darwin.accept(serverFD, nil, nil)
        guard client >= 0 else { return }
        queue.async { [weak self] in
            defer { close(client) }
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(client, &chunk, chunk.count)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk.prefix(n))
                if buffer.count > 256 * 1024 { break }
                if buffer.contains(UInt8(ascii: "\n")) { break }
            }
            if buffer.last == UInt8(ascii: "\n") {
                buffer.removeLast()
            }
            guard !buffer.isEmpty else { return }
            let handler = self?.onEvent
            DispatchQueue.main.async {
                handler?(buffer)
            }
        }
    }
}
