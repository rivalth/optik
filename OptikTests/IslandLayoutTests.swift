import AppKit
import OptikCore
import Testing
@testable import Optik

/// Values from a 13" MacBook Air: 1470 × 956 pt, 179 × 32 pt notch.
private let builtIn = IslandScreen(
    frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
    notch: CGRect(x: 646, y: 924, width: 179, height: 32),
    displayID: 1, isBuiltIn: true)

/// A 27" display above and to the right, no notch.
private let external = IslandScreen(
    frame: CGRect(x: 1470, y: 400, width: 2560, height: 1440),
    notch: nil, displayID: 2, isBuiltIn: false)

struct IslandLayoutTests {
    @Test func idleIslandHangsFromTheNotchCenter() {
        let frame = IslandLayout.islandFrame(DesignTokens.Island.idle, on: builtIn)
        #expect(frame.width == 312)
        #expect(frame.height == 38)
        #expect(frame.maxY == 956)
        #expect(abs(frame.midX - builtIn.notch!.midX) <= 0.5)
    }

    @Test func wingsLeaveRoomBesideTheNotch() {
        let frame = IslandLayout.islandFrame(DesignTokens.Island.idle, on: builtIn)
        let notch = builtIn.notch!
        // Coop on the left wing (16 + 48 × 0.44 ≈ 37 pt), status on the right wing.
        #expect(notch.minX - frame.minX >= 56)
        #expect(frame.maxX - notch.maxX >= 56)
    }

    @Test func veryWideNotchWidensTheIsland() {
        var wide = builtIn
        wide.notch = CGRect(x: 600, y: 924, width: 260, height: 32)
        let frame = IslandLayout.islandFrame(DesignTokens.Island.idle, on: wide)
        #expect(abs(frame.width - 372) < 0.001, "width \(frame.width.description)")
        #expect(IslandLayout.islandFrame(DesignTokens.Island.reply, on: wide).width == 480)
    }

    @Test func withoutANotchItFloatsAsAPill() {
        let frame = IslandLayout.islandFrame(DesignTokens.Island.idle, on: external)
        #expect(frame.maxY == external.frame.maxY - IslandLayout.floatingInset)
        #expect(abs(frame.midX - external.frame.midX) <= 0.5)
    }

    @Test func closedPanelIsExactlyTheIsland() {
        let island = IslandLayout.islandFrame(DesignTokens.Island.idle, on: builtIn)
        #expect(IslandLayout.panelFrame(DesignTokens.Island.idle, on: builtIn, withMargin: false) == island)
    }

    @Test func openPanelLeavesRoomForTheOvershoot() {
        let island = IslandLayout.islandFrame(DesignTokens.Island.reply, on: builtIn)
        let panel = IslandLayout.panelFrame(DesignTokens.Island.reply, on: builtIn, withMargin: true)
        #expect(panel.contains(island))
        #expect(panel.maxY == island.maxY)
        #expect(panel.minX == island.minX - IslandLayout.overshootMargin)
        #expect(panel.minY == island.minY - IslandLayout.overshootMargin)
        #expect(abs(panel.midX - island.midX) < 0.01)
    }

    @Test func prefersTheBuiltInScreen() {
        #expect(IslandLayout.preferredScreen([external, builtIn]) == builtIn)
    }

    @Test func lidClosedMovesToTheMenuBarScreen() {
        #expect(IslandLayout.preferredScreen([external]) == external)
        #expect(IslandLayout.preferredScreen([]) == nil)
    }
}

struct FullScreenMonitorTests {
    @Test func fullScreenWindowCovers() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(FullScreenMonitor.covers(screen, screen))
        #expect(FullScreenMonitor.covers(screen.insetBy(dx: -0.5, dy: -0.5), screen))
    }

    @Test func zoomedWindowBelowTheMenuBarDoesNotCover() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let zoomed = CGRect(x: 0, y: 32, width: 1470, height: 924)
        #expect(!FullScreenMonitor.covers(zoomed, screen))
    }

    @Test func menuBarAndOverlaysAreIgnored() {
        #expect(FullScreenMonitor.contentLayers.contains(0))
        #expect(FullScreenMonitor.contentLayers.contains(Int(CGWindowLevelForKey(.floatingWindow))))
        #expect(!FullScreenMonitor.contentLayers.contains(Int(CGWindowLevelForKey(.dockWindow))))
        #expect(!FullScreenMonitor.contentLayers.contains(Int(CGWindowLevelForKey(.mainMenuWindow))))
        #expect(!FullScreenMonitor.contentLayers.contains(Int(CGWindowLevelForKey(.screenSaverWindow))))
    }
}
