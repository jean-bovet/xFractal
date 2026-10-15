// Pixel jobs for scripts/preview-gallery.py, read from stdin as one JSON array per line (paths may hold spaces;
// coordinates in pixels), one answer per line:
//
//   ["decode", FILE]             -> "width height" after decoding every pixel (a truncated PNG answers -1)
//   ["share", LIGHT, DARK, X, Y, W, H, DELTA] -> the share of the region's pixels where LIGHT is brighter than DARK by more than DELTA
//   ["stats", FILE, X, Y, W, H]  -> "mean std share>=0.85 share<=0.20" of the region's luminance (0...1)
//   ["diff", LIGHT, DARK, X, Y, W, H] -> "found bx by bw bh lightMean darkMean blobArea components outsideShare": the
//                                   largest connected blob (8-neighbour) of pixels where the two images differ by more
//                                   than 0.04, its bounding box and the mean luminance of each image inside it, the
//                                   number of blobs of 30 pixels or more, and the share of the region outside the
//                                   box that differs
//
// "-1" answers a job whose image cannot be decoded or whose region is not inside it.
import CoreGraphics
import Foundation
import ImageIO

struct Gray { var width: Int; var height: Int; var values: [Double] }

func load(_ path: String) -> Gray? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          CGImageSourceGetStatus(source) == .statusComplete,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var values = [Double](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
        values[i] = (0.299 * Double(pixels[i * 4]) + 0.587 * Double(pixels[i * 4 + 1]) + 0.114 * Double(pixels[i * 4 + 2])) / 255
    }
    return Gray(width: width, height: height, values: values)
}

func region(_ g: Gray, _ f: [Int]) -> (x: Int, y: Int, w: Int, h: Int)? {
    let (x, y, w, h) = (f[0], f[1], f[2], f[3])
    guard w > 0, h > 0, x >= 0, y >= 0, x + w <= g.width, y + h <= g.height else { return nil }
    return (x, y, w, h)
}

func stats(_ path: String, _ f: [Int]) -> String {
    guard let g = load(path), let r = region(g, f) else { return "-1" }
    var sum = 0.0, sumSq = 0.0, ge = 0, le = 0
    for yy in r.y..<(r.y + r.h) {
        for xx in r.x..<(r.x + r.w) {
            let v = g.values[yy * g.width + xx]
            sum += v; sumSq += v * v
            if v >= 0.85 { ge += 1 }
            if v <= 0.20 { le += 1 }
        }
    }
    let n = Double(r.w * r.h)
    let mean = sum / n
    let std = max(sumSq / n - mean * mean, 0).squareRoot()
    return String(format: "%.5f %.5f %.5f %.5f", mean, std, Double(ge) / n, Double(le) / n)
}

func diff(_ lightPath: String, _ darkPath: String, _ f: [Int]) -> String {
    guard let a = load(lightPath), let b = load(darkPath), a.width == b.width, a.height == b.height,
          let r = region(a, f) else { return "-1" }
    let w = r.w, h = r.h
    var mask = [Bool](repeating: false, count: w * h)
    for yy in 0..<h {
        for xx in 0..<w {
            let i = (r.y + yy) * a.width + (r.x + xx)
            mask[yy * w + xx] = abs(a.values[i] - b.values[i]) > 0.04
        }
    }
    var label = [Int](repeating: -1, count: w * h)
    var best: (area: Int, minX: Int, minY: Int, maxX: Int, maxY: Int) = (0, 0, 0, 0, 0)
    var components = 0
    var stack: [Int] = []
    for start in 0..<(w * h) where mask[start] && label[start] < 0 {
        var area = 0, minX = w, minY = h, maxX = 0, maxY = 0
        label[start] = start
        stack.append(start)
        while let p = stack.popLast() {
            let px = p % w, py = p / w
            area += 1
            minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = px + dx, ny = py + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let q = ny * w + nx
                    if mask[q], label[q] < 0 { label[q] = start; stack.append(q) }
                }
            }
        }
        if area >= 30 { components += 1 }
        if area > best.area { best = (area, minX, minY, maxX, maxY) }
    }
    guard best.area > 0 else { return "0 0 0 0 0 0 0 0 \(components) 0" }
    let bw = best.maxX - best.minX + 1, bh = best.maxY - best.minY + 1
    var lightSum = 0.0, darkSum = 0.0, outside = 0, outsideDiff = 0
    for yy in 0..<h {
        for xx in 0..<w {
            let inside = xx >= best.minX && xx <= best.maxX && yy >= best.minY && yy <= best.maxY
            if inside {
                let i = (r.y + yy) * a.width + (r.x + xx)
                lightSum += a.values[i]; darkSum += b.values[i]
            } else {
                outside += 1
                if mask[yy * w + xx] { outsideDiff += 1 }
            }
        }
    }
    let n = Double(bw * bh)
    let share = outside > 0 ? Double(outsideDiff) / Double(outside) : 0
    return String(format: "1 %d %d %d %d %.5f %.5f %d %d %.6f", r.x + best.minX, r.y + best.minY, bw, bh,
                  lightSum / n, darkSum / n, best.area, components, share)
}

func decode(_ path: String) -> String {
    guard let g = load(path) else { return "-1" }
    return "\(g.width) \(g.height)"
}

func share(_ lightPath: String, _ darkPath: String, _ f: [Int], _ delta: Double) -> String {
    guard let a = load(lightPath), let b = load(darkPath), a.width == b.width, a.height == b.height,
          let r = region(a, f) else { return "-1" }
    var count = 0
    for yy in r.y..<(r.y + r.h) {
        for xx in r.x..<(r.x + r.w) {
            let i = yy * a.width + xx
            if a.values[i] - b.values[i] > delta { count += 1 }
        }
    }
    return String(format: "%.5f", Double(count) / Double(r.w * r.h))
}

while let line = readLine() {
    guard let data = line.data(using: .utf8), let job = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
          let mode = job.first as? String else { print("-1"); continue }
    func str(_ i: Int) -> String? { i < job.count ? job[i] as? String : nil }
    func ints(_ from: Int, _ n: Int) -> [Int]? {
        let v = job.dropFirst(from).prefix(n).compactMap { ($0 as? NSNumber)?.intValue }
        return v.count == n ? v : nil
    }
    switch mode {
    case "decode":
        print(str(1).map(decode) ?? "-1")
    case "stats":
        if let f = str(1), let r = ints(2, 4) { print(stats(f, r)) } else { print("-1") }
    case "diff":
        if let l = str(1), let d = str(2), let r = ints(3, 4) { print(diff(l, d, r)) } else { print("-1") }
    case "share":
        if let l = str(1), let d = str(2), let r = ints(3, 4), job.count > 7, let delta = (job[7] as? NSNumber)?.doubleValue {
            print(share(l, d, r, delta))
        } else { print("-1") }
    default:
        print("-1")
    }
}
