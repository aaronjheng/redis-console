import Observation

@MainActor
@Observable
class TabManager {
    var tabStates: [ConnectionState] = []

    func createTab() -> ConnectionState {
        let state = ConnectionState()
        tabStates.append(state)
        return state
    }

    func closeTab(_ state: ConnectionState) {
        state.disconnect()
        tabStates.removeAll { $0.id == state.id }
    }

    func tabIndex(for state: ConnectionState) -> Int? {
        tabStates.firstIndex(where: { $0.id == state.id })
    }
}
