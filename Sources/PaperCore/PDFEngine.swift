// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics
import CPDFEngine

public struct PDFError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct TextLine {
    public let index: Int
    public let bounds: CGRect
    public let text: String
    public let font: String
    public let size: CGFloat
    public let color: UInt32
    public let editable: Bool
}
public struct PDFImage {
    public let index: Int
    public let bounds: CGRect
    public let editable: Bool
}
public struct PDFRevision {
    public let number: UInt64
    public let data: Data
}
public struct PDFChange {
    public let before: Data
    public let after: PDFRevision
}
public final class PDFEngine {
    private let handle: OpaquePointer
    public init(data: Data, password: String = "") throws {
        var error = [CChar](repeating: 0, count: 1024)
        let result = data.withUnsafeBytes { raw in
            pe_open(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, password, &error, error.count)
        }
        guard let result else { throw PDFError(String(cString: error)) }
        handle = result
    }
    public init() throws {
        var error = [CChar](repeating: 0, count: 1024)
        guard let result = pe_blank(&error, error.count) else { throw PDFError(String(cString: error)) }
        handle = result
    }
    deinit { pe_close(handle) }
    private func check(_ result: Int32) throws {
        guard result != 0 else { throw PDFError(String(cString: pe_error(handle))) }
    }
    private func bytes(_ action: (UnsafeMutablePointer<PEBytes>) -> Int32) throws -> Data {
        var result = PEBytes()
        defer { pe_free(result.data) }
        try check(action(&result))
        guard let data = result.data else { throw PDFError("The PDF engine returned no data.") }
        return Data(bytes: data, count: result.count)
    }
    public var pageCount: Int { Int(pe_page_count(handle)) }
    public var canModify: Bool { pe_can_modify(handle) != 0 }
    public var isSigned: Bool { pe_is_signed(handle) != 0 }
    public func snapshot() throws -> Data { try bytes { pe_snapshot(handle, $0) } }
    public func export(password: String = "", flatten: Bool = false, compress: Bool = false) throws -> Data {
        try bytes { pe_export(handle, password, flatten ? 1 : 0, compress ? 1 : 0, $0) }
    }
    public func lines(page: Int) throws -> [TextLine] {
        var result = PELines()
        defer { pe_free(result.items) }
        try check(pe_lines(handle, Int32(page), &result))
        let count: Int = Int(result.count)
        var lines: [TextLine] = []
        for i in 0..<count {
            var item = result.items![i]
            let text = String(cString: pe_line_text(&item))
            let font = String(cString: pe_line_font(&item))
            lines.append(TextLine(index: i, bounds: item.bounds.cgRect, text: text, font: font, size: CGFloat(item.size), color: item.color, editable: item.editable != 0))
        }
        return lines
    }
    public func replaceLine(page: Int, index: Int, text: String, font: String = "", size: CGFloat, color: UInt32) throws {
        try check(pe_replace_line(handle, Int32(page), Int32(index), text, font, Float(size), color))
    }
    public func annotate(page: Int, kind: String, bounds: CGRect, quads: [CGRect] = [], contents: String = "", color: UInt32 = 0xffd60a, size: CGFloat = 14, points: [CGPoint] = []) throws {
        let q = quads.map(PEriangle), p = points.map { PEPoint(x: Float($0.x), y: Float($0.y)) }
        try q.withUnsafeBufferPointer { qs in try p.withUnsafeBufferPointer { ps in
            try check(pe_annotate(handle, Int32(page), kind, PEriangle(bounds), qs.baseAddress, Int32(q.count), contents, color, Float(size), ps.baseAddress, Int32(p.count)))
        } }
    }
    public func annotation(page: Int, index: Int, contents: String = "", remove: Bool = false) throws {
        try check(pe_annotation_contents(handle, Int32(page), Int32(index), contents, remove ? 1 : 0))
    }
    public func transformAnnotation(page: Int, index: Int, bounds: CGRect) throws {
        try check(pe_annotation_rect(handle, Int32(page), Int32(index), PEriangle(bounds)))
    }
    public func rotate(page: Int, degrees: Int = 90) throws { try check(pe_rotate(handle, Int32(page), Int32(degrees))) }
    public func crop(page: Int, bounds: CGRect) throws { try check(pe_crop(handle, Int32(page), PEriangle(bounds))) }
    public func reorder(_ pages: [Int]) throws {
        let values = pages.map(Int32.init)
        try values.withUnsafeBufferPointer { try check(pe_reorder(handle, $0.baseAddress, Int32(values.count))) }
    }
    public func insert(data: Data, at: Int) throws {
        try data.withUnsafeBytes { try check(pe_insert_pdf(handle, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, Int32(at))) }
    }
    public func duplicate(pages: [Int]) throws {
        for page in Set(pages).sorted().reversed() {
            let copy = try extract(pages:[page])
            try insert(data:copy,at:page+1)
        }
    }
    public func insertBlank(at: Int) throws { try check(pe_insert_blank(handle, Int32(at))) }
    public func images(page: Int) throws -> [PDFImage] {
        var result = PEImages()
        defer { pe_free(result.items) }
        try check(pe_images(handle, Int32(page), &result))
        return (0..<Int(result.count)).map { i in
            let item = result.items![i]
            return PDFImage(index:i, bounds:item.bounds.cgRect, editable:item.editable != 0)
        }
    }
    public func editImage(page: Int, index: Int, bounds: CGRect, replacement: Data? = nil, remove: Bool = false) throws {
        try (replacement ?? Data()).withUnsafeBytes {
            try check(pe_edit_image(handle, Int32(page), Int32(index), PEriangle(bounds), $0.bindMemory(to:UInt8.self).baseAddress, $0.count, remove ? 1 : 0))
        }
    }
    public func editLink(page: Int, index: Int, bounds: CGRect, uri: String, remove: Bool = false) throws {
        try check(pe_edit_link(handle, Int32(page), Int32(index), PEriangle(bounds), uri, remove ? 1 : 0))
    }
    public func image(page: Int, bounds: CGRect, data: Data) throws {
        try data.withUnsafeBytes { try check(pe_image(handle, Int32(page), PEriangle(bounds), $0.bindMemory(to: UInt8.self).baseAddress, $0.count)) }
    }
    public func redact(page: Int, bounds: CGRect) throws { try check(pe_redact(handle, Int32(page), PEriangle(bounds))) }
    public func form(page: Int, index: Int, value: String) throws { try check(pe_form(handle, Int32(page), Int32(index), value)) }
    public func link(page: Int, bounds: CGRect, uri: String) throws { try check(pe_link(handle, Int32(page), PEriangle(bounds), uri)) }
    public func bookmark(page: Int, title: String = "", removeIndex: Int = -1) throws { try check(pe_bookmark(handle, Int32(page), title, Int32(removeIndex))) }
    public func ocr(page: Int, bounds: CGRect, text: String) throws { try check(pe_ocr_text(handle, Int32(page), PEriangle(bounds), text)) }
    public func extract(pages: [Int]) throws -> Data {
        let values = pages.map(Int32.init)
        return try values.withUnsafeBufferPointer { p in try bytes { pe_extract(handle, p.baseAddress, Int32(values.count), $0) } }
    }
}
private func PEriangle(_ r: CGRect) -> PERect { PERect(x0: Float(r.minX), y0: Float(r.minY), x1: Float(r.maxX), y1: Float(r.maxY)) }
private extension PERect {
    var cgRect: CGRect { CGRect(x: CGFloat(x0), y: CGFloat(y0), width: CGFloat(x1-x0), height: CGFloat(y1-y0)) }
}

/// The engine and its contexts never escape this queue. A mutation is committed only
/// after a complete candidate PDF can be reopened by the engine.
public final class DocumentStore {
    private let queue = DispatchQueue(label: "org.paperpdf.engine", qos: .userInitiated)
    private var engine: PDFEngine
    private var revision: UInt64 = 0
    public let originallySigned: Bool
    public let permitsEditing: Bool
    public init(data: Data? = nil, password: String = "") throws {
        let opened = try data.map { try PDFEngine(data: $0, password: password) } ?? PDFEngine()
        engine = opened
        originallySigned = opened.isSigned
        permitsEditing = opened.canModify
    }
    public func read<T>(_ action: (PDFEngine) throws -> T) rethrows -> T { try queue.sync { try action(engine) } }
    public var currentRevision: UInt64 { queue.sync { revision } }
    public func snapshot() throws -> PDFRevision { try queue.sync { PDFRevision(number: revision, data: try engine.snapshot()) } }
    public func transact(expectedRevision: UInt64? = nil, _ action: (PDFEngine) throws -> Void) throws -> PDFChange {
        try queue.sync {
            guard permitsEditing else { throw PDFError("This PDF does not permit editing. Open it with the owner password.") }
            if let expectedRevision, expectedRevision != revision { throw PDFError("The document changed while this operation was running. Try again.") }
            let before = try engine.snapshot()
            let candidate = try PDFEngine(data: before)
            try action(candidate)
            let data = try candidate.snapshot()
            let validated = try PDFEngine(data: data)
            engine = validated
            revision &+= 1
            return PDFChange(before: before, after: PDFRevision(number: revision, data: data))
        }
    }
    public func restore(_ data: Data) throws -> PDFRevision {
        try queue.sync {
            let replacement = try PDFEngine(data: data)
            engine = replacement
            revision &+= 1
            return PDFRevision(number: revision, data: data)
        }
    }
}
