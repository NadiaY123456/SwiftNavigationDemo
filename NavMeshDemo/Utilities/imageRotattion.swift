//
//  imageRotattion.swift
//  NavMeshDemo
//
import UIKit

extension UIImage {
    /// Rotates the image by the specified angle in degrees
    func rotated(by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        
        // Calculate the size of the rotated image
        var newSize = CGRect(origin: .zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .size
        
        // Ensure the size is positive
        newSize.width = abs(newSize.width)
        newSize.height = abs(newSize.height)
        
        // Create a context for the rotated image
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Move origin to center
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        // Rotate
        context.rotate(by: radians)
        // Draw the image centered
        self.draw(in: CGRect(
            x: -self.size.width/2,
            y: -self.size.height/2,
            width: self.size.width,
            height: self.size.height
        ))
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Common rotations
    func rotated90Clockwise() -> UIImage? {
        return rotated(by: 90)
    }
    
    func rotated90CounterClockwise() -> UIImage? {
        return rotated(by: -90)
    }
    
    func rotated180() -> UIImage? {
        return rotated(by: 180)
    }
    
    /// Flips the image horizontally
    func flippedHorizontally() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Flip horizontally
        context.translateBy(x: size.width, y: 0)
        context.scaleBy(x: -1.0, y: 1.0)
        
        draw(at: .zero)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Flips the image vertically
    func flippedVertically() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Flip vertically
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        draw(at: .zero)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

