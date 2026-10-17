import Combine
import Testing
@testable import Semono

struct SettingsStoreTests {
    @Test @MainActor func defaultsChangePublishesObjectWillChange() async {
        let store = SettingsStore.shared
        let original = store.showComputeColumn
        var changed = false
        let cancellable = store.objectWillChange.sink { changed = true }
        defer {
            store.showComputeColumn = original
            cancellable.cancel()
        }

        store.showComputeColumn = !original
        try? await Task.sleep(for: .milliseconds(150))
        #expect(changed)
    }
}
