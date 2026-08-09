import Foundation

protocol KeyBindingPersisting {
    func loadConfiguration() throws -> KeyBindingConfiguration
    func saveConfiguration(_ configuration: KeyBindingConfiguration) throws
}

final class FileKeyBindingPersistence: KeyBindingPersisting {
    private let fileURL: URL
    private let writer: CodableFileStore<KeyBindingConfiguration>

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "keybindings.json")) {
        self.fileURL = fileURL
        writer = CodableFileStore(
            fileURL: fileURL,
            options: CodableFileStoreOptions(
                prettyPrinted: true,
                sortedKeys: true,
                filePermissions: FilePermissions.privateFile
            )
        )
    }

    func loadConfiguration() throws -> KeyBindingConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return KeyBindingConfiguration() }
        let data = try Data(contentsOf: fileURL)
        if let configuration = try? JSONDecoder().decode(KeyBindingConfiguration.self, from: data) {
            return configuration
        }
        let containers = try JSONDecoder().decode([SafeKeyBinding].self, from: data)
        return KeyBindingConfiguration(
            preset: .muxyDefault,
            overrides: Self.legacyOverrides(from: containers.compactMap(\.binding))
        )
    }

    func saveConfiguration(_ configuration: KeyBindingConfiguration) throws {
        try writer.save(configuration)
    }

    private static func mergeWithDefaults(_ saved: [KeyBinding]) -> [KeyBinding] {
        var savedByAction: [ShortcutAction: KeyBinding] = [:]
        for binding in saved {
            savedByAction[binding.action] = binding
        }
        migrateComposerVoiceDefaultToLegacy(in: &savedByAction)
        var claimedCombos = Set(savedByAction.values.map(\.combo).filter(\.isAssigned))
        return KeyBinding.defaults.map { defaultBinding in
            if let savedBinding = savedByAction[defaultBinding.action] {
                return savedBinding
            }
            guard defaultBinding.combo.isAssigned else { return defaultBinding }
            guard !claimedCombos.contains(defaultBinding.combo) else {
                return KeyBinding(action: defaultBinding.action, combo: KeyCombo(key: "", modifiers: 0))
            }
            claimedCombos.insert(defaultBinding.combo)
            return defaultBinding
        }
    }

    private static func legacyOverrides(from saved: [KeyBinding]) -> [KeyBinding] {
        let defaultsByAction = Dictionary(uniqueKeysWithValues: KeyBinding.defaults.map { ($0.action, $0) })
        return mergeWithDefaults(saved).filter { binding in
            defaultsByAction[binding.action]?.combo != binding.combo
        }
    }

    private static func migrateComposerVoiceDefaultToLegacy(in bindings: inout [ShortcutAction: KeyBinding]) {
        guard bindings[.toggleComposerVoice]?.combo == KeyCombo(key: "i", command: true, shift: true),
              bindings[.toggleVoiceRecording]?.combo.isAssigned != true
        else { return }
        bindings[.toggleComposerVoice] = KeyBinding(
            action: .toggleComposerVoice,
            combo: KeyCombo(key: "", modifiers: 0)
        )
        bindings[.toggleVoiceRecording] = KeyBinding(
            action: .toggleVoiceRecording,
            combo: KeyCombo(key: "i", command: true, shift: true)
        )
    }

    private struct SafeKeyBinding: Codable {
        let binding: KeyBinding?

        init(from decoder: Decoder) throws {
            binding = try? KeyBinding(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try binding?.encode(to: encoder)
        }
    }
}
