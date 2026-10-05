import Foundation
import PDFKit

/// Turns a degree document into plain text lines: PDF (PDFKit), HTML, MHTML (a saved web page: MIME parts decoded
/// from quoted-printable / base64, the HTML part used), Word .docx (word/document.xml via /usr/bin/unzip), and
/// plain text / Markdown. Pure except for reading the file (and unzip for .docx).
public enum DegreeDocumentText {
    public enum Format: String, Hashable, Sendable {
        case pdf, html, mhtml, docx, text
    }

    public struct Extracted: Hashable, Sendable {
        public var format: Format
        public var text: String
        /// The page's `<title>` or first `<h1>`, when the document had one.
        public var heading: String?
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unreadable(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): return why
            case .empty(let name): return "No text could be read from \(name). If it is a scanned PDF, save the page as HTML or PDF from the catalog instead."
            }
        }
    }

    public static func format(of url: URL, data: Data) -> Format {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "mhtml", "mht": return .mhtml
        case "html", "htm", "xhtml": return .html
        case "docx": return .docx
        default:
            if data.starts(with: Array("%PDF".utf8)) { return .pdf }
            if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .docx }
            let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
            if head.contains("mime-version:") && head.contains("multipart/related") { return .mhtml }
            if head.contains("<html") || head.contains("<!doctype html") { return .html }
            return .text
        }
    }

    public static func extract(contentsOf url: URL) throws -> Extracted {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw Failure.unreadable("\(url.lastPathComponent) couldn’t be opened: \(error.localizedDescription)") }
        let format = format(of: url, data: data)
        let result: Extracted
        switch format {
        case .pdf: result = try pdf(data, name: url.lastPathComponent)
        case .docx: result = Extracted(format: .docx, text: try docx(url), heading: nil)
        default: result = extract(data: data, format: format)
        }
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Failure.empty(url.lastPathComponent) }
        return result
    }

    /// Text formats from memory (HTML, MHTML, text).
    public static func extract(data: Data, format: Format) -> Extracted {
        switch format {
        case .mhtml:
            let html = mhtmlHTML(data)
            return Extracted(format: .mhtml, text: text(fromHTML: html), heading: heading(inHTML: html))
        case .html:
            let html = decodeText(data)
            return Extracted(format: .html, text: text(fromHTML: html), heading: heading(inHTML: html))
        default:
            return Extracted(format: format, text: decodeText(data), heading: nil)
        }
    }

    static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: PDF

    static func pdf(_ data: Data, name: String) throws -> Extracted {
        guard let document = PDFDocument(data: data) else { throw Failure.unreadable("\(name) isn’t a readable PDF.") }
        var pages: [String] = []
        for index in 0 ..< document.pageCount {
            if let text = document.page(at: index)?.string { pages.append(text) }
        }
        return Extracted(format: .pdf, text: pages.joined(separator: "\n"), heading: document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
    }

    // MARK: DOCX

    static func docx(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { throw Failure.unreadable("\(url.lastPathComponent) couldn’t be unpacked.") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw Failure.unreadable("\(url.lastPathComponent) isn’t a Word document this app can read.") }
        return text(fromWordXML: decodeText(data))
    }

    /// Paragraphs (`</w:p>`) and line breaks become newlines; tabs stay; runs' text is kept.
    public static func text(fromWordXML xml: String) -> String {
        var s = xml
        s = s.replacingOccurrences(of: #"</w:p>"#, with: "\n")
        s = s.replacingOccurrences(of: #"<w:br[^>]*/>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<w:tab[^>]*/>"#, with: "\t", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(s)
    }

    // MARK: MHTML

    /// The HTML of a saved web page (the first text/html part; all of them when there are several).
    public static func mhtmlHTML(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self)
        guard let boundary = mimeBoundary(raw) else { return raw }
        var htmls: [String] = []
        for part in raw.components(separatedBy: "--" + boundary) {
            guard let split = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") else { continue }
            let headers = part[..<split.lowerBound].lowercased()
            guard headers.contains("content-type: text/html") else { continue }
            let body = String(part[split.upperBound...])
            if headers.contains("content-transfer-encoding: quoted-printable") {
                htmls.append(decodeText(quotedPrintable(body)))
            } else if headers.contains("content-transfer-encoding: base64") {
                let compact = body.filter { !$0.isWhitespace }
                htmls.append(decodeText(Data(base64Encoded: compact) ?? Data()))
            } else {
                htmls.append(body)
            }
        }
        return htmls.isEmpty ? raw : htmls.joined(separator: "\n")
    }

    static func mimeBoundary(_ raw: String) -> String? {
        let head = String(raw.prefix(8192))
        guard let range = head.range(of: #"boundary="?([^"\r\n;]+)"?"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(head[range])
        let value = match.drop { $0 != "=" }.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return value.isEmpty ? nil : value
    }

    /// RFC 2045 quoted-printable: "=\r\n" soft breaks removed, "=XX" bytes decoded.
    public static func quotedPrintable(_ text: String) -> Data {
        var out = Data()
        let bytes = Array(text.utf8)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 48 ... 57: return b - 48
            case 65 ... 70: return b - 55
            case 97 ... 102: return b - 87
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == 61 { // "="
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                if i + 2 < bytes.count, let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                    out.append(h << 4 | l)
                    i += 3
                    continue
                }
            }
            out.append(b)
            i += 1
        }
        return out
    }

    // MARK: HTML

    /// Block elements become line breaks, list items "• ", table cells tabs; scripts / styles / heads are dropped;
    /// entities decoded; runs of spaces collapsed per line.
    public static func text(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "head", "noscript", "svg", "template"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<span[^>]*display:\s*none[^>]*>[\s\S]*?</span>"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<li\b[^>]*>"#, with: "\n• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<(br|hr)\b[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"</?(p|div|h[1-6]|ul|ol|tr|table|tbody|thead|section|article|header|footer|li|dt|dd|dl|blockquote|pre|nav|main|aside|form|fieldset|legend|caption|label)\b[^>]*>"#,
                                   with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"</t[dh]>"#, with: "\t", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        let lines = s.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"[ \t\u{00a0}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        var out: [String] = []
        for line in lines where !(line.isEmpty && (out.last?.isEmpty ?? true)) { out.append(line) }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func heading(inHTML html: String) -> String? {
        for pattern in [#"<h1\b[^>]*>([\s\S]*?)</h1>"#, #"<title\b[^>]*>([\s\S]*?)</title>"#] {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let inner = String(html[range]).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                let text = BannerText.collapse(decodeEntities(inner))
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "rsquo": "’",
        "lsquo": "‘", "rdquo": "”", "ldquo": "“", "bull": "•", "hellip": "…", "middot": "·", "rarr": "→", "copy": "©", "reg": "®",
        "trade": "™", "eacute": "é", "zwnj": "", "zwj": "", "shy": "",
    ]

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[amp...]
            if let semi = after.prefix(12).firstIndex(of: ";") {
                let name = String(after[after.index(after: amp) ..< semi])
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X"), let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) {
                    replacement = String(Character(u))
                } else if name.hasPrefix("#"), let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) {
                    replacement = String(Character(u))
                } else {
                    replacement = namedEntities[name]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after.dropFirst()
        }
        out += rest
        return out
    }
}
