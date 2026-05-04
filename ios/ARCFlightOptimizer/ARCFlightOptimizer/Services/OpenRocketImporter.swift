import Foundation

struct ImportedRocketDesign {
    var name: String
    var fileName: String
    var dryMassGrams: Double?
    var diameterMillimeters: Double?
    var heightMillimeters: Double?
    var widthMillimeters: Double?
    var notes: String
}

enum OpenRocketImportError: LocalizedError {
    case unreadableFile
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Could not read that rocket design file."
        case .unsupportedFormat:
            return "Could not find rocket dimensions in that OpenRocket file."
        }
    }
}

enum OpenRocketImporter {
    static func importDesign(from data: Data, fileName: String, fallbackName: String) throws -> ImportedRocketDesign {
        guard String(data: data, encoding: .utf8) != nil else {
            throw OpenRocketImportError.unreadableFile
        }

        let parser = XMLParser(data: data)
        let delegate = OpenRocketParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            throw OpenRocketImportError.unsupportedFormat
        }

        let name = delegate.rocketName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mass = grams(fromOpenRocketMassValues: delegate.massValues)
        let height = millimeters(fromOpenRocketLengthValue: delegate.lengthValues.max())
        let diameter = diameterMillimeters(from: delegate)

        guard mass != nil || height != nil || diameter != nil else {
            throw OpenRocketImportError.unsupportedFormat
        }

        let importedName = (name?.isEmpty == false ? name : nil) ?? fallbackName
        let details = [
            mass.map { "mass \(Int($0)) g" },
            height.map { "height \(Int($0)) mm" },
            diameter.map { "diameter \(Int($0)) mm" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return ImportedRocketDesign(
            name: importedName.isEmpty ? "Imported Rocket" : importedName,
            fileName: fileName,
            dryMassGrams: mass,
            diameterMillimeters: diameter,
            heightMillimeters: height,
            widthMillimeters: diameter,
            notes: "Imported OpenRocket design: \(details)."
        )
    }

    private static func grams(fromOpenRocketMassValues values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return total <= 20 ? total * 1_000 : total
    }

    private static func millimeters(fromOpenRocketLengthValue value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 20 ? value * 1_000 : value
    }

    private static func diameterMillimeters(from delegate: OpenRocketParserDelegate) -> Double? {
        if let diameter = delegate.diameterValues.max() {
            return millimeters(fromOpenRocketLengthValue: diameter)
        }
        if let radius = delegate.radiusValues.max() {
            return millimeters(fromOpenRocketLengthValue: radius * 2)
        }
        return nil
    }
}

private final class OpenRocketParserDelegate: NSObject, XMLParserDelegate {
    var rocketName: String?
    var lengthValues: [Double] = []
    var radiusValues: [Double] = []
    var diameterValues: [Double] = []
    var massValues: [Double] = []

    private var currentElement = ""
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var hasCapturedRocketName = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        elementStack.append(currentElement)
        textBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let normalized = elementName.lowercased()
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "name", !hasCapturedRocketName, !value.isEmpty {
            rocketName = value
            hasCapturedRocketName = true
        }

        if let numericValue = Double(value) {
            if normalized.contains("length") {
                lengthValues.append(numericValue)
            } else if normalized.contains("radius") {
                radiusValues.append(numericValue)
            } else if normalized.contains("diameter") {
                diameterValues.append(numericValue)
            } else if normalized.contains("mass") {
                massValues.append(numericValue)
            }
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        currentElement = elementStack.last ?? ""
        textBuffer = ""
    }
}
