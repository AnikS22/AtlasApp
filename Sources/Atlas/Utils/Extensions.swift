//
//  Extensions.swift
//  Atlas
//
//  Utility extensions for common functionality
//

import Foundation
import SwiftUI

// MARK: - Date Extensions
extension Date {
    /// Returns a formatted relative date string
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Returns a formatted date string for display
    var displayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Checks if the date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Checks if the date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Returns the start of the day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}

// MARK: - String Extensions
extension String {
    /// Returns the string with the first character capitalized
    var capitalizedFirst: String {
        guard !isEmpty else { return self }
        return prefix(1).capitalized + dropFirst()
    }

    /// Removes whitespace and newlines from both ends
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks if the string is a valid email
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }

    /// Returns the word count
    var wordCount: Int {
        let words = components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    /// Returns the character count without whitespace
    var characterCountWithoutSpaces: Int {
        filter { !$0.isWhitespace }.count
    }
}

// MARK: - Color Extensions
extension Color {
    /// Creates a color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Returns a hex string representation
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])

        return String(format: "#%02lX%02lX%02lX",
                     lroundf(r * 255),
                     lroundf(g * 255),
                     lroundf(b * 255))
    }
}

// MARK: - View Extensions
extension View {
    /// Applies a condition to modify the view
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    #if os(iOS)
    /// Applies a rounded corner with specific corners
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    #endif

    /// Adds a card style
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            #if os(iOS)
            .background(Color(UIColor.secondarySystemBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

#if os(iOS)
// MARK: - Rounded Corner Shape
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
#endif

// MARK: - Array Extensions
extension Array where Element: Identifiable {
    /// Removes duplicates based on id
    func removingDuplicates() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Data Extensions
extension Data {
    /// Returns a formatted string representation of the data size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - URL Extensions
extension URL {
    /// Returns the file size in bytes
    var fileSize: Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64
    }

    /// Returns the formatted file size
    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - TimeInterval Extensions
extension TimeInterval {
    /// Returns a formatted duration string
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60

        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Returns a precise formatted duration string
    var preciseDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: self) ?? "0s"
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let conversationUpdated = Notification.Name("conversationUpdated")
    static let messageReceived = Notification.Name("messageReceived")
    static let settingsChanged = Notification.Name("settingsChanged")
    static let modelLoadingStatusChanged = Notification.Name("modelLoadingStatusChanged")
}
