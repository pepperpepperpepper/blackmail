// Guarded so this file compiles away on a host without UIKit.
// The library is built for Linux too, so the MIME and IMAP parsers
// can be tested in seconds instead of through a device cycle.
#if canImport(UIKit)

import UIKit

/// Tiny image factories for the two places UIKit will not take a colour.
///
/// `UISearchBar` is the case that forced these. Given `barTintColor` 201 it
/// renders 249, and a height constraint on its `searchTextField` is overridden
/// by its own layout — both measured on device, not assumed. A background
/// image is the one input it honours exactly, so fill, height and corner
/// radius all have to travel as pixels.
extension UIImage {

    /// A 1×1 image of a solid colour, stretched by the bar that uses it.
    static func solid(_ colour: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            colour.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    /// A rounded field of an exact height, resizable across its middle so the
    /// corners keep their radius at any width.
    static func roundedField(fill: UIColor, height: CGFloat, radius: CGFloat) -> UIImage {
        let w = radius * 2 + 1
        let size = CGSize(width: w, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                         cornerRadius: radius).fill()
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: radius, left: radius,
                                        bottom: radius, right: radius),
            resizingMode: .stretch)
    }
}

#endif
