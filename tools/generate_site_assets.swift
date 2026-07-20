#!/usr/bin/env swift
// Renders the marbled sheets used by the Shelfworth landing page (site/).
// Uses the same classical drop-and-tine marbling as the app and icon
// generator — see Library/Utilities/Marbling.swift and tools/generate_icon.swift.
//
// Run from anywhere:  swift tools/generate_site_assets.swift
// No dependencies — CoreGraphics only. Outputs into site/assets/.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Deterministic RNG

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + unit() * (hi - lo) }
}

// MARK: - Marbling (mirrors the in-app renderer)

typealias RGB = (Double, Double, Double)

struct MarblePalette {
    let paper: RGB
    let inks: [RGB]   // vein (darkest), mid, light, accent
    let gilt: RGB
}

let forestMarble = MarblePalette(
    paper: (0.91, 0.90, 0.79),
    inks: [(0.11, 0.25, 0.18), (0.47, 0.59, 0.45), (0.91, 0.90, 0.79), (0.55, 0.42, 0.20)],
    gilt: (0.83, 0.72, 0.42)
)

let espressoMarble = MarblePalette(
    paper: (0.13, 0.10, 0.06),
    inks: [(0.30, 0.12, 0.09), (0.33, 0.27, 0.17), (0.22, 0.18, 0.11), (0.14, 0.17, 0.24)],
    gilt: (0.62, 0.47, 0.26)
)

enum Op {
    case drop(cx: Double, cy: Double, r: Double, ink: Int)
    case comb(spacing: Double, phase: Double, z: Double, lambda: Double, dir: Double)
}

func invert(_ p: inout (x: Double, y: Double), _ op: Op) -> Int? {
    switch op {
    case let .drop(cx, cy, r, ink):
        let dx = p.x - cx, dy = p.y - cy
        let dist2 = dx * dx + dy * dy
        let r2 = r * r
        if dist2 <= r2 { return ink }
        let scale = (1 - r2 / dist2).squareRoot()
        p.x = cx + dx * scale
        p.y = cy + dy * scale
        return nil
    case let .comb(s, phase, z, lambda, dir):
        let t = (p.x - phase) / s
        let frac = t - t.rounded(.down)
        let d = abs(frac - 0.5) * s
        let dTine = s / 2 - d
        p.y -= dir * z * lambda / (dTine + lambda)
        return nil
    }
}

func nonpareilOps(rng: inout SplitMix) -> [Op] {
    [.comb(spacing: 34, phase: rng.range(0, 34), z: 240, lambda: 22, dir: 1)]
}

func bouquetOps(rng: inout SplitMix) -> [Op] {
    var ops = nonpareilOps(rng: &rng)
    ops.append(.comb(spacing: 102, phase: rng.range(0, 102), z: 210, lambda: 44, dir: -1))
    return ops
}

func lattice(_ ix: Int, _ iy: Int, _ seed: UInt64) -> Double {
    var h = UInt64(bitPattern: Int64(ix)) &* 0x9E3779B97F4A7C15
    h &+= UInt64(bitPattern: Int64(iy)) &* 0xC2B2AE3D27D4EB4F
    h ^= seed
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
    return Double((h ^ (h >> 31)) >> 11) / Double(1 << 53)
}

func smootherstep(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

func valueNoise(_ x: Double, _ y: Double, _ seed: UInt64) -> Double {
    let ix = Int(x.rounded(.down)), iy = Int(y.rounded(.down))
    let fx = smootherstep(x - Double(ix)), fy = smootherstep(y - Double(iy))
    let a = lattice(ix, iy, seed), b = lattice(ix + 1, iy, seed)
    let c = lattice(ix, iy + 1, seed), d = lattice(ix + 1, iy + 1, seed)
    let ab = a + (b - a) * fx, cd = c + (d - c) * fx
    return ab + (cd - ab) * fy
}

func fbm(_ x: Double, _ y: Double, _ octaves: Int, _ seed: UInt64) -> Double {
    var v = 0.0, amp = 0.5, freq = 1.0
    for i in 0..<octaves {
        v += amp * valueNoise(x * freq, y * freq, seed &+ UInt64(i) &* 0x85EBCA6B)
        amp *= 0.5; freq *= 2
    }
    return v
}

func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
}

/// Renders a marbled sheet — identical math to the app's launch endpapers.
func marbleSheet(palette: MarblePalette, pattern: String, seed: UInt64,
                 w: Int, h: Int, unitsPerPixel: Double, veins: Bool,
                 veinStrength: Double = 1.0, wash: Double = 0) -> CGImage {
    var rng = SplitMix(seed: seed)
    let ops: [Op]
    switch pattern {
    case "bouquet": ops = bouquetOps(rng: &rng)
    default: ops = nonpareilOps(rng: &rng)
    }
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    for py in 0..<h {
        for px in 0..<w {
            var p = (x: Double(px) * unitsPerPixel, y: Double(py) * unitsPerPixel)
            let wob = 2.2
            p.x += (fbm(p.y * 0.012, p.x * 0.012, 3, seed &+ 3) - 0.5) * 2 * wob
            p.y += (fbm(p.x * 0.011 + 9.7, p.y * 0.011, 3, seed &+ 5) - 0.5) * 2 * wob
            var ink: Int? = nil
            for op in ops.reversed() {
                if let hit = invert(&p, op) { ink = hit; break }
            }
            var c: RGB
            if let ink {
                c = palette.inks[ink]
            } else {
                let bandH = 34.0
                let breathe = (valueNoise(p.y * 0.02, 3.7, seed &+ 21) - 0.5) * 8
                let idx = Int(((p.y + breathe) / bandH).rounded(.down))
                let cycle = [0, 1, 2, 3, 2, 1]
                c = palette.inks[cycle[((idx % cycle.count) + cycle.count) % cycle.count]]
            }
            if veins {
                let vx = Double(px) * 0.016, vy = Double(py) * 0.016
                let ridge = 1 - abs(2 * fbm(vx, vy, 4, seed &+ 11) - 1)
                if ridge > 0.965 {
                    let t = (0.55 + 0.35 * (ridge - 0.965) / 0.035) * veinStrength
                    c = mix(c, palette.gilt, t)
                }
            }
            if wash > 0 { c = mix(c, palette.paper, wash) }
            let i = (py * w + px) * 4
            pixels[i] = UInt8(clamping: Int(c.0 * 255))
            pixels[i + 1] = UInt8(clamping: Int(c.1 * 255))
            pixels[i + 2] = UInt8(clamping: Int(c.2 * 255))
            pixels[i + 3] = 255
        }
    }
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)!
}

// MARK: - JPEG output (marble compresses ~8x better as JPEG than PNG)

func saveJPEG(_ image: CGImage, _ path: String, quality: Double = 0.82) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.jpeg.identifier as CFString, 1, nil)!
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(dest, image, options)
    CGImageDestinationFinalize(dest)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int ?? 0
    print("wrote \(path) (\(bytes / 1024)KB)")
}

// MARK: - Main

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assets = repoRoot.appendingPathComponent("site/assets")
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// Hero panels — present enough to read as marbling, washed enough for type.
saveJPEG(marbleSheet(palette: forestMarble, pattern: "bouquet", seed: 23,
                     w: 1440, h: 900, unitsPerPixel: 1.2, veins: true,
                     veinStrength: 0.5, wash: 0.42),
         assets.appendingPathComponent("marble-hero-light.jpg").path, quality: 0.78)
saveJPEG(marbleSheet(palette: espressoMarble, pattern: "bouquet", seed: 29,
                     w: 1440, h: 900, unitsPerPixel: 1.2, veins: true,
                     veinStrength: 0.55, wash: 0.30),
         assets.appendingPathComponent("marble-hero-dark.jpg").path, quality: 0.78)

// Endpaper backdrops — faded far toward the canvas, like the app's launch
// endpaper and detail-view underlay.
saveJPEG(marbleSheet(palette: forestMarble, pattern: "bouquet", seed: 11,
                     w: 1400, h: 900, unitsPerPixel: 1.3, veins: false, wash: 0.80),
         assets.appendingPathComponent("endpaper-light.jpg").path, quality: 0.78)
saveJPEG(marbleSheet(palette: espressoMarble, pattern: "bouquet", seed: 11,
                     w: 1400, h: 900, unitsPerPixel: 1.3, veins: false, wash: 0.82),
         assets.appendingPathComponent("endpaper-dark.jpg").path, quality: 0.78)
print("done")
