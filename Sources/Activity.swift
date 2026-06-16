import Foundation

/// A lightweight terminal activity spinner that animates on standard error.
///
/// Enabled globally via the `--activity` flag. The spinner coordinates with
/// `Terminal` output so that lines printed to stdout/stderr are not garbled by
/// the in-progress animation: callers wrap their writes in ``suspend(_:)``.
final class ActivityIndicator {
    /// The spinner that is currently animating, if any. `Terminal` consults this
    /// so it can clear the spinner line before emitting output.
    static var current: ActivityIndicator?

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private let message: String
    private let interval: TimeInterval
    private let lock = NSRecursiveLock()
    private var thread: Thread?
    private var running = false

    init(message: String = "Working", interval: TimeInterval = 0.08) {
        self.message = message
        self.interval = interval
    }

    /// Whether a spinner can be drawn (stderr must be an interactive TTY).
    static var isSupported: Bool {
        isatty(fileno(stderr)) == 1
    }

    /// Begins animating the spinner on a background thread.
    func start() {
        guard Self.isSupported else { return }

        lock.lock()
        running = true
        lock.unlock()
        Self.current = self

        let thread = Thread { [weak self] in
            guard let self else { return }
            var index = 0
            while true {
                self.lock.lock()
                guard self.running else {
                    self.lock.unlock()
                    break
                }
                let frame = Self.frames[index % Self.frames.count]
                self.write("\r\(frame) \(self.message)…")
                self.lock.unlock()

                index += 1
                Thread.sleep(forTimeInterval: self.interval)
            }
        }
        thread.stackSize = 64 * 1024
        self.thread = thread
        thread.start()
    }

    /// Stops the spinner and clears its line.
    func stop() {
        guard Self.isSupported else { return }
        lock.lock()
        running = false
        clearLine()
        lock.unlock()
        Self.current = nil
        thread = nil
    }

    /// Runs `body` with the spinner line cleared so output is not interleaved
    /// with the animation. The spinner resumes drawing on its next tick.
    func suspend(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        clearLine()
        body()
    }

    // MARK: - Private

    /// Erases the current terminal line. Must be called while holding `lock`.
    private func clearLine() {
        write("\r\u{001B}[2K")
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
