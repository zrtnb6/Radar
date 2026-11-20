import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create icon context")
}

let canvas = CGRect(x: 62, y: 62, width: 900, height: 900)
let background = CGPath(roundedRect: canvas, cornerWidth: 205, cornerHeight: 205, transform: nil)
context.saveGState()
context.addPath(background)
context.clip()
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// 单色深蓝底，只在顶部压一层极淡高光，保留体积感但不做花哨渐变
context.setFillColor(CGColor(red: 0.075, green: 0.345, blue: 0.665, alpha: 1))
context.fill(canvas)
let sheen = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.11),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 962), end: CGPoint(x: 512, y: 480), options: [])

let center = CGPoint(x: 512, y: 512)
context.setLineCap(.round)

// 两道同心扫描弧：外弧实、内弧淡，缺口统一留在左上
for (index, radius) in [250.0, 142.0].enumerated() {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: index == 0 ? 0.96 : 0.72))
    context.setLineWidth(62)
    context.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    context.strokePath()
}

// 中心命中点
context.setFillColor(CGColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1))
context.fillEllipse(in: CGRect(x: center.x - 68, y: center.y - 68, width: 136, height: 136))
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("Unable to create icon image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to write icon")
}
