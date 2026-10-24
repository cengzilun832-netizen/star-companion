import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: keep_largest_alpha_component.swift input.png output.png\n", stderr)
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
var visited = [Bool](repeating: false, count: width * height)
var largest: [Int] = []
let neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]

for y in 0..<height {
    for x in 0..<width {
        let start = y * width + x
        if visited[start] || pixels[y * bytesPerRow + x * 4 + 3] == 0 { continue }

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
                if visited[next] || pixels[ny * bytesPerRow + nx * 4 + 3] == 0 { continue }
                visited[next] = true
                queue.append(next)
            }
        }
        if queue.count > largest.count { largest = queue }
    }
}

var keep = [Bool](repeating: false, count: width * height)
for index in largest { keep[index] = true }
for y in 0..<height {
    for x in 0..<width where !keep[y * width + x] {
        let offset = y * bytesPerRow + x * 4
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
    }
}

guard
    let outputImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
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
