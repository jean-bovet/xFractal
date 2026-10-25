import SwiftUI
import UIKit
@testable import xFractal

enum GalleryAppearance: String {
    case light, dark

    var style: UIUserInterfaceStyle { self == .light ? .light : .dark }
}

/// What a builder returns: a fresh store (read back through the production `load()`) and the view that shows it.
struct BuiltScenario {
    let store: StateStore
    let suiteName: String
    let defaults: UserDefaults
    let makeView: (_ sheetProbe: AnyView?, _ foldRegions: [CGRect]?) -> ContentView
}

struct GalleryScenario {
    let fixture: GalleryFixture

    var name: String { fixture.name }
    var slug: String { fixture.slug }
    var group: String { fixture.group }

    /// Fresh per call and per appearance: its own `UserDefaults` suite (persistent domain removed first), seeded with the
    /// production encoding under the production keys, and a new `StateStore` that reads it through `load()`, as a
    /// relaunch does. Nothing is shared between calls.
    func build(_ appearance: GalleryAppearance) -> BuiltScenario {
        let suiteName = "gallery.\(slug).\(appearance.rawValue)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let encoder = JSONEncoder()
        if let state = fixture.state {
            defaults.set(try! encoder.encode(state), forKey: StateStore.stateKey)
        }
        if !fixture.journal.isEmpty {
            defaults.set(try! encoder.encode(fixture.journal), forKey: StateStore.journalKey)
        }
        let store = StateStore(defaults: defaults, now: { galleryFixedDate })
        let showing = fixture.sheet != .none
        return BuiltScenario(store: store, suiteName: suiteName, defaults: defaults) { probe, foldRegions in
            ContentView(store: store, showingSheet: showing, sheetProbe: probe, foldRegions: foldRegions)
        }
    }
}

enum GalleryScenarios {
    /// Every scenario, from its fixture.
    static let every: [GalleryScenario] = GalleryFixtures.all.map(GalleryScenario.init)

    /// The scenarios the snapshot test renders: all of them.
    static let all: [GalleryScenario] = every

    static func scenario(_ fragment: String) -> GalleryScenario {
        every.first { $0.name.contains(fragment) || $0.slug.contains(fragment) }!
    }
}
