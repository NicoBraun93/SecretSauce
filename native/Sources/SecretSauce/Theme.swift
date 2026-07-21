import SwiftUI
import AppKit

extension Color {
    static let dsPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 59/255, green: 130/255, blue: 245/255, alpha: 1) // #3b82f5
        } else {
            return NSColor(red: 34/255, green: 116/255, blue: 234/255, alpha: 1) // #2274ea
        }
    })
    
    static let dsBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 13/255, green: 15/255, blue: 18/255, alpha: 1) // #0d0f12
        } else {
            return NSColor(red: 248/255, green: 249/255, blue: 251/255, alpha: 1) // #f8f9fb
        }
    })
    
    static let dsCard = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 17/255, green: 19/255, blue: 25/255, alpha: 1) // #111319
        } else {
            return NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1) // #ffffff
        }
    })
    
    static let dsSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 27/255, green: 30/255, blue: 40/255, alpha: 1) // #1b1e28
        } else {
            return NSColor(red: 238/255, green: 240/255, blue: 244/255, alpha: 1) // #eef0f4
        }
    })
    
    static let dsBorder = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 27/255, green: 30/255, blue: 40/255, alpha: 1) // #1b1e28
        } else {
            return NSColor(red: 221/255, green: 224/255, blue: 231/255, alpha: 1) // #dde0e7
        }
    })
    
    static let dsForeground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 231/255, green: 235/255, blue: 241/255, alpha: 1) // #e7ebf1
        } else {
            return NSColor(red: 22/255, green: 27/255, blue: 38/255, alpha: 1) // #161b26
        }
    })
    
    static let dsMutedForeground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.name.rawValue.lowercased().contains("dark") {
            return NSColor(red: 128/255, green: 137/255, blue: 148/255, alpha: 1) // #808994
        } else {
            return NSColor(red: 93/255, green: 100/255, blue: 111/255, alpha: 1) // #5d646f
        }
    })
    
    static let dsSuccess = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let dsWarning = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let dsDanger = Color(red: 239/255, green: 68/255, blue: 68/255) // #ef4444
}
