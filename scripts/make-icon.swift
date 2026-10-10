import AppKit
func moon(_ rect: NSRect, color: NSColor) {
    let image = NSImage(systemSymbolName:"moon.fill",accessibilityDescription:nil)!.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[color]))!
    image.draw(in:rect)
}
func render(pixels: Int, menu: Bool) -> Data {
    let unit:CGFloat = menu ? 20 : 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    rep.size = NSSize(width:unit,height:unit)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
    NSColor.clear.setFill();NSRect(x:0,y:0,width:unit,height:unit).fill()
    if menu {
        NSColor.black.setStroke()
        let window=NSBezierPath(roundedRect:NSRect(x:1.5,y:3,width:17,height:14),xRadius:3,yRadius:3)
        window.lineWidth=1.6;window.stroke()
        let bar=NSBezierPath();bar.move(to:NSPoint(x:2,y:12.7));bar.line(to:NSPoint(x:18,y:12.7));bar.lineWidth=1.3;bar.stroke()
        moon(NSRect(x:7.7,y:4.4,width:8.5,height:7.3),color:.black)
    } else {
        let tile=NSBezierPath(roundedRect:NSRect(x:80,y:80,width:864,height:864),xRadius:194,yRadius:194)
        NSGradient(starting:NSColor(calibratedRed:0.13,green:0.22,blue:0.35,alpha:1),ending:NSColor(calibratedRed:0.035,green:0.075,blue:0.15,alpha:1))!.draw(in:tile,angle:-70)
        let rim=NSBezierPath(roundedRect:NSRect(x:83,y:83,width:858,height:858),xRadius:191,yRadius:191)
        NSColor.white.withAlphaComponent(0.12).setStroke();rim.lineWidth=3;rim.stroke()
        let window=NSBezierPath(roundedRect:NSRect(x:225,y:283,width:574,height:478),xRadius:68,yRadius:68)
        let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.24);shadow.shadowBlurRadius=36;shadow.shadowOffset=NSSize(width:0,height:-20)
        NSGraphicsContext.saveGraphicsState();shadow.set()
        NSColor(calibratedRed:0.18,green:0.31,blue:0.43,alpha:1).setFill();window.fill();NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting:NSColor(calibratedRed:0.31,green:0.45,blue:0.55,alpha:1),ending:NSColor(calibratedRed:0.10,green:0.18,blue:0.29,alpha:1))!.draw(in:window,angle:-80)
        NSColor(calibratedRed:0.69,green:0.90,blue:0.92,alpha:0.8).setStroke();window.lineWidth=12;window.stroke()
        let bar=NSBezierPath();bar.move(to:NSPoint(x:231,y:657));bar.line(to:NSPoint(x:793,y:657));bar.lineWidth=9
        NSColor(calibratedRed:0.69,green:0.90,blue:0.92,alpha:0.45).setStroke();bar.stroke()
        for (i,alpha) in [0.95,0.65,0.4].enumerated() {
            NSColor(calibratedRed:0.69,green:0.94,blue:0.87,alpha:alpha).setFill()
            NSBezierPath(ovalIn:NSRect(x:272+CGFloat(i)*43,y:694,width:18,height:18)).fill()
        }
        moon(NSRect(x:420,y:341,width:296,height:272),color:NSColor(calibratedRed:0.62,green:0.96,blue:0.84,alpha:1))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
for (name,pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    try render(pixels:pixels,menu:false).write(to:URL(fileURLWithPath:"build/PolishedHelper.iconset/\(name).png"))
}
try render(pixels:40,menu:true).write(to:URL(fileURLWithPath:"build/StatusMoon.png"))
