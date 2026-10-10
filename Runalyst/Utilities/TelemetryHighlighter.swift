import SwiftUI

/// Utility for rendering telemetry citations (SPM, BPM, pace, biomechanics) in bold, app-accent color via AttributedString.
enum TelemetryHighlighter {

    /// Highlights numbers and biomechanical units with bold weight and accent styling.
    static func highlight(_ text: String, accentColor: Color = Color(red: 0.0, green: 0.75, blue: 0.65)) -> AttributedString {
        var attributed = AttributedString(text)

        // Patterns covering cadence, heart rate, pace strings, percentages, and metrics
        let patterns = [
            #"\b\d{2,3}\s?(?:SPM|spm)\b"#,
            #"\b\d{2,3}\s?(?:BPM|bpm)\b"#,
            #"\b\d{1,2}:\d{2}(?:\s?(?:/km|/mi|min/km|min/mi))?\b"#,
            #"\b\d+(?:\.\d+)?\s?(?:cm|m|km|mi|%)\b"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

                for match in matches {
                    if let stringRange = Range(match.range, in: text),
                       let attrRange = Range(stringRange, in: attributed) {
                        attributed[attrRange].font = .system(size: 15, weight: .bold, design: .rounded)
                        attributed[attrRange].foregroundColor = accentColor
                    }
                }
            }
        }

        return attributed
    }
}
