import Foundation
import MetalKit
import simd
import Testing
@testable import Bubo

/// The Galassia (spec 11): a stable layout, the cache, the files listed with or without git, the camera, the search
/// and a map that draws only when it must.
@MainActor
struct GalaxyTests {
    static let files = [
        "README.md", "Package.swift",
        "Sources/App/main.swift", "Sources/App/View.swift", "Sources/App/Model/User.swift",
        "Sources/Core/Store.swift", "Sources/Core/Net/Client.swift", "Sources/Core/Net/Request.swift",
        "Tests/AppTests.swift", "docs/a.md", "docs/b.md", "docs/adr/0001.md",
    ]

    /// `count` files spread over nested folders, as a mid-sized repo has them.
    static func manyFiles(_ count: Int) -> [String] {
        (0..<count).map { index in
            "module\(index % 12)/feature\(index % 97)/part\(index % 7)/file\(index).swift"
        }
    }

    // MARK: Layout

    @Test func theSameFilesGiveTheSameLayout() {
        let layout = GalaxyLayout(files: Self.files)
        #expect(GalaxyLayout(files: Self.files.reversed()) == layout)
        #expect(GalaxyLayout(files: Self.files + Self.files) == layout)
    }

    @Test(arguments: [
        ["Sources/App/Login.swift", "Sources/App/Logout.swift"],
        ["docs/adr/0002.md"],
        ["NEWS.md", "Tests/MoreTests.swift"],
    ])
    func filesAddedToExistingFoldersMoveNoFolder(added: [String]) {
        let before = GalaxyLayout(files: Self.files)
        let after = GalaxyLayout(files: Self.files + added)
        #expect(after.clusters.map(\.path) == before.clusters.map(\.path))
        #expect(after.clusters.map(\.center) == before.clusters.map(\.center))
        #expect(after.clusters.map(\.core) == before.clusters.map(\.core))
        #expect(after.clusters.map(\.radius) == before.clusters.map(\.radius))
        #expect(after.stars.count == before.stars.count + added.count)
    }

    @Test func removedFilesMoveNoFolderThatStays() {
        let before = GalaxyLayout(files: Self.files)
        let after = GalaxyLayout(files: Self.files.filter { $0 != "Sources/Core/Store.swift" && $0 != "docs/a.md" })
        #expect(after.clusters.map(\.center) == before.clusters.map(\.center))
        #expect(after.clusters.map(\.core) == before.clusters.map(\.core))
    }

    @Test func aNewFolderMovesNoFolderBeforeItOrElsewhere() {
        let before = GalaxyLayout(files: Self.files)
        let after = GalaxyLayout(files: Self.files + ["docs/zz/new.md"])
        for cluster in before.clusters where !cluster.path.hasPrefix("docs") && cluster.path != "" {
            let moved = after.clusters.first { $0.path == cluster.path }
            #expect(moved?.center == cluster.center, "\(cluster.path) moved")
            #expect(moved?.core == cluster.core, "\(cluster.path) moved its core")
        }
    }

    @Test func siblingFoldersDoNotOverlapAndStayInsideTheirParent() throws {
        let layout = GalaxyLayout(files: Self.manyFiles(3_000))
        let byPath = Dictionary(uniqueKeysWithValues: layout.clusters.map { ($0.path, $0) })
        let siblings = Dictionary(grouping: layout.clusters.dropFirst()) { ($0.path as NSString).deletingLastPathComponent }
        for (parentPath, children) in siblings {
            let parent = try #require(byPath[parentPath])
            for child in children {
                #expect(simd_length(child.center - parent.center) + child.radius <= parent.radius + 0.001)
                #expect(simd_length(child.center - parent.core) >= GalaxyLayout.coreRadius + child.radius)
            }
            for (offset, first) in children.enumerated() {
                for second in children.dropFirst(offset + 1) {
                    #expect(simd_length(first.center - second.center) >= first.radius + second.radius - 0.001)
                }
            }
        }
    }

    @Test func starsSitInTheirFolderCore() {
        let layout = GalaxyLayout(files: Self.files)
        for star in layout.stars {
            let cluster = layout.clusters[star.cluster]
            #expect(simd_length(star.position - cluster.core) <= GalaxyLayout.coreRadius)
            #expect((star.path as NSString).deletingLastPathComponent == cluster.path)
        }
        #expect(layout.clusters[0].fileCount == Self.files.count)
    }

    @Test func aFolderHoldingOneSubfolderIsBarelyLargerThanIt() {
        let layout = GalaxyLayout(files: ["a/b/c/d/e/f/g/h/i/j/file.swift"])
        // Each level adds about its core's diameter, never doubles: ten levels stay small.
        for (outer, inner) in zip(layout.clusters, layout.clusters.dropFirst()) {
            #expect(outer.radius <= inner.radius + 2 * GalaxyLayout.coreRadius + GalaxyLayout.gap + 0.001)
        }
        #expect(layout.radius < 30)
    }

    @Test func tenThousandFilesAreLaidOutQuickly() {
        let files = Self.manyFiles(10_000)
        let elapsed = ContinuousClock().measure { _ = GalaxyLayout(files: files) }
        #expect(elapsed < .milliseconds(500))
    }

    // MARK: Cache

    @Test func theCachedFilesAreLaidOutWellWithinTheFirstImageBudget() throws {
        let folder = URL.temporaryDirectory.appending(path: "galassia-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = GalaxyCache(folder: folder)
        let project = URL(filePath: "/tmp/progetto")
        let files = Self.manyFiles(10_000).sorted()
        #expect(cache.files(of: project) == nil)
        cache.save(files, of: project)
        var layout: GalaxyLayout?
        let elapsed = ContinuousClock().measure {
            layout = cache.files(of: project).map { GalaxyLayout(files: $0) }
        }
        #expect(layout == GalaxyLayout(files: files))
        // The first image waits for this: it must leave most of the 500 ms to the map, even in Debug.
        #expect(elapsed < .milliseconds(250))
    }

    // MARK: Files

    @Test func insideGitTheFilesComeFromLsFiles() async {
        let runner = ProcessRunner { _, arguments in
            #expect(arguments.contains("ls-files"))
            return ProcessOutput(exitCode: 0, standardOutput: "b.swift\0a/c.swift\0")
        }
        let files = await GalaxyFiles.list(in: URL(filePath: "/tmp/progetto"), runner: runner)
        #expect(files == ["a/c.swift", "b.swift"])
    }

    @Test func outsideGitTheFolderIsScannedWithoutHiddenFilesAndCaches() async throws {
        let folder = URL.temporaryDirectory.appending(path: "galassia-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        for path in ["a.txt", "src/b.swift", ".hidden", ".git/config", "node_modules/x/index.js", ".build/out"] {
            let file = folder.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let runner = ProcessRunner { _, _ in
            ProcessOutput(exitCode: 128, standardOutput: "", standardError: "fatal: not a git repository")
        }
        #expect(await GalaxyFiles.list(in: folder, runner: runner) == ["a.txt", "src/b.swift"])
    }

    // MARK: Camera

    @Test func aPointAndItsPlaneCorrespond() {
        let camera = GalaxyCamera(center: SIMD2(3, -2), scale: 40)
        let size = CGSize(width: 800, height: 600)
        let plane = SIMD2<Float>(5, 1)
        let back = camera.plane(at: camera.point(for: plane, in: size), in: size)
        #expect(simd_length(back - plane) < 0.0001)
        #expect(camera.point(for: camera.center, in: size) == CGPoint(x: 400, y: 300))
    }

    @Test func zoomingKeepsThePointUnderTheCursor() {
        var camera = GalaxyCamera(center: .zero, scale: 10)
        let size = CGSize(width: 800, height: 600)
        let anchor = CGPoint(x: 600, y: 120)
        let under = camera.plane(at: anchor, in: size)
        camera.zoom(by: 3, around: anchor, in: size, minimumScale: 1)
        #expect(camera.scale == 30)
        #expect(simd_length(camera.plane(at: anchor, in: size) - under) < 0.0001)
    }

    @Test func theFittingCameraShowsTheWholeCircle() {
        let size = CGSize(width: 1000, height: 500)
        let camera = GalaxyCamera.fitting(radius: 50, in: size)
        let top = camera.point(for: SIMD2(0, -50), in: size)
        let right = camera.point(for: SIMD2(50, 0), in: size)
        #expect(top.y >= 0)
        #expect(right.x <= size.width)
    }

    /// The files of the bubo repo on 2026-10-01, where the Galassia once opened with only a handful of points.
    static func buboFiles() throws -> [String] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let list = try String(contentsOf: root.appending(path: "BuboTests/Fixtures/galassia-bubo.txt"), encoding: .utf8)
        return list.split(separator: "\n").map(String.init)
    }

    /// The map's size when the window first opens, and when the window is at its smallest first size of 900 by 600.
    @Test(arguments: [CGSize(width: GalaxyWindow.defaultSize.width - 300, height: GalaxyWindow.defaultSize.height),
                      CGSize(width: 600, height: 600)])
    func theFirstCameraShowsTheStarOfEveryFile(map size: CGSize) throws {
        let files = try Self.buboFiles()
        let model = GalaxyModel(project: URL(filePath: "/tmp/bubo"))
        model.apply(GalaxyLayout(files: files))
        model.resize(to: size)
        let bounds = CGRect(origin: .zero, size: size)
        let inView = try #require(model.layout).stars.filter { bounds.contains(model.camera.point(for: $0.position, in: size)) }
        let shown = model.areStarsLit ? inView.count : 0
        #expect(Double(shown) >= 0.95 * Double(files.count), "\(shown) of \(files.count) stars shown")
    }

    @Test func noTwoFolderNamesCoverEachOther() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/bubo"))
        model.apply(GalaxyLayout(files: try Self.buboFiles()))
        model.resize(to: CGSize(width: 800, height: 720))
        let folders = model.labels().filter { $0.kind == .folder }
        #expect(!folders.isEmpty)
        for (offset, first) in folders.enumerated() {
            for second in folders.dropFirst(offset + 1) {
                let apart = abs(first.point.x - second.point.x) >= 60 || abs(first.point.y - second.point.y) >= 14
                #expect(apart, "\(first.text) covers \(second.text)")
            }
        }
    }

    @Test func aResizeKeepsTheWholeGalassiaInViewUntilTheCameraMoves() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.manyFiles(500)))
        model.resize(to: CGSize(width: 600, height: 130))
        model.resize(to: CGSize(width: 1000, height: 800))
        let radius = model.layout?.radius ?? 0
        let center = model.layout?.center ?? .zero
        #expect(model.camera == .fitting(radius: radius, around: center, in: CGSize(width: 1000, height: 800)))
        model.pan(by: CGSize(width: 40, height: 0))
        let moved = model.camera
        model.resize(to: CGSize(width: 1200, height: 800))
        #expect(model.camera == moved)
    }

    // MARK: Model

    @Test func theSearchMatchesNamesAndPaths() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.files))
        model.query = "net/"
        #expect(model.rows.map { model.layout!.stars[$0].path } == ["Sources/Core/Net/Client.swift",
                                                                      "Sources/Core/Net/Request.swift"])
        model.query = "readme"
        #expect(model.matches.count == 1)
        model.query = ""
        #expect(model.matches.isEmpty)
        #expect(model.rows.count == Self.files.count)
    }

    @Test func selectingARowFliesToItsStar() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.files))
        model.resize(to: CGSize(width: 800, height: 600))
        let index = try #require(model.layout?.stars.firstIndex { $0.path == "docs/adr/0001.md" })
        model.select(index)
        model.advanceFlight(to: .greatestFiniteMagnitude)
        #expect(!model.isFlying)
        #expect(model.selection == index)
        #expect(model.camera.center == model.layout?.stars[index].position)
    }

    @Test func clickingAStarSelectsItsRow() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.files))
        let size = CGSize(width: 800, height: 600)
        model.resize(to: size)
        let index = try #require(model.layout?.stars.firstIndex { $0.path == "README.md" })
        let star = try #require(model.layout?.stars[index])
        model.fly(to: GalaxyCamera(center: star.position, scale: 400))
        model.advanceFlight(to: .greatestFiniteMagnitude)
        model.click(at: model.camera.point(for: star.position, in: size))
        #expect(model.selection == index)
        #expect(model.revealedInList == index)
    }

    @Test func clickingAFolderZoomsIntoIt() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.files))
        let size = CGSize(width: 800, height: 600)
        model.resize(to: size)
        let docs = try #require(model.layout?.clusters.firstIndex { $0.path == "docs" })
        let cluster = try #require(model.layout?.clusters[docs])
        let edge = cluster.center + SIMD2(cluster.radius * 0.95, 0)
        #expect(model.hit(at: model.camera.point(for: edge, in: size)) == .cluster(docs))
    }

    @Test func theLabelsNeverPassTheirLimit() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.apply(GalaxyLayout(files: Self.manyFiles(5_000)))
        model.resize(to: CGSize(width: 1600, height: 1000))
        model.query = "file"
        model.zoom(by: 4, around: CGPoint(x: 800, y: 500))
        #expect(model.labels().count <= GalaxyModel.labelLimit)
    }

    // MARK: Map

    @Test func theMapsShadersBuild() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        #expect(throws: Never.self) { _ = try GalaxyRenderer(view: MTKView(), model: model) }
    }

    @Test func aStillMapDrawsOnlyOnDemand() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        let map = GalaxyMapNSView(model: model)
        #expect(map.isPaused)
        #expect(map.enableSetNeedsDisplay)
    }

    @Test func aMapWithNoVisibleWindowDrawsNoFramesEvenWhileFlying() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        let map = GalaxyMapNSView(model: model)
        model.apply(GalaxyLayout(files: Self.files))
        map.setFrameSize(CGSize(width: 800, height: 600))
        model.fly(to: GalaxyCamera(center: SIMD2(1, 1), scale: 300))
        #expect(!map.isDrawingContinuously)
        #expect(map.isPaused)
    }
}
