import AppKit
import CoreGraphics
import Foundation
import PDFKit

// PDF to structured folder converter using macOS PDFKit.
// Usage: pdf-to-files <input.pdf>
// Output: <input.pdf>-files/ with content.md and images/

let PAGE_RENDER_DPI: CGFloat = 150

// MARK: - Image helpers

func savePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

func renderPageToCGImage(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
    let mediaBox = page.bounds(for: .mediaBox)
    let scale = dpi / 72.0
    let width = Int(mediaBox.width * scale)
    let height = Int(mediaBox.height * scale)

    guard width > 0, height > 0 else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
    else { return nil }

    // White background
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    ctx.scaleBy(x: scale, y: scale)

    // PDFPage.draw applies its own transforms for rotation/crop
    guard let cgPage = page.pageRef else { return nil }
    let transform = cgPage.getDrawingTransform(.mediaBox, rect: mediaBox, rotate: 0, preserveAspectRatio: true)
    ctx.concatenate(transform)
    ctx.drawPDFPage(cgPage)

    return ctx.makeImage()
}

// MARK: - Embedded image extraction

/// Walk a PDF page's Resources/XObject dictionary to extract embedded raster images.
func extractEmbeddedImages(from page: PDFPage) -> [(CGImage, String)] {
    guard let cgPage = page.pageRef,
        let dict = cgPage.dictionary
    else { return [] }

    var resourcesDict: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(dict, "Resources", &resourcesDict),
        let resources = resourcesDict
    else { return [] }

    var xObjectDict: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjectDict),
        let xObjects = xObjectDict
    else { return [] }

    var images: [(CGImage, String)] = []

    func enumerator(
        key: UnsafePointer<CChar>, obj: CGPDFObjectRef,
        info: UnsafeMutableRawPointer?
    ) -> Bool {
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(obj, .stream, &stream), let stream = stream else { return true }

        var streamDict: CGPDFDictionaryRef?
        streamDict = CGPDFStreamGetDictionary(stream)
        guard let sDict = streamDict else { return true }

        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(sDict, "Subtype", &subtype),
            let st = subtype, String(cString: st) == "Image"
        else { return true }

        var cgWidth: CGPDFInteger = 0
        var cgHeight: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(sDict, "Width", &cgWidth)
        CGPDFDictionaryGetInteger(sDict, "Height", &cgHeight)

        // Skip tiny images (icons, bullets, etc.)
        let minDimension = 32
        guard cgWidth >= minDimension, cgHeight >= minDimension else { return true }

        // Try to create a CGImage from the stream data
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return true }

        let keyName = String(cString: key)

        if let provider = CGDataProvider(data: data),
            let cgImage = CGImage(
                width: Int(cgWidth), height: Int(cgHeight),
                bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: Int(cgWidth) * 3,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
            )
        {
            let imagesPtr = info!.assumingMemoryBound(to: [(CGImage, String)].self)
            imagesPtr.pointee.append((cgImage, keyName))
        }

        return true
    }

    withUnsafeMutablePointer(to: &images) { ptr in
        CGPDFDictionaryApplyBlock(xObjects, enumerator, ptr)
    }

    return images
}

// MARK: - Text to basic markdown

/// Attempt basic markdown formatting from extracted text.
/// PDFKit gives us plain text; we clean it up and add structure.
func textToMarkdown(_ text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    var result: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // Collapse multiple blank lines
            if result.last != "" {
                result.append("")
            }
        } else {
            result.append(trimmed)
        }
    }

    return result.joined(separator: "\n")
}

// MARK: - Main

func convert(inputPath: String) -> Int32 {
    let outputDir = inputPath + "-files"
    let imagesDir = (outputDir as NSString).appendingPathComponent("images")
    let fm = FileManager.default

    // Idempotency
    if fm.fileExists(atPath: outputDir) {
        fputs("Output already exists: \(outputDir)\n", stderr)
        return 1
    }

    // Validate input
    guard fm.isReadableFile(atPath: inputPath) else {
        fputs("File not found or not readable: \(inputPath)\n", stderr)
        return 1
    }

    let inputURL = URL(fileURLWithPath: inputPath)
    guard let doc = PDFDocument(url: inputURL) else {
        fputs("Failed to open PDF: \(inputPath)\n", stderr)
        return 1
    }

    let pageCount = doc.pageCount
    if pageCount == 0 {
        fputs("PDF has no pages: \(inputPath)\n", stderr)
        return 1
    }

    // Create output dirs
    do {
        try fm.createDirectory(atPath: imagesDir, withIntermediateDirectories: true)
    } catch {
        fputs("Failed to create output directory: \(error)\n", stderr)
        // Clean up partial output
        try? fm.removeItem(atPath: outputDir)
        return 1
    }

    let baseName = inputURL.deletingPathExtension().lastPathComponent
    var markdown = "# \(baseName)\n\n"
    var totalImages = 0

    for pageIdx in 0..<pageCount {
        guard let page = doc.page(at: pageIdx) else { continue }
        let pageNum = pageIdx + 1

        if pageCount > 1 {
            markdown += "## Page \(pageNum)\n\n"
        }

        // Render full page as PNG (captures tables, charts, vectors — everything visual)
        if let cgImage = renderPageToCGImage(page, dpi: PAGE_RENDER_DPI) {
            let imageName = "\(baseName)-page\(pageNum).png"
            let imagePath = (imagesDir as NSString).appendingPathComponent(imageName)
            if savePNG(cgImage, to: imagePath) {
                markdown += "![Page \(pageNum)](images/\(imageName))\n\n"
                totalImages += 1
            }
        }

        // Extract and save embedded raster images
        let embedded = extractEmbeddedImages(from: page)
        for (imgIdx, (cgImage, _)) in embedded.enumerated() {
            let imageName = "\(baseName)-page\(pageNum)-img\(imgIdx + 1).png"
            let imagePath = (imagesDir as NSString).appendingPathComponent(imageName)
            if savePNG(cgImage, to: imagePath) {
                markdown += "![Embedded image \(imgIdx + 1)](images/\(imageName))\n\n"
                totalImages += 1
            }
        }

        // Extract text
        let rawText = page.string ?? ""
        let cleaned = textToMarkdown(rawText)
        if !cleaned.isEmpty {
            markdown += cleaned + "\n\n"
        }

        if pageIdx < pageCount - 1 {
            markdown += "---\n\n"
        }
    }

    // Write content.md
    let mdPath = (outputDir as NSString).appendingPathComponent("content.md")
    do {
        try markdown.write(toFile: mdPath, atomically: true, encoding: .utf8)
    } catch {
        fputs("Failed to write markdown: \(error)\n", stderr)
        try? fm.removeItem(atPath: outputDir)
        return 1
    }

    print("Converted \(pageCount) page(s), \(totalImages) image(s) to \(outputDir)")
    return 0
}

// Entry point
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: pdf-to-files <pdf-file>\n", stderr)
    exit(1)
}

exit(convert(inputPath: CommandLine.arguments[1]))
