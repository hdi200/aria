// Android stand-in for UniformTypeIdentifiers: the UTType values the shared iOS code names.
// Android identifies files by MIME type; `preferredMIMEType` carries it.

import Foundation

public struct UTType: Hashable, Sendable, CustomStringConvertible {
    public let identifier: String
    public let preferredFilenameExtension: String?
    public let preferredMIMEType: String?
    private let supertypes: [String]

    public init(_ identifier: String, filenameExtension: String? = nil, mimeType: String? = nil, conformsTo supertypes: [String] = []) {
        self.identifier = identifier
        self.preferredFilenameExtension = filenameExtension
        self.preferredMIMEType = mimeType
        self.supertypes = supertypes
    }

    public init?(filenameExtension: String) {
        let lowercased = filenameExtension.lowercased()
        guard !lowercased.isEmpty else {
            return nil
        }
        if let known = UTType.known.first(where: { $0.preferredFilenameExtension == lowercased }) {
            self = known
        } else {
            self.init("dyn.ext.\(lowercased)", filenameExtension: lowercased, mimeType: "application/octet-stream", conformsTo: [UTType.data.identifier])
        }
    }

    public var description: String { identifier }

    public func conforms(to type: UTType) -> Bool {
        type == self || supertypes.contains(type.identifier) || type == .item || (type == .data && self != .folder)
    }

    public static let item = UTType("public.item", mimeType: "*/*")
    public static let content = UTType("public.content", mimeType: "*/*", conformsTo: ["public.item"])
    public static let data = UTType("public.data", mimeType: "application/octet-stream", conformsTo: ["public.item"])
    public static let folder = UTType("public.folder", conformsTo: ["public.item"])
    public static let fileURL = UTType("public.file-url", conformsTo: ["public.item"])
    public static let text = UTType("public.text", mimeType: "text/*", conformsTo: ["public.data", "public.content"])
    public static let plainText = UTType("public.plain-text", filenameExtension: "txt", mimeType: "text/plain", conformsTo: ["public.text"])
    public static let json = UTType("public.json", filenameExtension: "json", mimeType: "application/json", conformsTo: ["public.text"])
    public static let xml = UTType("public.xml", filenameExtension: "xml", mimeType: "text/xml", conformsTo: ["public.text"])
    public static let zip = UTType("public.zip-archive", filenameExtension: "zip", mimeType: "application/zip", conformsTo: ["public.data"])
    public static let pdf = UTType("com.adobe.pdf", filenameExtension: "pdf", mimeType: "application/pdf", conformsTo: ["public.data", "public.content"])
    public static let image = UTType("public.image", mimeType: "image/*", conformsTo: ["public.data", "public.content"])
    public static let png = UTType("public.png", filenameExtension: "png", mimeType: "image/png", conformsTo: ["public.image"])
    public static let jpeg = UTType("public.jpeg", filenameExtension: "jpg", mimeType: "image/jpeg", conformsTo: ["public.image"])
    public static let audio = UTType("public.audio", mimeType: "audio/*", conformsTo: ["public.data", "public.content"])
    public static let midi = UTType("public.midi-audio", filenameExtension: "mid", mimeType: "audio/midi", conformsTo: ["public.audio"])
    public static let movie = UTType("public.movie", mimeType: "video/*", conformsTo: ["public.data", "public.content"])
    public static let mpeg4Movie = UTType("public.mpeg-4", filenameExtension: "mp4", mimeType: "video/mp4", conformsTo: ["public.movie"])

    private static let known: [UTType] = [plainText, json, xml, zip, pdf, png, jpeg, midi, mpeg4Movie]
}
