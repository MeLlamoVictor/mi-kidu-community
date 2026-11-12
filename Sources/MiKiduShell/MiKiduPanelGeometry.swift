import Foundation
import CoreGraphics

/// Geometría en coordenadas globales AppKit, con origen inferior izquierdo.
public enum MiKiduPanelGeometry {
    public static let size = CGSize(width: 116, height: 64)
    public static let avatarHitRectTopLeft = CGRect(x: 4, y: 4, width: 56, height: 56)
    public static let menuHitRectTopLeft = CGRect(x: 68, y: 10, width: 44, height: 44)

    public static func origin(visibleFrame: CGRect, size: CGSize = Self.size,
                              margen: CGFloat = 16) -> CGPoint {
        let x = max(visibleFrame.minX, visibleFrame.maxX - size.width - margen)
        let y = max(visibleFrame.minY, visibleFrame.maxY - size.height - margen)
        return CGPoint(x: x, y: y)
    }

    public static func limitar(_ frame: CGRect, a visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - height)
        let x = min(maxX, max(visibleFrame.minX, frame.minX))
        let y = min(maxY, max(visibleFrame.minY, frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func indicePantalla(contiene punto: CGPoint, marcos: [CGRect]) -> Int? {
        marcos.firstIndex(where: { $0.contains(punto) })
    }

    public static func rectanguloHitTest(_ topLeftRect: CGRect, altoVista: CGFloat) -> CGRect {
        CGRect(x: topLeftRect.minX,
               y: altoVista - topLeftRect.maxY,
               width: topLeftRect.width,
               height: topLeftRect.height)
    }
}

public enum MiKiduPanelPresence: Equatable, Sendable {
    case cerrado
    case visible
}
