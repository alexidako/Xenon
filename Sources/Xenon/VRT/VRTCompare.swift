import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// `Xenon --vrt-compare <baselineDir> <currentDir> <diffDir>`
enum VRTCompare {
    /// A pixel differs when any colour channel is off by more than this (out of 255).
    static let channelTolerance = 6
    /// A screen fails when more than this share of its pixels differ.
    static let areaTolerance = 0.0015

    struct Bitmap { let w: Int, h: Int, px: [UInt8] }

    static func load(_ path: String) -> Bitmap? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(w: w, h: h, px: px)
    }

    static func write(_ b: Bitmap, to path: String) {
        var px = b.px
        guard let ctx = CGContext(data: &px, width: b.w, height: b.h, bitsPerComponent: 8, bytesPerRow: b.w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Fraction of pixels that differ, plus a diff image (changed pixels red over a dimmed copy of the new image).
    static func diff(_ a: Bitmap, _ b: Bitmap) -> (Double, Bitmap) {
        var out = b.px, changed = 0
        for i in stride(from: 0, to: a.px.count, by: 4) {
            let d = max(abs(Int(a.px[i]) - Int(b.px[i])), abs(Int(a.px[i + 1]) - Int(b.px[i + 1])), abs(Int(a.px[i + 2]) - Int(b.px[i + 2])))
            if d > channelTolerance {
                changed += 1; out[i] = 255; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = 255
            } else {
                out[i] = b.px[i] / 4; out[i + 1] = b.px[i + 1] / 4; out[i + 2] = b.px[i + 2] / 4; out[i + 3] = 255
            }
        }
        return (Double(changed) / Double(a.w * a.h), Bitmap(w: b.w, h: b.h, px: out))
    }

    static func run(baseline: String, current: String, diffDir: String) -> Int32 {
        let fm = FileManager.default
        try? fm.removeItem(atPath: diffDir)
        try? fm.createDirectory(atPath: diffDir, withIntermediateDirectories: true)
        func names(_ d: String) -> Set<String> {
            Set(((try? fm.contentsOfDirectory(atPath: d)) ?? []).filter { $0.hasSuffix(".png") })
        }
        let base = names(baseline), cur = names(current)
        var bad = 0, passed = 0
        for n in base.union(cur).sorted() {
            let name = String(n.dropLast(4))
            if !cur.contains(n) { print("MISSING  \(name)   (has a baseline but was not captured)"); bad += 1; continue }
            if !base.contains(n) { print("NEW      \(name)   (no baseline yet; run with --update to accept)"); bad += 1; continue }
            guard let a = load("\(baseline)/\(n)"), let b = load("\(current)/\(n)") else { print("ERROR    \(name)   (unreadable image)"); bad += 1; continue }
            if a.w != b.w || a.h != b.h { print("FAIL     \(name)   size changed \(a.w)x\(a.h) → \(b.w)x\(b.h)"); bad += 1; continue }
            let (share, img) = diff(a, b)
            if share > areaTolerance {
                write(img, to: "\(diffDir)/\(name).png")
                print(String(format: "FAIL     %@   %.2f%% of pixels changed → %@/%@.png", name, share * 100, diffDir, name)); bad += 1
            } else { passed += 1; print(String(format: "PASS     %@   (%.3f%% differ)", name, share * 100)) }
        }
        print("\n\(passed) passed, \(bad) need attention")
        return bad == 0 ? 0 : 1
    }
}
