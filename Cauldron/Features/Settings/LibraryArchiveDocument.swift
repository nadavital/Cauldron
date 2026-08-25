import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cauldronLibraryArchive = UTType(exportedAs: "Nadav.Cauldron.library-archive")
}

struct LibraryArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cauldronLibraryArchive, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
