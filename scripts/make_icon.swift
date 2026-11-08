import AppKit
let size=1024
let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
let rect=NSRect(x:70,y:70,width:884,height:884)
let outline=NSBezierPath(roundedRect:rect,xRadius:210,yRadius:210)
NSGradient(colors:[NSColor(calibratedRed:0.88,green:0.91,blue:0.84,alpha:1),NSColor(calibratedRed:0.61,green:0.70,blue:0.57,alpha:1)])!.draw(in:outline,angle:-65)
NSColor.white.withAlphaComponent(0.55).setStroke();outline.lineWidth=4;outline.stroke()
let arch=NSBezierPath();arch.move(to:NSPoint(x:260,y:430));arch.curve(to:NSPoint(x:764,y:430),controlPoint1:NSPoint(x:240,y:840),controlPoint2:NSPoint(x:784,y:840));arch.lineWidth=49;arch.lineCapStyle = .round;NSColor(calibratedRed:0.24,green:0.34,blue:0.26,alpha:1).setStroke();arch.stroke()
for x in [232,728] {let pad=NSBezierPath(roundedRect:NSRect(x:x,y:370,width:68,height:170),xRadius:28,yRadius:28);NSColor(calibratedRed:0.25,green:0.35,blue:0.27,alpha:1).setFill();pad.fill()}
let left=NSBezierPath();left.move(to:NSPoint(x:512,y:335));left.line(to:NSPoint(x:337,y:368));left.curve(to:NSPoint(x:337,y:599),controlPoint1:NSPoint(x:330,y:400),controlPoint2:NSPoint(x:337,y:550));left.curve(to:NSPoint(x:512,y:555),controlPoint1:NSPoint(x:402,y:611),controlPoint2:NSPoint(x:476,y:583));left.close()
NSColor(calibratedRed:0.97,green:0.94,blue:0.84,alpha:1).setFill();left.fill()
let right=NSBezierPath();right.move(to:NSPoint(x:512,y:335));right.line(to:NSPoint(x:687,y:368));right.line(to:NSPoint(x:687,y:599));right.curve(to:NSPoint(x:512,y:555),controlPoint1:NSPoint(x:622,y:611),controlPoint2:NSPoint(x:548,y:583));right.close();NSColor(calibratedRed:1,green:0.98,blue:0.90,alpha:1).setFill();right.fill()
let spine=NSBezierPath();spine.move(to:NSPoint(x:512,y:342));spine.line(to:NSPoint(x:512,y:552));spine.lineWidth=6;NSColor(calibratedRed:0.62,green:0.64,blue:0.48,alpha:0.6).setStroke();spine.stroke()
let ribbon=NSBezierPath();ribbon.move(to:NSPoint(x:606,y:590));ribbon.line(to:NSPoint(x:606,y:490));ribbon.line(to:NSPoint(x:630,y:511));ribbon.line(to:NSPoint(x:653,y:499));ribbon.line(to:NSPoint(x:653,y:598));ribbon.close();NSColor(calibratedRed:0.65,green:0.33,blue:0.20,alpha:1).setFill();ribbon.fill()
image.unlockFocus();let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!;try! data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
