// Reads text from an image (optionally a crop) with Apple Vision. usage: ocr <image> [x y w h] (crop in pixels)
import Foundation
import Vision
import CoreGraphics
import ImageIO
let args = CommandLine.arguments
guard args.count >= 2, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      var img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print(""); exit(1) }
if args.count >= 6, let x = Int(args[2]), let y = Int(args[3]), let w = Int(args[4]), let h = Int(args[5]),
   let c = img.cropping(to: CGRect(x: x, y: y, width: w, height: h)) { img = c }
let req = VNRecognizeTextRequest { r, _ in
    let lines = (r.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
    print(lines.joined(separator: "\n"))
}
req.recognitionLevel = .fast
try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
