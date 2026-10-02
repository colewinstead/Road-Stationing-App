import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Raw XML nodes exist only at the parsing boundary; engine models are typed.
final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""
    init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
}

final class XMLDocument: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var root: XMLNode?
    private var failure: String?
    private var nodeCount = 0
    private var textCount = 0
    static func parse(_ data: Data) throws -> XMLNode {
        guard data.count <= 64 * 1024 * 1024 else { throw LandXMLParsingError.invalidXML("File exceeds 64 MiB import limit.") }
        let delegate = XMLDocument(); let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, let root = delegate.root else {
            throw LandXMLParsingError.invalidXML(delegate.failure ?? parser.parserError?.localizedDescription ?? "Empty document.")
        }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        nodeCount += 1
        if nodeCount > 1_000_000 || stack.count >= 128 { failure = "XML nesting/node limit exceeded."; parser.abortParsing(); return }
        let node = XMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textCount += string.utf8.count
        if textCount > 64 * 1024 * 1024 { failure = "XML text limit exceeded."; parser.abortParsing(); return }
        stack.last?.text.append(string)
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    // Geometry does not require DTDs or entities. Reject declarations entirely.
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        failure = "Entity declarations are not supported."; parser.abortParsing()
    }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        failure = "External entities are not supported."; parser.abortParsing()
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { nil }
}
