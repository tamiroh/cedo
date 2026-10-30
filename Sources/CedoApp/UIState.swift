import Foundation

struct UIState: Codable {
    enum Panel: String, Codable {
        case terminal
        case log
    }

    var folderPath: String?
    var filePaths: [String: String] = [:]
    var panel: Panel?
    var panelWidth: Double = 440
    var showsHistory = false
    var showsHiddenFiles = false

    private static let key = "uiState"

    init() {}

    // Missing keys fall back to the defaults, so a new property doesn't discard the saved state
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UIState()
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        filePaths = try container.decodeIfPresent([String: String].self, forKey: .filePaths) ?? defaults.filePaths
        panel = try container.decodeIfPresent(Panel.self, forKey: .panel)
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? defaults.panelWidth
        showsHistory = try container.decodeIfPresent(Bool.self, forKey: .showsHistory) ?? defaults.showsHistory
        showsHiddenFiles =
            try container.decodeIfPresent(Bool.self, forKey: .showsHiddenFiles) ?? defaults.showsHiddenFiles
    }

    static func load() -> UIState {
        guard let data = UserDefaults.standard.data(forKey: key),
            let state = try? JSONDecoder().decode(UIState.self, from: data)
        else { return UIState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
