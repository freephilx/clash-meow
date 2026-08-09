import Darwin
import Foundation

final class YAMLFileChangeMonitor: @unchecked Sendable {
    private let url: URL
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var isStopped = false

    init(url: URL, queue: DispatchQueue = .global(qos: .utility), onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    func start() {
        isStopped = false
        startSource()
    }

    func stop() {
        isStopped = true
        source?.cancel()
        source = nil
    }

    private func startSource() {
        guard source == nil, FileManager.default.fileExists(atPath: url.path) else { return }

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let nextSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        nextSource.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source?.data ?? []
            self.onChange()
            if event.contains(.delete) || event.contains(.rename) {
                self.source?.cancel()
                self.source = nil
                guard !self.isStopped else { return }
                self.queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.startSource()
                }
            }
        }
        nextSource.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        source = nextSource
        nextSource.resume()
    }
}
