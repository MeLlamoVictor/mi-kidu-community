// Compilar con BlobatarEngine.swift y KiduCommunityIcon.swift del mismo checkout.
import AppKit
import Foundation
import SwiftUI

@main @MainActor
struct RenderCommunityIcons {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func json(_ value: [String: Any], at path: URL) throws {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: path)
        }
        let info = ["author": "xcode", "version": 1] as [String: Any]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json(["info": info], at: directory.appendingPathComponent("Contents.json"))
        func render(_ sample: KiduCommunityIcon.Sample, dark: Bool, mac: Bool, side: Int, to url: URL) throws {
            let tile = KiduCommunityIcon.Tile(seed: sample.seed, color: sample.color, kind: .child,
                                              dark: dark, rounded: mac)
            let renderer = ImageRenderer(content: tile.frame(width: 1024, height: 1024))
            renderer.scale = Double(side) / 1024
            renderer.isOpaque = !mac
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            // El exportador del sistema puede añadir EXIF. Distribuimos solo píxeles y color.
            var clean = Data(data.prefix(8))
            var offset = 8
            while offset + 12 <= data.count {
                let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) + Int($1) }
                let end = offset + length + 12
                guard end <= data.count else { throw CocoaError(.fileReadCorruptFile) }
                let tag = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
                if !["eXIf", "tEXt", "zTXt", "iTXt", "tIME"].contains(tag) {
                    clean.append(contentsOf: data[offset..<end])
                }
                offset = end
            }
            guard offset == data.count else { throw CocoaError(.fileReadCorruptFile) }
            try clean.write(to: url)
        }
        for sample in KiduCommunityIcon.samples {
            let folder = directory.appendingPathComponent(sample.asset + ".appiconset", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var images: [[String: Any]] = []
            for dark in [false, true] {
                let file = dark ? "iOS-Dark.png" : "iOS-Light.png"
                try render(sample, dark: dark, mac: false, side: 1024, to: folder.appendingPathComponent(file))
                var entry: [String: Any] = ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": file]
                if dark { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
                images.append(entry)
            }
            if sample.asset == "AppIcon" {
                for size in [16, 32, 128, 256, 512] {
                    for scale in [1, 2] {
                        let file = "Mac-\(size)x\(scale).png"
                        try render(sample, dark: false, mac: true, side: size * scale, to: folder.appendingPathComponent(file))
                        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": file])
                    }
                }
            }
            try json(["images": images, "info": info], at: folder.appendingPathComponent("Contents.json"))
        }
    }
}
