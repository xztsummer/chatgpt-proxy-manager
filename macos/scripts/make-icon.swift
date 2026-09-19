import AppKit
import CoreGraphics

// 生成应用图标：靛蓝渐变圆角方块 + 白色圆环对勾（呼应参考项目图标）
let size = 1024
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("无法创建画布")
}

let rounded = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                     cornerWidth: 232, cornerHeight: 232, transform: nil)
ctx.addPath(rounded)
ctx.clip()

let colors = [CGColor(srgbRed: 0.45, green: 0.47, blue: 0.99, alpha: 1),
              CGColor(srgbRed: 0.32, green: 0.33, blue: 0.92, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: CGFloat(size)),
                       end: CGPoint(x: 0, y: 0), options: [])

// 白色圆环
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(62)
let center: CGFloat = 512
let radius: CGFloat = 208
ctx.addEllipse(in: CGRect(x: center - radius, y: center - radius, width: radius * 2, height: radius * 2))
ctx.strokePath()

// 白色对勾
ctx.setLineWidth(74)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: center - 96, y: center + 12))
ctx.addLine(to: CGPoint(x: center - 24, y: center - 64))
ctx.addLine(to: CGPoint(x: center + 110, y: center + 78))
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("无法生成图像") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("无法编码 PNG") }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try png.write(to: URL(fileURLWithPath: out))
print("图标已生成：\(out)")
