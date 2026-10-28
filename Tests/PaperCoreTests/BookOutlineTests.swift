// SPDX-License-Identifier: MIT
#if !PAPER_NATIVE_TESTS
import XCTest
#endif
import PDFKit
import PaperCore

final class BookOutlineTests: XCTestCase {
    static func book(_ contents: [String]) throws -> Data {
        let doc = PDFDocument()
        for (i,content) in contents.enumerated() {
            let pageDoc = PDFDocument(data:EngineTests.fixture(content:content))!
            let page = pageDoc.page(at:0)!
            doc.insert(page,at:i)
        }
        return try XCTUnwrap(doc.dataRepresentation())
    }
    static func page(_ heading: String, body: String = "This is an ordinary body paragraph about the material discussed in the book.") -> String {
        "BT /F1 24 Tf 50 700 Td (\(heading)) Tj ET\nBT /F1 11 Tf 50 640 Td (\(body)) Tj ET"
    }
    func testEmbeddedBookmarksWinOverHeuristics() throws {
        let engine = try PDFEngine(data:Self.book([Self.page("Chapter 1"),Self.page("Chapter 2")]))
        try engine.bookmark(page:1,title:"Author supplied navigation")
        let contents = try BookOutline.extract(data:engine.snapshot())
        XCTAssertEqual(contents.chapters.count,1)
        XCTAssertEqual(contents.chapters.first?.title,"Author supplied navigation")
        XCTAssertEqual(contents.chapters.first?.page,1)
        XCTAssertEqual(contents.chapters.first?.embeddedIndex,0)
    }
    func testDetectsHeadingsWithoutBookmarksAndSkipsRunningHeaders() throws {
        let data = try Self.book([
            Self.page("Chapter 1: Beginnings"),
            Self.page("Chapter 2: Middle"),
            Self.page("Chapter 3: Endings"),
            Self.page("Running Header",body:"An ordinary paragraph ending with a period."),
            Self.page("Running Header",body:"An ordinary paragraph ending with a period."),
            Self.page("Running Header",body:"An ordinary paragraph ending with a period.")
        ])
        let result = try BookOutline.extract(data:data)
        XCTAssertEqual(result.chapters.map(\.page),[0,1,2])
        XCTAssertEqual(result.chapters.last?.title,"Chapter 3: Endings")
    }
    func testPrintedTOCResolvesFrontMatterAndSubsections() throws {
        let toc = "BT /F1 22 Tf 50 700 Td (Contents) Tj ET\nBT /F1 12 Tf 50 650 Td (Chapter 1: Beginnings .... 1) Tj ET\nBT /F1 12 Tf 50 625 Td (1.1 Early Days .... 2) Tj ET\nBT /F1 12 Tf 50 600 Td (Chapter 2: Middle .... 3) Tj ET"
        let data = try Self.book([Self.page("A Book"),toc,Self.page("Chapter 1: Beginnings"),Self.page("1.1 Early Days"),Self.page("Chapter 2: Middle")])
        let result = try BookOutline.extract(data:data)
        XCTAssertEqual(result.chapters.count,2)
        XCTAssertEqual(result.chapters.first?.page,2)
        XCTAssertEqual(result.chapters.first?.children.first?.page,3)
        XCTAssertEqual(result.chapters.last?.page,4)
    }
    func testDoesNotInventChaptersForPlainOrScannedDocuments() throws {
        let plain = try Self.book(["BT /F1 12 Tf 50 700 Td (A normal paragraph in a short document.) Tj ET"])
        XCTAssertTrue(try BookOutline.extract(data:plain).chapters.isEmpty)
        let numberedBody = try Self.book(["BT /F1 12 Tf 50 700 Td (1. A short list item) Tj 0 -20 Td (2. Another list item) Tj ET"])
        XCTAssertTrue(try BookOutline.extract(data:numberedBody).chapters.isEmpty)
        let blank = try PDFEngine().snapshot()
        XCTAssertTrue(try BookOutline.extract(data:blank).chapters.isEmpty)
    }
}
