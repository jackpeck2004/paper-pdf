// SPDX-License-Identifier: MIT
#if !PAPER_NATIVE_TESTS
import XCTest
#endif
import PDFKit
import PaperCore

final class EngineTests: XCTestCase {
    static func fixture(content: String = "", rotation: Int = 0, extra: [String] = [], pageExtra: String = "", catalogExtra: String = "") -> Data {
        let stream = content.isEmpty ? "q 0.8 0.9 1 rg 0 0 600 800 re f Q\nBT /F1 18 Tf 1 0 0 1 50 700 Tm (Original secret) Tj ET\nBT /F1 18 Tf 1 0 0 1 50 650 Tm (Keep this line) Tj ET" : content
        var objects = ["<< /Type /Catalog /Pages 2 0 R \(catalogExtra) >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Rotate \(rotation) /Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> /Contents 4 0 R \(pageExtra) >>", "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length 25 >>\nstream\nff000000ff000000ffffffff>\nendstream"]
        objects += extra
        var data = Data("%PDF-1.7\n".utf8), offsets = [0]
        for (i,obj) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(obj)\nendobj\n".utf8)) }
        let start = data.count
        var xref = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { xref += String(format:"%010d 00000 n \n",offset) }
        xref += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
        data.append(Data(xref.utf8)); return data
    }
    func testTextReplacementRemovesOriginalAndKeepsOtherText() throws {
        let store = try DocumentStore(data:Self.fixture())
        let line = try XCTUnwrap(store.read { try $0.lines(page:0).first })
        let before = try store.snapshot()
        let change = try store.transact { try $0.replaceLine(page:0,index:line.index,text:"Corrected text",size:line.size,color:line.color) }
        let doc = try XCTUnwrap(PDFDocument(data:change.after.data))
        XCTAssertTrue(doc.string?.contains("Corrected text") == true)
        XCTAssertFalse(doc.string?.contains("Original secret") == true)
        XCTAssertTrue(doc.string?.contains("Keep this line") == true)
        XCTAssertEqual(doc.pageCount,1)
        let originalDocument = try XCTUnwrap(PDFDocument(data:before.data))
        defer { withExtendedLifetime(originalDocument) {} }
        let original = try XCTUnwrap(originalDocument.page(at:0))
        let changed = try XCTUnwrap(doc.page(at:0))
        // Blue page background must remain; no white rectangle may cover the correction.
        let a = original.thumbnail(of:CGSize(width:600,height:800),for:.cropBox)
        let b = changed.thumbnail(of:CGSize(width:600,height:800),for:.cropBox)
        let ar = try XCTUnwrap(a.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let br = try XCTUnwrap(b.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        for p in [(45,100),(250,100),(55,85),(20,20)] {
            let ac = try XCTUnwrap(ar.colorAt(x:p.0,y:p.1)?.usingColorSpace(.sRGB))
            let bc = try XCTUnwrap(br.colorAt(x:p.0,y:p.1)?.usingColorSpace(.sRGB))
            XCTAssertEqual(ac.redComponent,bc.redComponent,accuracy:0.02)
            XCTAssertEqual(ac.blueComponent,bc.blueComponent,accuracy:0.02)
        }
    }
    func testFailureIsAtomicAndStaleWorkRejected() throws {
        let store = try DocumentStore(data:Self.fixture())
        let initial = try store.snapshot()
        XCTAssertThrowsError(try store.transact { engine in
            try engine.insertBlank(at:1)
            try engine.replaceLine(page:0,index:0,text:String(repeating:"Too long ",count:100),size:18,color:0)
        })
        XCTAssertEqual(store.read { $0.pageCount },1)
        XCTAssertEqual(try store.snapshot().number,initial.number)
        _ = try store.transact { try $0.rotate(page:0) }
        XCTAssertThrowsError(try store.transact(expectedRevision:initial.number) { try $0.insertBlank(at:1) })
        XCTAssertEqual(store.read { $0.pageCount },1)
    }
    func testAnnotationsRoundTripAndUndoSnapshots() throws {
        let store = try DocumentStore(data:Self.fixture())
        let line = try XCTUnwrap(store.read { try $0.lines(page:0).first })
        let change = try store.transact { e in
            try e.annotate(page:0,kind:"Highlight",bounds:line.bounds,quads:[line.bounds],contents:"Review this")
            try e.annotate(page:0,kind:"FreeText",bounds:CGRect(x:50,y:200,width:180,height:60),contents:"A comment",color:0,size:14)
            try e.annotate(page:0,kind:"Ink",bounds:CGRect(x:10,y:10,width:30,height:30),color:0,points:[CGPoint(x:10,y:10),CGPoint(x:40,y:40)])
        }
        let doc = try XCTUnwrap(PDFDocument(data:change.after.data))
        XCTAssertEqual(doc.page(at:0)?.annotations.count,3)
        XCTAssertTrue(doc.page(at:0)?.annotations.contains { $0.contents == "Review this" } == true)
        _ = try store.restore(change.before)
        XCTAssertEqual(PDFDocument(data:try store.snapshot().data)?.page(at:0)?.annotations.count,0)
        _ = try store.restore(change.after.data)
        XCTAssertEqual(PDFDocument(data:try store.snapshot().data)?.page(at:0)?.annotations.count,3)
        _ = try store.transact { try $0.annotation(page:0,index:0,contents:"Updated") }
        XCTAssertTrue(PDFDocument(data:try store.snapshot().data)?.page(at:0)?.annotations.contains { $0.contents == "Updated" } == true)
    }
    func testFreeTextRendersLettersWithoutColoredRectangle() throws {
        let engine = try PDFEngine(data:Self.fixture())
        try engine.annotate(page:0,kind:"FreeText",bounds:CGRect(x:50,y:250,width:220,height:70),contents:"Visible text",color:0xCC2200,size:18)
        for flatten in [false,true] {
            let doc = try XCTUnwrap(PDFDocument(data:engine.export(flatten:flatten)))
            let page = try XCTUnwrap(doc.page(at:0))
            let image = page.thumbnail(of:CGSize(width:600,height:800),for:.cropBox)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let background = try XCTUnwrap(bitmap.colorAt(x:260,y:310)?.usingColorSpace(.sRGB))
            XCTAssertEqual(background.redComponent,0.8,accuracy:0.03)
            XCTAssertEqual(background.greenComponent,0.9,accuracy:0.03)
            XCTAssertEqual(background.blueComponent,1,accuracy:0.03)
            var redPixels = 0
            for y in 250..<320 { for x in 50..<270 {
                if let c = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB), c.redComponent > 0.5, c.greenComponent < 0.4, c.blueComponent < 0.4 { redPixels += 1 }
            } }
            // Glyphs must paint visible pixels, without filling the whole box.
            XCTAssertTrue(redPixels > 50)
            XCTAssertTrue(redPixels < 3000)
            if !flatten { XCTAssertEqual(page.annotations.first?.contents,"Visible text") }
            else { XCTAssertTrue(doc.string?.contains("Visible text") == true) }
        }
    }
    func testRedactionAndNonIncrementalExport() throws {
        let store = try DocumentStore(data:Self.fixture())
        let line = try XCTUnwrap(store.read { try $0.lines(page:0).first })
        _ = try store.transact { try $0.redact(page:0,bounds:line.bounds) }
        let data = try store.read { try $0.export() }
        let doc = try XCTUnwrap(PDFDocument(data:data))
        XCTAssertFalse(doc.string?.contains("secret") == true)
        XCTAssertTrue(doc.string?.contains("Keep this line") == true)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("/Prev "))
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("Original secret"))
    }
    func testEncryptedAndFlattenedExports() throws {
        let engine = try PDFEngine(data:Self.fixture())
        try engine.annotate(page:0,kind:"FreeText",bounds:CGRect(x:50,y:250,width:200,height:50),contents:"Flatten me",color:0)
        let encrypted = try engine.export(password:"local-only")
        XCTAssertThrowsError(try PDFEngine(data:encrypted))
        let reopened = try PDFEngine(data:encrypted,password:"local-only")
        XCTAssertEqual(reopened.pageCount,1)
        let flattened = try engine.export(flatten:true)
        let doc = try XCTUnwrap(PDFDocument(data:flattened))
        XCTAssertEqual(doc.page(at:0)?.annotations.count,0)
        XCTAssertTrue(doc.string?.contains("Flatten me") == true)
        XCTAssertEqual(PDFDocument(data:try engine.snapshot())?.page(at:0)?.annotations.count,1)
    }
    func testPagesBookmarksLinksAndExtraction() throws {
        let store = try DocumentStore(data:Self.fixture())
        _ = try store.transact { e in
            try e.insertBlank(at:1); try e.bookmark(page:0,title:"Start")
            try e.link(page:0,bounds:CGRect(x:50,y:300,width:100,height:20),uri:"https://example.com")
            try e.rotate(page:1); try e.reorder([1,0])
        }
        let doc = try XCTUnwrap(PDFDocument(data:try store.snapshot().data))
        XCTAssertEqual(doc.pageCount,2)
        XCTAssertEqual(doc.page(at:0)?.rotation,90)
        XCTAssertTrue(doc.page(at:1)?.string?.contains("Original secret") == true)
        XCTAssertEqual(doc.outlineRoot?.child(at:0)?.label,"Start")
        XCTAssertEqual(doc.page(at:1)?.annotations.first?.url?.absoluteString,"https://example.com")
        let extracted = try store.read { try $0.extract(pages:[1]) }
        XCTAssertEqual(PDFDocument(data:extracted)?.pageCount,1)
        XCTAssertTrue(PDFDocument(data:extracted)?.string?.contains("Original secret") == true)
    }
    func testGeometryRoundTripsForAllRotationsAndCropOffsets() throws {
        for rotation in [0,90,180,270] {
            let page = try XCTUnwrap(PDFDocument(data:Self.fixture(rotation:rotation))?.page(at:0))
            page.setBounds(CGRect(x:30,y:40,width:400,height:500),for:.cropBox)
            let geometry = PageGeometry(page:page)
            for point in [CGPoint(x:30,y:40),CGPoint(x:430,y:540),CGPoint(x:100,y:200)] {
                let restored = geometry.pdfPoint(geometry.enginePoint(point))
                XCTAssertEqual(restored.x,point.x,accuracy:0.001); XCTAssertEqual(restored.y,point.y,accuracy:0.001)
            }
            let engine = try PDFEngine(data:Self.fixture(rotation:rotation))
            try engine.crop(page:0,bounds:CGRect(x:20,y:20,width:200,height:300))
            let cropped = try XCTUnwrap(PDFDocument(data:try engine.snapshot())?.page(at:0))
            let b = cropped.bounds(for:.cropBox)
            XCTAssertEqual(rotation%180 == 0 ? b.width : b.height,200,accuracy:0.01)
        }
    }
    func testImageOccurrenceEditingPreservesText() throws {
        let data = Self.fixture(content:"BT /F1 18 Tf 50 700 Td (Keep me) Tj ET\nq 100 0 0 100 300 500 cm /Im1 Do Q")
        let store = try DocumentStore(data:data)
        let images = try store.read { try $0.images(page:0) }
        XCTAssertEqual(images.count,1)
        let image = try XCTUnwrap(images.first)
        XCTAssertTrue(image.editable)
        _ = try store.transact { try $0.editImage(page:0,index:0,bounds:image.bounds,remove:true) }
        XCTAssertEqual(try store.read { try $0.images(page:0).count },0)
        XCTAssertTrue(PDFDocument(data:try store.snapshot().data)?.string?.contains("Keep me") == true)
    }
    func testFormsAndMergeRejectionRollback() throws {
        let data = Self.fixture(extra:["<< /Type /Annot /Subtype /Widget /FT /Tx /T (Name) /V (Old) /Rect [50 400 250 430] /P 3 0 R /DA (/Helv 12 Tf 0 g) >>","<< /Fields [7 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >>"],pageExtra:"/Annots [7 0 R]",catalogExtra:"/AcroForm 8 0 R")
        let store = try DocumentStore(data:data)
        _ = try store.transact { try $0.form(page:0,index:0,value:"Alice") }
        XCTAssertEqual(PDFDocument(data:try store.snapshot().data)?.page(at:0)?.annotations.first?.widgetStringValue,"Alice")
        XCTAssertThrowsError(try store.transact { try $0.insert(data:data,at:1) })
        XCTAssertEqual(store.read { $0.pageCount },1)
    }
    func testOCRLayerIsInvisibleAndSearchable() throws {
        let engine = try PDFEngine()
        try engine.ocr(page:0,bounds:CGRect(x:50,y:50,width:160,height:20),text:"Searchable scan")
        let doc = try XCTUnwrap(PDFDocument(data:try engine.snapshot()))
        XCTAssertTrue(doc.string?.contains("Searchable scan") == true)
        let thumb = try XCTUnwrap(doc.page(at:0)?.thumbnail(of:CGSize(width:595,height:842),for:.cropBox).tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let pixel = try XCTUnwrap(thumb.colorAt(x:60,y:60)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(pixel.redComponent,0.98)
    }
    func testMergePreservesCommentsAndRejectsMalformedData() throws {
        let source = try PDFEngine(data:Self.fixture())
        try source.annotate(page:0,kind:"Text",bounds:CGRect(x:20,y:20,width:24,height:24),contents:"Merge note")
        let engine = try PDFEngine()
        try engine.insert(data:source.snapshot(),at:1)
        let doc = try XCTUnwrap(PDFDocument(data:try engine.snapshot()))
        XCTAssertEqual(doc.pageCount,2)
        XCTAssertTrue(doc.page(at:1)?.annotations.contains { $0.contents == "Merge note" } == true)
        XCTAssertThrowsError(try PDFEngine(data:Data("not a pdf".utf8)))
    }
    func testDuplicateIsIndependentAndMergeMapsInternalLinks() throws {
        let engine = try PDFEngine(data:Self.fixture())
        try engine.link(page:0,bounds:CGRect(x:10,y:10,width:50,height:20),uri:"#page=1")
        try engine.annotate(page:0,kind:"Text",bounds:CGRect(x:20,y:20,width:24,height:24),contents:"Original note")
        try engine.duplicate(pages:[0])
        try engine.rotate(page:1)
        try engine.annotation(page:1,index:0,contents:"Copy note")
        let doc = try XCTUnwrap(PDFDocument(data:engine.snapshot()))
        XCTAssertEqual(doc.pageCount,2)
        XCTAssertEqual(doc.page(at:0)?.rotation,0)
        XCTAssertEqual(doc.page(at:1)?.rotation,90)
        XCTAssertTrue(doc.page(at:0)?.annotations.contains { $0.contents == "Original note" } == true)
        XCTAssertTrue(doc.page(at:1)?.annotations.contains { $0.contents == "Copy note" } == true)
        let copiedLink = try XCTUnwrap(doc.page(at:1)?.annotations.first { $0.type == "Link" })
        XCTAssertEqual(copiedLink.destination?.page,doc.page(at:1))
    }
    func testReorderRetainsFormsAndCatalogMetadata() throws {
        let data = Self.fixture(extra:["<< /Type /Annot /Subtype /Widget /FT /Tx /T (Name) /V (Old) /Rect [50 400 250 430] /P 3 0 R /DA (/Helv 12 Tf 0 g) >>","<< /Fields [7 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >>"],pageExtra:"/Annots [7 0 R]",catalogExtra:"/AcroForm 8 0 R /Lang (en-US) /MarkInfo << /Marked true >>")
        let engine = try PDFEngine(data:data)
        try engine.insertBlank(at:1); try engine.reorder([1,0])
        try engine.form(page:1,index:0,value:"After reorder")
        let exported = try engine.snapshot()
        XCTAssertEqual(PDFDocument(data:exported)?.page(at:1)?.annotations.first?.widgetStringValue,"After reorder")
        let source = String(decoding:exported,as:UTF8.self)
        XCTAssertTrue(source.contains("/Lang(en-US)") || source.contains("/Lang (en-US)"))
        XCTAssertTrue(source.contains("/MarkInfo"))
    }
    func testRemainingMarkupTypesAndLinkManagement() throws {
        let engine = try PDFEngine(data:Self.fixture())
        let line = try XCTUnwrap(engine.lines(page:0).first)
        for kind in ["Underline","StrikeOut"] { try engine.annotate(page:0,kind:kind,bounds:line.bounds,quads:[line.bounds]) }
        for kind in ["Square","Circle","Line","Text"] { try engine.annotate(page:0,kind:kind,bounds:CGRect(x:50,y:300,width:100,height:40),contents:"Review") }
        try engine.link(page:0,bounds:CGRect(x:50,y:400,width:100,height:20),uri:"https://example.com")
        try engine.editLink(page:0,index:0,bounds:CGRect(x:50,y:420,width:100,height:20),uri:"https://example.org")
        let doc = try XCTUnwrap(PDFDocument(data:engine.snapshot()))
        XCTAssertEqual(doc.page(at:0)?.annotations.filter { $0.type != "Popup" }.count,7)
        XCTAssertEqual(doc.page(at:0)?.annotations.first { $0.type == "Link" }?.url?.host,"example.org")
        try engine.editLink(page:0,index:0,bounds:.zero,uri:"",remove:true)
        XCTAssertFalse(PDFDocument(data:try engine.snapshot())?.page(at:0)?.annotations.contains { $0.type == "Link" } == true)
    }
    func testRealOnDeviceOCRAndCompression() throws {
        let sourceDocument = try XCTUnwrap(PDFDocument(data:Self.fixture()))
        let page = try XCTUnwrap(sourceDocument.page(at:0))
        let image = page.thumbnail(of:CGSize(width:1200,height:1600),for:.cropBox)
        let scan = PDFDocument(); scan.insert(try XCTUnwrap(PDFPage(image:image)),at:0)
        let data = try XCTUnwrap(scan.dataRepresentation())
        let lines = try OCRService.recognize(data:data,pages:[0])
        XCTAssertTrue(lines.contains { $0.text.localizedCaseInsensitiveContains("Original") })
        let engine = try PDFEngine(data:data)
        for line in lines { try engine.ocr(page:line.page,bounds:line.bounds,text:line.text) }
        let compressed = try engine.export(compress:true)
        XCTAssertTrue(PDFDocument(data:compressed)?.string?.contains("Original") == true)
    }
    func testMixedStyleAndMissingGlyphRejection() throws {
        let engine = try PDFEngine(data:Self.fixture(content:"BT /F1 18 Tf 50 700 Td (First) Tj /F1 24 Tf ( mixed) Tj ET"))
        XCTAssertFalse(try XCTUnwrap(engine.lines(page:0).first).editable)
        let plain = try PDFEngine(data:Self.fixture())
        XCTAssertThrowsError(try plain.replaceLine(page:0,index:0,text:"emoji 😀",font:"Helvetica",size:18,color:0))
    }
}
