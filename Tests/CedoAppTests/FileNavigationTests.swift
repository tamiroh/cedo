import Foundation
import Testing

@testable import CedoApp

@MainActor
struct FileNavigationTests {
    @Test func navigatesFileHistoryAcrossDeletionsAndNewSelections() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = ["first", "second", "third", "fourth"].map { folder.appendingPathComponent($0) }
        let workspace = Workspace()
        for file in files {
            try "draft".write(to: file, atomically: true, encoding: .utf8)
            workspace.select(file)
            workspace.select(file)
        }
        try FileManager.default.removeItem(at: files[1])
        workspace.goBack()
        #expect(workspace.selectedFile == files[2])
        workspace.goBack()
        #expect(workspace.selectedFile == files[0])
        #expect(workspace.previousFiles.isEmpty)
        workspace.goBack()
        #expect(workspace.selectedFile == files[0])
        workspace.select(files[0])
        workspace.goForward()
        #expect(workspace.selectedFile == files[2])
        workspace.goForward()
        #expect(workspace.selectedFile == files[3])
        workspace.goBack()
        workspace.select(files[0])
        #expect(workspace.nextFiles.isEmpty)
        workspace.goForward()
        #expect(workspace.selectedFile == files[0])
    }
}
