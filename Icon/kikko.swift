// Fork: the app's own icon, the dark Kikko of Settings › Custom, drawn by
// the same code the app draws it with. build.sh puts ForkIconArt.swift in
// front of this file and runs the two as one script:
//
//   swift <both> AppIcon.iconset [AppIcon.icon]
//
// The iconset is the plate as the Dock has always shown it. The Icon
// Composer document, for macOS 26's Dock styles, is the same plate filling
// the whole canvas: macOS cuts the corners itself there.

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// `bleed`: the plate (824 of 1024) stretched to the edges of the picture.
func png(pixels: Int, bleed: Bool) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let g = context.cgContext
    var size = CGFloat(pixels)
    if bleed {
        let k: CGFloat = 1024 / 824
        g.translateBy(x: -100 * k * size / 1024, y: -100 * k * size / 1024)
        size *= k
    }
    ForkIconArt.draw(.hexagons, dark: true, in: g, size: size)
    g.flush()
    return rep.representation(using: .png, properties: [:])
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png(pixels: points * scale, bleed: false)?.write(to: out.appendingPathComponent(name))
    }
}
print("drew: \(out.path)")

if CommandLine.arguments.count > 2 {
    let doc = URL(fileURLWithPath: CommandLine.arguments[2])
    let assets = doc.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: doc)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try png(pixels: 1024, bleed: true)?.write(to: assets.appendingPathComponent("kikko.png"))
    // The plate's own colour (0x1F1E1C) under the picture, in every style.
    let ground = #"{ "solid" : "srgb:0.12157,0.11765,0.10980,1.00000" }"#
    let json = """
    {
      "fill" : \(ground),
      "groups" : [
        {
          "layers" : [
            { "name" : "kikko", "image-name" : "kikko.png", "glass" : false }
          ],
          "shadow" : { "kind" : "none", "opacity" : 0.5 },
          "specular" : false,
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
      ],
      "supported-platforms" : { "squares" : [ "macOS" ] }
    }
    """
    try json.write(to: doc.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("wrote: \(doc.path)")
}
