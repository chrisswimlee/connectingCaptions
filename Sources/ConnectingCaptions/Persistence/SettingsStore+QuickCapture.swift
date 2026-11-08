//
//  SettingsStore+QuickCapture.swift
//  Fluid
//
//  Where the Caption Listen shortcut shows captions.
//

import Combine
import CoreGraphics
import Foundation

/// Theater is the caption window. Quick capture is the borderless chip.
enum CaptionPresentation: String, Codable, CaseIterable {
    case theater
    case quickCapture

    static func resolved(_ raw: String?) -> CaptionPresentation {
        guard let raw, let value = CaptionPresentation(rawValue: raw) else { return .theater }
        return value
    }
}

extension SettingsStore {
    private enum QuickCaptureDefaults {
        static let captionListenOpens = "CaptionListenOpens"
        static let originX = "QuickCaptureOriginX"
        static let originY = "QuickCaptureOriginY"
        static let hasOrigin = "QuickCaptureHasOrigin"
    }

    var captionListenOpens: CaptionPresentation {
        get { CaptionPresentation.resolved(self.defaults.string(forKey: QuickCaptureDefaults.captionListenOpens)) }
        set {
            objectWillChange.send()
            self.defaults.set(newValue.rawValue, forKey: QuickCaptureDefaults.captionListenOpens)
        }
    }

    var quickCaptureOrigin: CGPoint? {
        get {
            guard self.defaults.bool(forKey: QuickCaptureDefaults.hasOrigin) else { return nil }
            return CGPoint(
                x: self.defaults.double(forKey: QuickCaptureDefaults.originX),
                y: self.defaults.double(forKey: QuickCaptureDefaults.originY)
            )
        }
        set {
            objectWillChange.send()
            if let newValue {
                self.defaults.set(true, forKey: QuickCaptureDefaults.hasOrigin)
                self.defaults.set(newValue.x, forKey: QuickCaptureDefaults.originX)
                self.defaults.set(newValue.y, forKey: QuickCaptureDefaults.originY)
            } else {
                self.defaults.set(false, forKey: QuickCaptureDefaults.hasOrigin)
                self.defaults.removeObject(forKey: QuickCaptureDefaults.originX)
                self.defaults.removeObject(forKey: QuickCaptureDefaults.originY)
            }
        }
    }
}
