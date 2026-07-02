import Foundation
import SwiftTerm

// Two benchmarks for SwiftTerm:
//   vt      headless VT-core throughput (parsing + buffer update, no rendering)
//   render  end-to-end throughput through the live NSView (parse + layout + draw)
//
// Usage: swiftterm-bench [vt|render]

func rssMB() -> Int {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "rss=", "-p", "\(getpid())"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
    return (Int(s) ?? 0) / 1024
}

// MARK: - Headless VT core

final class NullTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

func makeChunk(targetBytes: Int, line: String) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(targetBytes + line.utf8.count)
    let lineBytes = Array(line.utf8)
    while out.count < targetBytes { out.append(contentsOf: lineBytes) }
    return out
}

func benchVT() {
    let term = Terminal(delegate: NullTerminalDelegate())
    term.resize(cols: 120, rows: 40)

    let plainLine = "The quick brown fox jumps over the lazy dog 0123456789\n"
    let ansiLine = "\u{1b}[31mERROR\u{1b}[0m \u{1b}[32m OK \u{1b}[0m \u{1b}[1;34minfo\u{1b}[0m building module 0123456789\n"
    let scrollLine = "\r\u{1b}[2K\u{1b}[33m[####################        ] 72%\u{1b}[0m progress step 0123456789\n"

    let chunkBytes = 8 * 1024 * 1024
    let totalTarget = 300 * 1024 * 1024

    func run(_ name: String, _ line: String) {
        let chunk = makeChunk(targetBytes: chunkBytes, line: line)
        var fed = 0
        let start = Date()
        while fed < totalTarget {
            term.feed(byteArray: chunk)
            fed += chunk.count
        }
        let elapsed = Date().timeIntervalSince(start)
        let mb = Double(fed) / (1024 * 1024)
        let mbps = mb / elapsed
        let padded = name.padding(toLength: 10, withPad: " ", startingAt: 0)
        print(String(format: "  %@ %7.1f MB in %6.3fs = %8.1f MB/s", padded, mb, elapsed, mbps))
    }

    print("== VT core throughput (headless, no rendering) ==")
    run("plain", plainLine)
    run("ansi", ansiLine)
    run("scroll", scrollLine)
    print("  RSS after: \(rssMB()) MB")
}

// MARK: - End-to-end through the live view

#if canImport(AppKit)
import AppKit

final class RenderBench: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    private var window: NSWindow!
    private var tv: LocalProcessTerminalView!
    private var start = Date()
    private let lines = 1_000_000
    private let sample = "The quick brown fox jumps over the lazy dog 0123456789"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .resizable],
                          backing: .buffered, defer: false)
        tv = LocalProcessTerminalView(frame: window.contentView!.bounds)
        tv.autoresizingMask = [.width, .height]
        tv.processDelegate = self
        window.contentView!.addSubview(tv)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("== End-to-end through live view ==")
        print("  streaming \(lines) lines (~\(lines * (sample.count + 1) / (1024*1024)) MB)...")
        start = Date()
        tv.startProcess(executable: "/bin/sh",
                        args: ["-c", "yes '\(sample)' | head -n \(lines)"])
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let elapsed = Date().timeIntervalSince(start)
        let bytes = Double(lines * (sample.count + 1))
        let mb = bytes / (1024 * 1024)
        print(String(format: "  %.1f MB ingested+rendered in %.3fs = %.1f MB/s", mb, elapsed, mb / elapsed))
        print("  RSS after (1 surface, full scrollback): \(rssMB()) MB")
        exit(0)
    }
}
#endif

// MARK: - main

let mode = CommandLine.arguments.dropFirst().first ?? "vt"
switch mode {
case "vt":
    benchVT()
case "render":
    #if canImport(AppKit)
    let app = NSApplication.shared
    let delegate = RenderBench()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    #else
    print("render mode requires AppKit")
    #endif
default:
    print("usage: swiftterm-bench [vt|render]")
}
