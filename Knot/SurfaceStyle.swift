import SwiftUI

extension View {
    func knotSurfaceBorder(cornerRadius: CGFloat = 12, lineWidth: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.knotBorder, lineWidth: lineWidth)
        )
    }
}
