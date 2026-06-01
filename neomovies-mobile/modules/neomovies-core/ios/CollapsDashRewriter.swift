import Foundation

public class CollapsDashRewriter {
    public static func rewrite(
        manifest: String,
        voices: [String],
        subtitles: [CollapsSubtitle] = [],
        mediaId: String
    ) -> String {
        guard !manifest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return manifest
        }
        
        // Parse XML
        guard let data = manifest.data(using: .utf8) else { return manifest }
        let parser = XMLParser(data: data)
        let delegate = DashParserDelegate(voices: voices, subtitles: subtitles, mediaId: mediaId)
        parser.delegate = delegate
        parser.parse()
        
        return delegate.output
    }
}

private class DashParserDelegate: NSObject, XMLParserDelegate {
    let voices: [String]
    let subtitles: [CollapsSubtitle]
    let mediaId: String
    var output = ""
    var currentElement = ""
    var adaptationSetIndex = 0
    var representationIndex = 0
    var isAudioAdaptationSet = false
    var currentAdaptationSetId: String?
    
    init(voices: [String], subtitles: [CollapsSubtitle], mediaId: String) {
        self.voices = voices
        self.subtitles = subtitles
        self.mediaId = mediaId
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "AdaptationSet" {
            let mimeType = attributeDict["mimeType"] ?? ""
            isAudioAdaptationSet = mimeType.hasPrefix("audio/")
            currentAdaptationSetId = attributeDict["id"]
            
            var attrs = attributeDict
            
            // Rewrite audio track labels
            if isAudioAdaptationSet, let id = currentAdaptationSetId, let index = Int(id), index < voices.count {
                let voiceName = voices[index]
                attrs["lang"] = voiceName.lowercased().contains("eng") || voiceName.lowercased().contains("original") ? "en" : "ru"
                
                // Add label if not present
                if attrs["label"] == nil {
                    attrs["label"] = voiceName
                }
            }
            
            output += "<\(elementName)"
            for (key, value) in attrs.sorted(by: { $0.key < $1.key }) {
                output += " \(key)=\"\(escapeXml(value))\""
            }
            output += ">"
            
            adaptationSetIndex += 1
        } else if elementName == "Representation" {
            var attrs = attributeDict
            
            // Rewrite Representation id with proper naming
            let newId = "\(mediaId)_\(adaptationSetIndex)_\(representationIndex)"
            attrs["id"] = newId
            
            output += "<\(elementName)"
            for (key, value) in attrs.sorted(by: { $0.key < $1.key }) {
                output += " \(key)=\"\(escapeXml(value))\""
            }
            output += ">"
            
            representationIndex += 1
        } else if elementName == "Period" && !subtitles.isEmpty {
            // Start Period tag
            output += "<\(elementName)"
            for (key, value) in attributeDict.sorted(by: { $0.key < $1.key }) {
                output += " \(key)=\"\(escapeXml(value))\""
            }
            output += ">"
            
            // Inject subtitle AdaptationSets
            for (index, subtitle) in subtitles.enumerated() {
                let lang = subtitle.language.isEmpty ? "ru" : subtitle.language
                let label = subtitle.label.isEmpty ? "Subtitle" : subtitle.label
                
                output += "<AdaptationSet id=\"sub\(index)\" contentType=\"text\" lang=\"\(escapeXml(lang))\" label=\"\(escapeXml(label))\" mimeType=\"text/vtt\">"
                output += "<Representation id=\"sub\(index)_0\" bandwidth=\"1000\">"
                output += "<BaseURL>\(escapeXml(subtitle.url))</BaseURL>"
                output += "</Representation>"
                output += "</AdaptationSet>"
            }
        } else {
            output += "<\(elementName)"
            for (key, value) in attributeDict.sorted(by: { $0.key < $1.key }) {
                output += " \(key)=\"\(escapeXml(value))\""
            }
            output += ">"
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        output += "</\(elementName)>"
        
        if elementName == "AdaptationSet" {
            isAudioAdaptationSet = false
            currentAdaptationSetId = nil
            representationIndex = 0
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        output += escapeXml(string)
    }
    
    private func escapeXml(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
