import Foundation

enum FileTemplates {
    static var directory: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.resourceURL?.appendingPathComponent("FileTemplates", isDirectory: true)
    }
    static func data(for format: FileFormat) throws -> Data {
        if format == .txt || format == .md { return Data() }
        guard let directory else { throw RightNookError.templateUnavailable }
        return try data(for: format, in: directory)
    }
    static func data(for format: FileFormat, in directory: URL) throws -> Data {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("blank.\(format.rawValue)")),
              data.starts(with: format == .rtf ? Data("{\\rtf1".utf8) : Data([0x50, 0x4b, 0x03, 0x04])) else {
            throw RightNookError.templateUnavailable
        }
        return data
    }
}
