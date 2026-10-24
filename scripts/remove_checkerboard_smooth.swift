import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: remove_checkerboard_smooth.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Could not load input image.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerRow = width * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Could not create pixel buffer.\n", stderr)
    exit(1)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let rawData = context.data else {
    fputs("Could not access pixel buffer.\n", stderr)
    exit(1)
}

let pixels = rawData.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
let infinity = 1_000_000
var distance = [Int](repeating: infinity, count: width * height)
var foreground = [Bool](repeating: false, count: width * height)

for y in 0..<height {
    for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let neutral = abs(red - green) <= 4 && abs(green - blue) <= 4
        let checkerboard = neutral && red >= 235
        if !checkerboard { foreground[y * width + x] = true }
    }
}

var visited = [Bool](repeating: false, count: width * height)
var largest: [Int] = []
let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
for y in 0..<height {
    for x in 0..<width {
        let start = y * width + x
        if visited[start] || !foreground[start] { continue }
        visited[start] = true
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let cx = current % width
            let cy = current / width
            for (dx, dy) in neighbors {
                let nx = cx + dx
                let ny = cy + dy
                if nx < 0 || nx >= width || ny < 0 || ny >= height { continue }
                let next = ny * width + nx
                if visited[next] || !foreground[next] { continue }
                visited[next] = true
                queue.append(next)
            }
        }
        if queue.count > largest.count { largest = queue }
    }
}
for index in largest { distance[index] = 0 }

func update(_ index: Int, _ neighbor: Int, _ cost: Int) {
    distance[index] = min(distance[index], distance[neighbor] + cost)
}

for y in 0..<height {
    for x in 0..<width {
        let index = y * width + x
        if x > 0 { update(index, index - 1, 3) }
        if y > 0 {
            update(index, index - width, 3)
            if x > 0 { update(index, index - width - 1, 4) }
            if x + 1 < width { update(index, index - width + 1, 4) }
        }
    }
}

for y in stride(from: height - 1, through: 0, by: -1) {
    for x in stride(from: width - 1, through: 0, by: -1) {
        let index = y * width + x
        if x + 1 < width { update(index, index + 1, 3) }
        if y + 1 < height {
            update(index, index + width, 3)
            if x > 0 { update(index, index + width - 1, 4) }
            if x + 1 < width { update(index, index + width + 1, 4) }
        }
    }
}

let opaqueDistance = 27
let clearDistance = 36
for y in 0..<height {
    for x in 0..<width {
        let index = y * width + x
        let offset = y * bytesPerRow + x * 4
        let d = distance[index]
        if d == 0 {
            pixels[offset + 3] = 255
        } else if d <= clearDistance {
            pixels[offset] = 255
            pixels[offset + 1] = 255
            pixels[offset + 2] = 255
            let alpha = d <= opaqueDistance ? 255 : max(0, (clearDistance - d) * 255 / (clearDistance - opaqueDistance))
            pixels[offset + 3] = UInt8(alpha)
        } else {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }
    }
}

guard
    let outputImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    fputs("Could not create output image.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write output image.\n", stderr)
    exit(1)
}

print(outputURL.path)
