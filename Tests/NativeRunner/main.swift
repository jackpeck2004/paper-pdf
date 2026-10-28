import AppKit
_ = NSApplication.shared
let instance = EngineTests()
let cases: [(String,(EngineTests) -> () throws -> Void)] = [
    ("text replacement",EngineTests.testTextReplacementRemovesOriginalAndKeepsOtherText),
    ("atomic failures",EngineTests.testFailureIsAtomicAndStaleWorkRejected),
    ("annotation round trips and undo",EngineTests.testAnnotationsRoundTripAndUndoSnapshots),
    ("secure redaction",EngineTests.testRedactionAndNonIncrementalExport),
    ("encrypted and flattened export",EngineTests.testEncryptedAndFlattenedExports),
    ("page organization",EngineTests.testPagesBookmarksLinksAndExtraction),
    ("page geometry",EngineTests.testGeometryRoundTripsForAllRotationsAndCropOffsets),
    ("image occurrence editing",EngineTests.testImageOccurrenceEditingPreservesText),
    ("forms and merge rollback",EngineTests.testFormsAndMergeRejectionRollback),
    ("invisible OCR layer",EngineTests.testOCRLayerIsInvisibleAndSearchable),
    ("merge comments and malformed input",EngineTests.testMergePreservesCommentsAndRejectsMalformedData),
    ("independent duplicates and internal links",EngineTests.testDuplicateIsIndependentAndMergeMapsInternalLinks),
    ("form and catalog preservation",EngineTests.testReorderRetainsFormsAndCatalogMetadata),
    ("all markup and link management",EngineTests.testRemainingMarkupTypesAndLinkManagement),
    ("on-device OCR and compression",EngineTests.testRealOnDeviceOCRAndCompression),
    ("unsupported text",EngineTests.testMixedStyleAndMissingGlyphRejection)
]
for (name,test) in cases {
    let before = testFailures
    do { try test(instance)() } catch { testFailures += 1; print("FAIL \(name): \(error)") }
    print("\(testFailures == before ? "PASS" : "FAIL") \(name)")
}
let bookTests = BookOutlineTests()
let bookCases: [(String,() throws -> Void)] = [
    ("embedded book navigation",bookTests.testEmbeddedBookmarksWinOverHeuristics),
    ("detected chapters",bookTests.testDetectsHeadingsWithoutBookmarksAndSkipsRunningHeaders),
    ("printed contents and front-matter offset",bookTests.testPrintedTOCResolvesFrontMatterAndSubsections),
    ("no invented chapters",bookTests.testDoesNotInventChaptersForPlainOrScannedDocuments)
]
for (name,test) in bookCases {
    let before = testFailures
    do { try test() } catch { testFailures += 1; print("FAIL \(name): \(error)") }
    print("\(testFailures == before ? "PASS" : "FAIL") \(name)")
}
let documentTests = DocumentTests()
let nativeCases: [(String,() throws -> Void)] = [
    ("native window, controller actions, undo and redo",documentTests.testNativeWindowCommandsAndUndoRedo),
    ("inline editing and icon toolbar",documentTests.testInlineTextEditingAndIconToolbar),
    ("hierarchical chapter navigation",documentTests.testOutlineHierarchyNavigatesToChapter),
    ("view-mode keyboard dispatch",documentTests.testReaderMenuShortcutsDispatchToAllViewModes),
    ("page navigation and shortcut aliases",documentTests.testGoToPageFieldAndShortcutAliases),
    ("responsive layout and native glass",documentTests.testResponsiveLayoutUsesNativeGlass),
    ("Preview sidebar and single page control",documentTests.testPreviewSidebarAndSinglePageControl),
    ("native thumbnail reordering and undo",documentTests.testNativeThumbnailReorderCommitsAndUndoes),
    ("full-width outline and trailing page numbers",documentTests.testOutlineUsesFullWidthAndTrailingPageColumn),
    ("native atomic save and reopen",documentTests.testNativeAtomicSaveAndReopen)
]
for (name,test) in nativeCases {
    let before = testFailures
    do { try test() } catch { testFailures += 1; print("FAIL \(name): \(error)") }
    print("\(testFailures == before ? "PASS" : "FAIL") \(name)")
}
print("\(cases.count+bookCases.count+nativeCases.count) tests, \(testFailures) failures")
exit(testFailures == 0 ? 0 : 1)
