import AppKit
import Testing
@testable import ZoomDNZ

@Suite struct AnnotationTests {
    @Test func rectIsNormalizedRegardlessOfDragDirection() {
        let a = Annotation(tool: .rect, points: [CGPoint(x: 50, y: 80), CGPoint(x: 10, y: 20)],
                           color: .red, width: 2)
        #expect(a.rect == CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    @Test func translateMovesEveryPoint() {
        var a = Annotation(tool: .pen, points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)],
                           color: .red, width: 2)
        a.translate(by: CGPoint(x: 10, y: -1))
        #expect(a.points == [CGPoint(x: 11, y: 1), CGPoint(x: 13, y: 3)])
    }

    @Test func emptyAnnotationHasZeroRect() {
        let a = Annotation(tool: .line, color: .red, width: 2)
        #expect(a.rect == .zero)
    }
}
