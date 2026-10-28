// SPDX-License-Identifier: MIT
import PDFKit

/// PDFKit uses unrotated PDF coordinates; MuPDF uses a rotated, top-left crop box.
public struct PageGeometry {
    private let box: CGRect
    private let rotation: Int
    public init(page: PDFPage) {
        box = page.bounds(for: .cropBox)
        rotation = (page.rotation % 360 + 360) % 360
    }
    public func enginePoint(_ point: CGPoint) -> CGPoint {
        let x = point.x - box.minX, y = point.y - box.minY
        switch rotation {
        case 90: return CGPoint(x: y, y: x)
        case 180: return CGPoint(x: box.width-x, y: y)
        case 270: return CGPoint(x: box.height-y, y: box.width-x)
        default: return CGPoint(x: x, y: box.height-y)
        }
    }
    public func pdfPoint(_ point: CGPoint) -> CGPoint {
        let p: CGPoint
        switch rotation {
        case 90: p = CGPoint(x: point.y, y: point.x)
        case 180: p = CGPoint(x: box.width-point.x, y: point.y)
        case 270: p = CGPoint(x: box.width-point.y, y: box.height-point.x)
        default: p = CGPoint(x: point.x, y: box.height-point.y)
        }
        return CGPoint(x: p.x+box.minX, y: p.y+box.minY)
    }
    public func engineRect(_ r: CGRect) -> CGRect { transform(r, enginePoint) }
    public func pdfRect(_ r: CGRect) -> CGRect { transform(r, pdfPoint) }
    private func transform(_ r: CGRect, _ f: (CGPoint) -> CGPoint) -> CGRect {
        let p = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.maxY)].map(f)
        let xs = p.map(\.x), ys = p.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
}
