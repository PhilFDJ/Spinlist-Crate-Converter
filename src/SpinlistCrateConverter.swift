// SpinlistCrateConverter.swift
// A self-contained macOS app that converts .m3u / .m3u8 playlists into Serato
// crates (~/Music/_Serato_/Subcrates). Drag files onto the window or onto the
// app icon. No third-party dependencies.
//
// Build with -parse-as-library (see build.sh).

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Serato .crate binary writer

enum Crate {
    static let version = "1.0/Serato ScratchLive Crate"

    /// tag = 4 ASCII bytes + 4-byte big-endian length + payload
    static func tag(_ name: String, _ payload: Data) -> Data {
        var d = Data()
        d.append(contentsOf: Array(name.utf8))            // 4 ASCII bytes
        let n = UInt32(payload.count)
        d.append(UInt8((n >> 24) & 0xFF))
        d.append(UInt8((n >> 16) & 0xFF))
        d.append(UInt8((n >> 8) & 0xFF))
        d.append(UInt8(n & 0xFF))
        d.append(payload)
        return d
    }

    /// UTF-16 big-endian text payload (no BOM)
    static func text(_ name: String, _ s: String) -> Data {
        var bytes = [UInt8]()
        for u in Array(s.utf16) {
            bytes.append(UInt8((u >> 8) & 0xFF))
            bytes.append(UInt8(u & 0xFF))
        }
        return tag(name, Data(bytes))
    }

    static func build(paths: [String]) -> Data {
        var out = Data()
        out.append(text("vrsn", version))

        // sort + default column view (cosmetic, matches native crates)
        var osrt = Data()
        osrt.append(text("tvcn", "song"))
        osrt.append(tag("brev", Data([0])))
        out.append(tag("osrt", osrt))

        for col in ["song", "artist", "album", "length", "bpm", "key", "comment"] {
            var ovct = Data()
            ovct.append(text("tvcn", col))
            ovct.append(text("tvcw", "0"))
            out.append(tag("ovct", ovct))
        }

        for p in paths {
            out.append(tag("otrk", text("ptrk", p)))
        }
        return out
    }
}

// MARK: - Playlist parsing / conversion

struct ConvResult: Identifiable {
    let id = UUID()
    var playlist: String
    var crate: String
    var tracks: Int = 0
    var missing: Int = 0
    var unresolved: Int = 0
    var written: Bool = false
    var note: String = ""
}

enum Converter {
    static func readText(_ url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let d = try? Data(contentsOf: url) {
            return String(data: d, encoding: .isoLatin1) ?? String(data: d, encoding: .utf8)
        }
        return nil
    }

    static func sanitize(_ s: String) -> String {
        var r = s.replacingOccurrences(of: "%%", with: "-")
        r = r.replacingOccurrences(of: "/", with: "-")
        r = r.replacingOccurrences(of: ":", with: "-")
        r = r.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? "playlist" : r
    }

    /// Resolve one playlist line to an absolute file URL, or nil if it can't be.
    static func entryToURL(_ entryIn: String, base: URL) -> URL? {
        var entry = entryIn.trimmingCharacters(in: .whitespacesAndNewlines)
        if entry.isEmpty || entry.hasPrefix("#") { return nil }

        if entry.lowercased().hasPrefix("file://") {
            if let u = URL(string: entry), u.isFileURL { return u }
        }
        if entry.contains("%") {
            let upper = entry.uppercased()
            if upper.contains("%20") || upper.contains("%2F"),
               let dec = entry.removingPercentEncoding {
                entry = dec
            }
        }
        entry = entry.replacingOccurrences(of: "\\", with: "/")

        if entry.hasPrefix("/") {
            return URL(fileURLWithPath: entry)
        }
        return base.appendingPathComponent(entry)
    }

    /// Serato stores paths relative to the volume root, without a leading slash.
    static func seratoPath(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        return p.hasPrefix("/") ? String(p.dropFirst()) : p
    }

    static func convert(url: URL, outDir: URL) -> ConvResult {
        let name = url.lastPathComponent
        let crateName = sanitize(url.deletingPathExtension().lastPathComponent)
        var r = ConvResult(playlist: name, crate: crateName)

        guard let text = readText(url) else {
            r.note = "couldn't read file"
            return r
        }
        let base = url.deletingLastPathComponent()
        var paths = [String]()
        for line in text.components(separatedBy: .newlines) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            guard let u = entryToURL(s, base: base) else {
                r.unresolved += 1
                continue
            }
            if !FileManager.default.fileExists(atPath: u.path) { r.missing += 1 }
            paths.append(seratoPath(u))
        }
        r.tracks = paths.count
        if paths.isEmpty {
            r.note = "no resolvable tracks"
            return r
        }
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            try Crate.build(paths: paths).write(to: outDir.appendingPathComponent(crateName + ".crate"))
            r.written = true
        } catch {
            r.note = "write failed: \(error.localizedDescription)"
        }
        return r
    }
}

// MARK: - Model

final class Model: ObservableObject {
    static let shared = Model()
    @Published var results: [ConvResult] = []
    @Published var busy = false

    let outDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/_Serato_/Subcrates")

    func process(_ urls: [URL]) {
        let playlists = urls.filter { ["m3u", "m3u8"].contains($0.pathExtension.lowercased()) }
        guard !playlists.isEmpty else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            var out = [ConvResult]()
            for u in playlists { out.append(Converter.convert(url: u, outDir: self.outDir)) }
            DispatchQueue.main.async {
                self.results = out
                self.busy = false
            }
        }
    }
}

// MARK: - App delegate (drop onto Dock icon / Open With)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Model.shared.process(urls)
    }
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Model.shared.process([URL(fileURLWithPath: filename)])
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - UI

private let navy = Color(red: 10/255, green: 18/255, blue: 40/255)
private let navy2 = Color(red: 15/255, green: 26/255, blue: 56/255)
private let lime = Color(red: 192/255, green: 240/255, blue: 72/255)
private let muted = Color(red: 124/255, green: 134/255, blue: 165/255)

struct ContentView: View {
    @EnvironmentObject var model: Model
    @State private var hot = false

    private var markImage: NSImage? {
        if let p = Bundle.main.path(forResource: "dropmark", ofType: "png") {
            return NSImage(contentsOfFile: p)
        }
        return nil
    }

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()
            VStack(spacing: 16) {
                if let img = markImage {
                    Image(nsImage: img).resizable().scaledToFit().frame(height: 68)
                }
                (Text("Spinlist ").foregroundColor(.white)
                 + Text("Crate Converter").foregroundColor(lime))
                    .font(.system(size: 20, weight: .bold))
                Text("Drop playlists → Serato crates")
                    .font(.system(size: 13)).foregroundColor(muted)

                dropZone

                if !model.results.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.results) { r in resultRow(r) }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                Text("Crates are written to ~/Music/_Serato_/Subcrates. Quit Serato before converting, then reopen it to see them.")
                    .font(.system(size: 11.5)).foregroundColor(muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
            .foregroundColor(hot ? lime : Color(red: 51/255, green: 64/255, blue: 110/255))
            .background(RoundedRectangle(cornerRadius: 18).fill(hot ? navy2 : navy2.opacity(0.6)))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 10) {
                    if model.busy {
                        ProgressView().controlSize(.large)
                    } else {
                        Text("Drag & drop your .m3u / .m3u8 files here")
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                        Text("or click to choose files").font(.system(size: 13)).foregroundColor(muted)
                        Text("Drop playlists")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(navy)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Capsule().fill(lime))
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { chooseFiles() }
            .onDrop(of: [UTType.fileURL], isTargeted: $hot) { providers in
                handleDrop(providers); return true
            }
            .padding(.vertical, 4)
    }

    private func warnText(_ r: ConvResult) -> String {
        var bits = [String]()
        if r.missing > 0 { bits.append("\(r.missing) missing") }
        if r.unresolved > 0 { bits.append("\(r.unresolved) relative skipped") }
        return bits.joined(separator: ", ")
    }

    private func resultRow(_ r: ConvResult) -> some View {
        let warn = warnText(r)
        let amber = Color(red: 1, green: 0.81, blue: 0.36)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.crate + ".crate").foregroundColor(.white).font(.system(size: 14, weight: .semibold))
                Text("from \(r.playlist)").foregroundColor(muted).font(.system(size: 12))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if r.written {
                    Text("✓ \(r.tracks) track\(r.tracks == 1 ? "" : "s")").foregroundColor(lime).font(.system(size: 13, weight: .semibold))
                    if !warn.isEmpty {
                        Text(warn).foregroundColor(amber).font(.system(size: 11.5))
                    }
                } else {
                    Text(r.note.isEmpty ? "skipped" : r.note).foregroundColor(amber).font(.system(size: 12))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(navy2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 38/255, green: 50/255, blue: 90/255)))
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let u = url {
                    DispatchQueue.main.async { Model.shared.process([u]) }
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["m3u", "m3u8"]
        if panel.runModal() == .OK {
            Model.shared.process(panel.urls)
        }
    }
}

@main
struct SpinlistCrateConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        WindowGroup("Spinlist Crate Converter") {
            ContentView().environmentObject(model)
        }
    }
}
