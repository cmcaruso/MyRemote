import CoreGraphics
import HostCore
import Testing

@Suite("The Laser's dot")
struct LaserTests {
    static let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let projector = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    @Test func startsInTheCentreOfTheDisplayWithTheCursor() {
        var laser = Laser()
        laser.start(cursor: CGPoint(x: 2000, y: 500), displays: [Self.builtIn, Self.projector])
        #expect(laser.display == Self.projector)
        #expect(laser.position == CGPoint(x: 2472, y: 540))
    }

    @Test func eachHoldStartsInTheCentreAgain() {
        var laser = Laser()
        laser.start(cursor: .zero, displays: [Self.builtIn])
        laser.move(dx: 300, dy: 100)
        _ = laser.step(dt: 1)
        laser.end()
        #expect(laser.display == nil)
        laser.start(cursor: .zero, displays: [Self.builtIn])
        #expect(laser.position == CGPoint(x: 756, y: 491))
    }

    @Test func easesTowardTheTargetAndArrives() {
        var laser = Laser()
        laser.start(cursor: .zero, displays: [Self.builtIn])
        laser.move(dx: 100, dy: 0)
        let first = laser.step(dt: 1.0 / 60)
        // Part of the way after one frame, not all of it and not none of it.
        #expect(first.x > 756 + 30 && first.x < 756 + 70)
        for _ in 0..<30 { _ = laser.step(dt: 1.0 / 60) }
        #expect(abs(laser.position.x - 856) < 0.01)
    }

    @Test func easingDoesNotDependOnTheFrameRate() {
        var at60 = Laser(), at120 = Laser()
        at60.start(cursor: .zero, displays: [Self.builtIn])
        at120.start(cursor: .zero, displays: [Self.builtIn])
        at60.move(dx: 200, dy: -80)
        at120.move(dx: 200, dy: -80)
        _ = at60.step(dt: 1.0 / 60)
        _ = at120.step(dt: 1.0 / 120)
        _ = at120.step(dt: 1.0 / 120)
        #expect(abs(at60.position.x - at120.position.x) < 1e-9)
        #expect(abs(at60.position.y - at120.position.y) < 1e-9)
    }

    @Test func staysOnItsDisplay() {
        var laser = Laser()
        laser.start(cursor: CGPoint(x: 2000, y: 10), displays: [Self.builtIn, Self.projector])
        laser.move(dx: -5000, dy: -5000)
        _ = laser.step(dt: 1)
        #expect(laser.position == CGPoint(x: 1512 + Laser.margin, y: Laser.margin))
        laser.move(dx: 99999, dy: 99999)
        _ = laser.step(dt: 1)
        #expect(laser.position == CGPoint(x: 1512 + 1920 - Laser.margin, y: 1080 - Laser.margin))
    }

    @Test func comesBackFromTheEdgeAsSoonAsTheMotionReverses() {
        var laser = Laser()
        laser.start(cursor: .zero, displays: [Self.builtIn])
        laser.move(dx: 5000, dy: 0)
        laser.move(dx: -10, dy: 0)
        _ = laser.step(dt: 1)
        #expect(abs(laser.position.x - (1512 - Laser.margin - 10)) < 1e-6)
    }

    @Test func ignoresMotionWhileHidden() {
        var laser = Laser()
        laser.move(dx: 10, dy: 10)
        #expect(laser.step(dt: 1) == .zero)
    }

    @Test func fallsBackToTheFirstDisplayWhenTheCursorIsOnNone() {
        var laser = Laser()
        laser.start(cursor: CGPoint(x: -50, y: -50), displays: [Self.builtIn, Self.projector])
        #expect(laser.display == Self.builtIn)
    }
}
