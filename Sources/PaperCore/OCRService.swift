// SPDX-License-Identifier: MIT
import PDFKit
import Vision

public struct OCRLine {
    public let page: Int
    public let bounds: CGRect
    public let text: String
}
public enum OCRService {
    /// Uses a private PDFKit snapshot, never the live viewer's document.
    public static func recognize(data: Data, pages: [Int]) throws -> [OCRLine] {
        guard let document = PDFDocument(data: data) else { throw PDFError("Could not open the OCR snapshot.") }
        var result: [OCRLine] = []
        for index in pages {
            guard let page = document.page(at: index) else { continue }
            if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let crop = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let size = CGSize(width: rotated ? crop.height : crop.width, height: rotated ? crop.width : crop.height)
            let image = page.thumbnail(of: CGSize(width:size.width*2,height:size.height*2), for: .cropBox)
            var proposed = CGRect(origin:.zero,size:image.size)
            guard let cg = image.cgImage(forProposedRect:&proposed,context:nil,hints:nil) else { throw PDFError("Could not render page \(index+1) for OCR.") }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage:cg).perform([request])
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let b = observation.boundingBox
                result.append(OCRLine(page:index,bounds:CGRect(x:b.minX*size.width,y:(1-b.maxY)*size.height,width:b.width*size.width,height:b.height*size.height),text:candidate.string))
            }
        }
        return result
    }
}
