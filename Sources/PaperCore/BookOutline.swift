// SPDX-License-Identifier: MIT
import AppKit
import PDFKit

public struct BookChapter {
    public let title: String
    public let page: Int
    public let children: [BookChapter]
    public let embeddedIndex: Int?
    public init(title: String, page: Int, children: [BookChapter] = [], embeddedIndex: Int? = nil) {
        self.title = title; self.page = page; self.children = children; self.embeddedIndex = embeddedIndex
    }
}
public struct BookContents {
    public enum Source: Equatable { case embedded, contentsPage, headings, unavailable }
    public let chapters: [BookChapter]
    public let source: Source
}

/// Read embedded navigation first. Only infer navigation for PDFs without bookmarks.
/// Inferred results are view state; inspecting a book never modifies its PDF.
public enum BookOutline {
    private struct Line { let text: String; let size: CGFloat; let bold: Bool }
    private struct TOCEntry { let title: String; let printed: Int; let level: Int }
    public static func embedded(in document: PDFDocument) -> [BookChapter] {
        func read(_ item: PDFOutline, rootIndex: Int?) -> BookChapter? {
            let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination
            let children = (0..<item.numberOfChildren).compactMap { item.child(at:$0) }.compactMap { read($0, rootIndex:nil) }
            let page = destination?.page.map { document.index(for:$0) } ?? children.first?.page
            guard let page, page != NSNotFound, page >= 0, page < document.pageCount else { return nil }
            return BookChapter(title:item.label ?? "Untitled",page:page,children:children,embeddedIndex:rootIndex)
        }
        guard let root = document.outlineRoot else { return [] }
        return (0..<root.numberOfChildren).compactMap { index in root.child(at:index).flatMap { read($0,rootIndex:index) } }
    }
    public static func extract(data: Data) throws -> BookContents {
        guard let document = PDFDocument(data:data) else { throw PDFError("Could not read the book’s contents.") }
        let embedded = embedded(in:document)
        if !embedded.isEmpty { return BookContents(chapters:embedded,source:.embedded) }
        var pages: [[Line]] = []
        var sizes: [Int:Int] = [:]
        for index in 0..<document.pageCount {
            let lines = lines(on:document.page(at:index))
            pages.append(lines)
            for line in lines where line.text.count > 35 {
                sizes[Int(line.size.rounded()),default:0] += line.text.count
            }
        }
        let bodySize = CGFloat(sizes.max { $0.value < $1.value }?.key ?? 12)
        var frequency: [String:Int] = [:]
        for lines in pages { for key in Set(lines.prefix(5).map { normalize($0.text) }) { frequency[key,default:0] += 1 } }
        let headings: [(title:String,page:Int)] = pages.enumerated().flatMap { page,lines in
            lines.enumerated().compactMap { position,line -> (String,Int)? in
                let title = line.text.trimmingCharacters(in:.whitespacesAndNewlines)
                guard title.count > 1, title.count < 150, position < 32,
                      frequency[normalize(title),default:0] <= 2,
                      !title.hasSuffix("."), !title.contains("....."), !title.contains("…"),
                      !matches(title,#"\s\d+\s*$"#) || isNumberedHeading(title),
                      (isNumberedHeading(title) && (isChapterLabel(title) || line.bold || line.size >= bodySize*1.2)) || (isNamedHeading(title) && (line.bold || line.size >= bodySize*1.15)) || (line.size >= bodySize*1.4 && title.split(separator:" ").count < 16) else { return nil }
                if matches(title,#"^(?:contents|table of contents|indice|sommaire)$"#) { return nil }
                if isNumberedHeading(title), title.split(separator:" ").count <= 3, position+1 < lines.count {
                    let next = lines[position+1]
                    if next.text.count < 100 && next.text.count > 2 && (next.bold || next.size >= bodySize*1.2) && !isNumberedHeading(next.text) {
                        return (title+": "+next.text,page)
                    }
                }
                return (title,page)
            }
        }
        // Printed TOCs carry explicit page numbers. Match their titles to real
        // chapter pages to derive the front-matter offset instead of assuming zero.
        var toc: [TOCEntry] = []
        var tocPages = Set<Int>()
        for index in 0..<min(pages.count,40) {
            let lines = pages[index]
            let entries = lines.compactMap { parseTOC($0.text) }
            let hasTitle = lines.prefix(10).contains { matches($0.text,#"^(?:table of contents|contents|indice|sommaire|inhaltsverzeichnis)$"#) }
            let dotted = lines.filter { matches($0.text,#"\.{2,}|…|·{2,}"#) }.count
            if entries.count >= 2 && (hasTitle || dotted >= 2 || (tocPages.contains(index-1) && entries.count >= 3)) {
                toc.append(contentsOf:entries); tocPages.insert(index)
            }
        }
        if toc.count >= 2 {
            var offsets: [Int:Int] = [:]
            for entry in toc {
                if let actual = headings.first(where: { !tocPages.contains($0.page) && similar($0.title,entry.title) }) {
                    offsets[actual.page-(entry.printed-1),default:0] += 1
                }
                // Honor explicit PDF page labels when they identify an actual page.
                if let actual = (0..<document.pageCount).first(where: { !tocPages.contains($0) && document.page(at:$0)?.label == String(entry.printed) && pageContainsTitle(pages[$0],entry.title) }) {
                    offsets[actual-(entry.printed-1),default:0] += 1
                }
            }
            // Unmatched entries aren't guessed: require an evidenced mapping.
            let offset = offsets.max { $0.value < $1.value }?.key
            var resolved: [(TOCEntry,Int)] = []
            for entry in toc {
                let exact = headings.first { !tocPages.contains($0.page) && similar($0.title,entry.title) }?.page
                let textMatch = pages.indices.first { !tocPages.contains($0) && pageContainsTitle(pages[$0],entry.title) }
                let mapped = offset.map { entry.printed-1+$0 }
                guard let page = exact ?? textMatch ?? mapped, pages.indices.contains(page), !tocPages.contains(page) else { continue }
                if !resolved.contains(where: { normalize($0.0.title)==normalize(entry.title) && $0.1==page }) { resolved.append((entry,page)) }
            }
            if resolved.count >= 2 {
                var chapters: [BookChapter] = []
                var currentTitle: String?, currentPage = 0, children: [BookChapter] = []
                func flush() {
                    if let title = currentTitle { chapters.append(BookChapter(title:title,page:currentPage,children:children)) }
                }
                for (entry,page) in resolved {
                    if entry.level > 0, currentTitle != nil { children.append(BookChapter(title:entry.title,page:page)) }
                    else { flush(); currentTitle = entry.title; currentPage = page; children = [] }
                }
                flush()
                return BookContents(chapters:chapters,source:.contentsPage)
            }
        }
        var unique: [BookChapter] = []
        for heading in headings where !tocPages.contains(heading.page) {
            if !unique.contains(where: { $0.page==heading.page || normalize($0.title)==normalize(heading.title) }) {
                unique.append(BookChapter(title:heading.title,page:heading.page))
            }
        }
        return BookContents(chapters:unique.count >= 2 ? unique : [],source:unique.count >= 2 ? .headings : .unavailable)
    }
    private static func lines(on page: PDFPage?) -> [Line] {
        guard let text = page?.attributedString, text.length > 0 else { return [] }
        let string = text.string as NSString
        var result: [Line] = [], offset = 0
        while offset < string.length {
            let range = string.lineRange(for:NSRange(location:offset,length:0))
            let value = string.substring(with:range).trimmingCharacters(in:.whitespacesAndNewlines)
            var size: CGFloat = 0, bold = false
            text.enumerateAttribute(.font,in:range) { value,_,_ in
                if let font = value as? NSFont { size = max(size,font.pointSize); bold = bold || font.fontDescriptor.symbolicTraits.contains(.bold) }
            }
            if !value.isEmpty { result.append(Line(text:value,size:size,bold:bold)) }
            offset = NSMaxRange(range)
        }
        return result
    }
    private static func parseTOC(_ value: String) -> TOCEntry? {
        let pattern = #"^(.+?)(?:\s*[.·…]{2,}\s*|\s+)([0-9]{1,5})\s*$"#
        guard let regex = try? NSRegularExpression(pattern:pattern), let match = regex.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),
              let titleRange = Range(match.range(at:1),in:value), let numberRange = Range(match.range(at:2),in:value), let printed = Int(value[numberRange]), printed > 0 else { return nil }
        let title = String(value[titleRange]).trimmingCharacters(in:CharacterSet(charactersIn:" .·…\t"))
        guard title.count > 2, title.count < 150, !title.allSatisfy(\.isNumber) else { return nil }
        return TOCEntry(title:title,printed:printed,level:matches(title,#"^\d+\.\d+(?:\.\d+)*\s"#) ? 1 : 0)
    }
    private static func isChapterLabel(_ text: String) -> Bool {
        matches(text,#"^(?:chapter|part|book|section|capitolo|parte|chapitre|livre|kapitel)\s+"#)
    }
    private static func isNumberedHeading(_ text: String) -> Bool {
        matches(text,#"^(?:(?:chapter|part|book|section|capitolo|parte|chapitre|livre|kapitel)\s+(?:\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)\b|\d+(?:\.\d+)*[.)]?\s+[\p{L}])"#)
    }
    private static func isNamedHeading(_ text: String) -> Bool {
        matches(text,#"^(?:(?:introduction|preface|foreword|prologue|epilogue|conclusion|bibliography|references|index|acknowledgments|acknowledgements|appendix)(?:\s+[a-z0-9])?)$"#)
    }
    private static func matches(_ text: String,_ pattern: String) -> Bool { text.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil }
    private static func normalize(_ value: String) -> String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")).replacingOccurrences(of:#"[^\p{L}\p{N}]+"#,with:" ",options:.regularExpression).trimmingCharacters(in:.whitespaces)
    }
    private static func similar(_ a: String,_ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        return x==y || (min(x.count,y.count)>7 && (x.hasSuffix(y) || y.hasSuffix(x)))
    }
    private static func pageContainsTitle(_ lines: [Line],_ title: String) -> Bool {
        let top = lines.prefix(24).map(\.text)
        if top.contains(where: { similar($0,title) }) { return true }
        return zip(top,top.dropFirst()).contains { similar($0+" "+$1,title) }
    }
}
