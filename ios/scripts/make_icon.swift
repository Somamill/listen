import AppKit
// Native, opaque iOS variant of the existing half-filled listen. mark.
let size = 1024
let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
let cream = CGColor(red:250/255,green:248/255,blue:244/255,alpha:1)
let sage = CGColor(red:66/255,green:104/255,blue:75/255,alpha:1)
context.setFillColor(cream);context.fill(CGRect(x:0,y:0,width:size,height:size))
let circle=CGRect(x:242,y:242,width:540,height:540)
context.saveGState();context.clip(to:CGRect(x:0,y:0,width:1024,height:512));context.setFillColor(sage);context.fillEllipse(in:circle);context.restoreGState()
context.setStrokeColor(sage);context.setLineWidth(32);context.strokeEllipse(in:circle)
let bitmap=NSBitmapImageRep(cgImage:context.makeImage()!)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
