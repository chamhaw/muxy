import AppKit
import Testing

@testable import Muxy

@Suite("KeyBindingStore")
@MainActor
struct KeyBindingStoreTests {
    @Test("action resolves by keyCode regardless of input layout characters")
    func actionResolvesFromKeyCode() throws {
        let persistence = StubKeyBindingPersistence(bindings: [
            KeyBinding(action: .newTab, combo: KeyCombo(key: "q", command: true))
        ])
        let store = KeyBindingStore(persistence: persistence)
        let event = try keyEvent(
            characters: "й",
            charactersIgnoringModifiers: "й",
            keyCode: 12,
            modifiers: [.command]
        )

        let action = store.action(for: event, scopes: [.mainWindow])

        #expect(action == .newTab)
    }

    @Test("action respects shortcut scope filtering")
    func actionRespectsScopeFiltering() throws {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(bindings: KeyBinding.defaults))
        let event = try keyEvent(
            characters: "R",
            charactersIgnoringModifiers: "r",
            keyCode: 15,
            modifiers: [.command, .shift]
        )

        #expect(store.action(for: event, scopes: [.global]) == .reloadConfig)
        #expect(store.action(for: event, scopes: [.mainWindow]) == nil)
    }

    @Test("action resolves Cmd+Backtick to toggle extension console")
    func actionResolvesToggleExtensionConsole() throws {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(bindings: KeyBinding.defaults))
        let event = try keyEvent(
            characters: "`",
            charactersIgnoringModifiers: "`",
            keyCode: 50,
            modifiers: [.command]
        )

        #expect(store.action(for: event, scopes: [.mainWindow]) == .toggleExtensionConsole)
    }

    @Test("action resolves inspect element only in browser scope")
    func actionResolvesInspectElementOnlyInBrowserScope() throws {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(bindings: KeyBinding.defaults))
        let event = try keyEvent(
            characters: "i",
            charactersIgnoringModifiers: "i",
            keyCode: 34,
            modifiers: [.command, .option]
        )

        #expect(store.action(for: event, scopes: [.global, .mainWindow]) == nil)
        #expect(store.action(for: event, scopes: [.global, .mainWindow, .browser]) == .inspectElement)
    }

    @Test("action can be assigned and reset")
    func actionCanBeAssignedAndReset() {
        let persistence = StubKeyBindingPersistence(bindings: KeyBinding.defaults)
        let store = KeyBindingStore(persistence: persistence)
        let combo = KeyCombo(key: "u", command: true)

        #expect(store.combo(for: .refreshWorktrees) == KeyCombo(key: "r", command: true, option: true))

        store.updateBinding(action: .refreshWorktrees, combo: combo)

        #expect(store.combo(for: .refreshWorktrees) == combo)

        store.resetBinding(action: .refreshWorktrees)

        #expect(store.combo(for: .refreshWorktrees) == KeyCombo(key: "r", command: true, option: true))
    }

    @Test("preset changes preserve user shortcut overrides")
    func presetChangesPreserveUserShortcutOverrides() throws {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(configuration: KeyBindingConfiguration()))
        let customCombo = KeyCombo(key: "u", command: true, option: true)
        let keyCode = try #require(KeyCombo.keyCode(for: "u"))
        let nextTabEvent = try keyEvent(
            characters: "U",
            charactersIgnoringModifiers: "u",
            keyCode: keyCode,
            modifiers: [.command, .option]
        )

        store.updateBinding(action: .nextTab, combo: customCombo)
        store.selectPreset(.tabNavigation)

        #expect(store.selectedPreset == .tabNavigation)
        #expect(store.combo(for: .nextTab) == customCombo)
        #expect(store.combo(for: .previousTab) == KeyCombo(key: KeyCombo.leftArrowKey, command: true, option: true))
        #expect(store.combo(for: .focusPaneLeft).isAssigned == false)
        #expect(store.action(for: nextTabEvent, scopes: [.mainWindow]) == .nextTab)
    }

    @Test("legacy default keybindings allow preset changes")
    func legacyDefaultKeybindingsAllowPresetChanges() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let legacyBindings = KeyBinding.defaults
        try JSONEncoder().encode(legacyBindings).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))

        #expect(store.selectedPreset == .muxyDefault)
        #expect(store.overrides.isEmpty)
        #expect(store.combo(for: .nextTab) == KeyCombo(key: "]", command: true))
        #expect(store.selectPreset(.tabNavigation) == nil)
        #expect(store.combo(for: .nextTab) == KeyCombo(key: KeyCombo.rightArrowKey, command: true, option: true))
    }

    @Test("legacy custom keybindings remain overrides")
    func legacyCustomKeybindingsRemainOverrides() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let customBinding = KeyBinding(action: .nextTab, combo: KeyCombo(key: "u", command: true, option: true))
        let legacyBindings = KeyBinding.defaults.map { binding in
            binding.action == customBinding.action ? customBinding : binding
        }
        try JSONEncoder().encode(legacyBindings).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))

        #expect(store.overrides == [customBinding])
        #expect(store.selectPreset(.tabNavigation) == nil)
        #expect(store.combo(for: .nextTab) == customBinding.combo)
        #expect(store.combo(for: .previousTab) == KeyCombo(key: KeyCombo.leftArrowKey, command: true, option: true))
    }

    @Test("preset changes reject duplicate effective shortcuts")
    func presetChangesRejectDuplicateEffectiveShortcuts() {
        let duplicate = KeyBinding(
            action: .focusPaneLeft,
            combo: KeyCombo(key: KeyCombo.leftArrowKey, command: true, option: true)
        )
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(configuration: KeyBindingConfiguration(overrides: [duplicate])))

        let conflict = store.selectPreset(.tabNavigation)

        #expect(conflict?.firstAction == .focusPaneLeft)
        #expect(conflict?.secondAction == .previousTab)
        #expect(store.selectedPreset == .muxyDefault)
    }

    @Test("configuration replacement rejects duplicate effective shortcuts")
    func configurationReplacementRejectsDuplicateEffectiveShortcuts() {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(configuration: KeyBindingConfiguration()))
        let configuration = KeyBindingConfiguration(
            preset: .tabNavigation,
            overrides: [
                KeyBinding(
                    action: .focusPaneLeft,
                    combo: KeyCombo(key: KeyCombo.leftArrowKey, command: true, option: true)
                ),
            ]
        )

        let conflict = store.replaceConfiguration(configuration)

        #expect(conflict?.firstAction == .focusPaneLeft)
        #expect(conflict?.secondAction == .previousTab)
        #expect(store.selectedPreset == .muxyDefault)
        #expect(store.overrides.isEmpty)
    }

    @Test("action can be unassigned")
    func actionCanBeUnassigned() throws {
        let persistence = StubKeyBindingPersistence(bindings: KeyBinding.defaults)
        let store = KeyBindingStore(persistence: persistence)
        let combo = KeyCombo(key: "", modifiers: 0)
        let event = try keyEvent(
            characters: "r",
            charactersIgnoringModifiers: "r",
            keyCode: 15,
            modifiers: [.command, .option]
        )

        store.updateBinding(action: .refreshWorktrees, combo: combo)

        #expect(store.combo(for: .refreshWorktrees) == combo)
        #expect(store.action(for: event, scopes: [.mainWindow]) == nil)
    }

    @Test("saved custom bindings gain new default actions")
    func savedCustomBindingsGainNewDefaultActions() {
        let customOpenProject = KeyBinding(action: .openProject, combo: KeyCombo(key: "j", command: true, option: true))
        let persistence = StubKeyBindingPersistence(bindings: [customOpenProject])
        let store = KeyBindingStore(persistence: persistence)

        #expect(store.combo(for: .openProject) == customOpenProject.combo)
        #expect(store.combo(for: .refreshWorktrees) == KeyCombo(key: "r", command: true, option: true))
        #expect(store.combo(for: .recentlyRemovedProjects).isAssigned == false)
    }

    @Test("Recently Removed Projects can be assigned by the user")
    func recentlyRemovedProjectsCanBeAssigned() throws {
        let store = KeyBindingStore(persistence: StubKeyBindingPersistence(bindings: KeyBinding.defaults))
        let combo = KeyCombo(key: "u", command: true, shift: true, option: true)
        let keyCode = try #require(KeyCombo.keyCode(for: "u"))
        let event = try keyEvent(
            characters: "U",
            charactersIgnoringModifiers: "u",
            keyCode: keyCode,
            modifiers: [.command, .option, .shift]
        )

        #expect(store.action(for: event, scopes: [.mainWindow]) == nil)

        store.updateBinding(action: .recentlyRemovedProjects, combo: combo)

        #expect(store.action(for: event, scopes: [.mainWindow]) == .recentlyRemovedProjects)
    }

    @Test("new default shortcuts do not shadow saved custom bindings")
    func newDefaultShortcutsDoNotShadowSavedCustomBindings() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let savedCombo = KeyCombo(key: "n", command: true, option: true)
        let savedBinding = KeyBinding(action: .terminalOmniboxCommands, combo: savedCombo)
        let data = try JSONEncoder().encode([savedBinding])
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))
        let keyCode = try #require(KeyCombo.keyCode(for: "n"))
        let event = try keyEvent(
            characters: "n",
            charactersIgnoringModifiers: "n",
            keyCode: keyCode,
            modifiers: [.command, .option]
        )

        #expect(store.combo(for: .terminalOmniboxCommands) == savedCombo)
        #expect(store.combo(for: .createWorktree).isAssigned == false)
        #expect(store.action(for: event, scopes: [.mainWindow]) == .terminalOmniboxCommands)
    }

    @Test("legacy default voice shortcut remains assigned to legacy voice")
    func legacyDefaultVoiceShortcutRemainsAssignedToLegacyVoice() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let saved = KeyBinding.defaults
            .filter { $0.action != .toggleComposerVoice }
            .map { binding in
                guard binding.action == .toggleVoiceRecording else { return binding }
                return KeyBinding(
                    action: .toggleVoiceRecording,
                    combo: KeyCombo(key: "i", command: true, shift: true)
                )
            }
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))

        #expect(store.combo(for: .toggleComposerVoice).isAssigned == false)
        #expect(store.combo(for: .toggleVoiceRecording) == KeyCombo(key: "i", command: true, shift: true))
    }

    @Test("generated composer voice shortcut migrates back to legacy voice")
    func generatedComposerVoiceShortcutMigratesBackToLegacyVoice() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let saved = KeyBinding.defaults.map { binding in
            switch binding.action {
            case .toggleComposerVoice:
                KeyBinding(
                    action: .toggleComposerVoice,
                    combo: KeyCombo(key: "i", command: true, shift: true)
                )
            case .toggleVoiceRecording:
                KeyBinding(action: .toggleVoiceRecording, combo: KeyCombo(key: "", modifiers: 0))
            default:
                binding
            }
        }
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))

        #expect(store.combo(for: .toggleComposerVoice).isAssigned == false)
        #expect(store.combo(for: .toggleVoiceRecording) == KeyCombo(key: "i", command: true, shift: true))
    }

    @Test("custom legacy voice shortcut survives composer shortcut migration")
    func customLegacyVoiceShortcutSurvivesComposerShortcutMigration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keybindings-\(UUID().uuidString).json")
        let customLegacyCombo = KeyCombo(key: "v", command: true, option: true)
        let saved = [
            KeyBinding(action: .toggleVoiceRecording, combo: customLegacyCombo)
        ]
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = KeyBindingStore(persistence: FileKeyBindingPersistence(fileURL: url))

        #expect(store.combo(for: .toggleComposerVoice).isAssigned == false)
        #expect(store.combo(for: .toggleVoiceRecording) == customLegacyCombo)
    }

    private func keyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            throw EventCreationError()
        }
        return event
    }

    private final class StubKeyBindingPersistence: KeyBindingPersisting {
        private var storedConfiguration: KeyBindingConfiguration

        init(bindings: [KeyBinding]) {
            storedConfiguration = KeyBindingConfiguration(preset: .muxyDefault, overrides: bindings)
        }

        init(configuration: KeyBindingConfiguration) {
            storedConfiguration = configuration
        }

        func loadConfiguration() throws -> KeyBindingConfiguration {
            storedConfiguration
        }

        func saveConfiguration(_ configuration: KeyBindingConfiguration) throws {
            storedConfiguration = configuration
        }
    }

    private struct EventCreationError: Error {}
}
