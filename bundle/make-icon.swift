import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generatore dell'icona di Relay (Core Graphics puro, headless: nessuna NSApplication). Concept
// "prompt classico": chevron `>` accento + cursore a blocco su squircle scuro (palette Relay Dark).
// Uso: `swift bundle/make-icon.swift <output.png>` (default: AppIcon-1024.png). Il Makefile
// (`make icon`) genera poi le varie dimensioni e l'`.icns`.

let side = 1024
let space = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("impossibile creare il contesto grafico")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a]) ?? CGColor(gray: 0, alpha: 1)
}

let canvas = CGFloat(side)

// Squircle di sfondo (margine ~ linee guida macOS), riempito con un gradiente verticale scuro.
let inset: CGFloat = 86
let bounds = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let squircle = CGPath(roundedRect: bounds, cornerWidth: 188, cornerHeight: 188, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let top = rgb(0.196, 0.220, 0.267) // #323844
let bottom = rgb(0.129, 0.145, 0.169) // #21252B
guard let gradient = CGGradient(
    colorsSpace: space,
    colors: [top, bottom] as CFArray,
    locations: [0, 1]
) else {
    fatalError("impossibile creare il gradiente")
}

ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: canvas),
    end: CGPoint(x: 0, y: 0),
    options: []
)
ctx.restoreGState()

// Highlight sottile sul bordo, per staccare lo squircle dallo sfondo del Dock.
ctx.saveGState()
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(1, 1, 1, 0.06))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// Chevron ">" del prompt (accento blu), ~80% dell'altezza del cursore (bracci 380..620 vs
// 300..700):
// il cursore resta l'elemento dominante, il chevron lo accompagna con un gap ampio.
ctx.saveGState()
ctx.setStrokeColor(rgb(0.380, 0.686, 0.937)) // #61AFEF
ctx.setLineWidth(80)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
// Vertice al centro ottico (500); bracci raccolti verso il centro.
ctx.move(to: CGPoint(x: 348, y: 620))
ctx.addLine(to: CGPoint(x: 481, y: 500))
ctx.addLine(to: CGPoint(x: 348, y: 380))
ctx.strokePath()
ctx.restoreGState()

// Cursore a blocco (crema, come il foreground), staccato dal chevron con un gap netto.
ctx.saveGState()
ctx.setFillColor(rgb(0.851, 0.863, 0.886)) // #D9DCE2
let cursor = CGRect(x: 571, y: 300, width: 145, height: 400)
ctx.addPath(CGPath(roundedRect: cursor, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.fillPath()
ctx.restoreGState()

guard let image = ctx.makeImage() else {
    fatalError("impossibile rasterizzare l'immagine")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("impossibile creare il file PNG")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("impossibile scrivere il PNG")
}

print("icona scritta: \(outputPath)")
