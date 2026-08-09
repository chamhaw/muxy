import AppKit
import os

private let logger = Logger(subsystem: "app.muxy", category: "KeyBindingStore")

@MainActor
@Observable
final class KeyBindingStore {
    static let shared = KeyBindingStore()

    private(set) var selectedPreset = KeymapPreset.muxyDefault
    private(set) var overrides: [KeyBinding] = []
    private(set) var bindings = KeymapPreset.muxyDefault.bindings
    private let persistence: any KeyBindingPersisting

    init(persistence: any KeyBindingPersisting = FileKeyBindingPersistence()) {
        self.persistence = persistence
        load()
    }

    func binding(for action: ShortcutAction) -> KeyBinding {
        bindings.first { $0.action == action }
            ?? KeyBinding.defaults.first { $0.action == action }
            ?? KeyBinding(action: action, combo: KeyCombo(key: "", modifiers: 0))
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        binding(for: action).combo
    }

    func updateBinding(action: ShortcutAction, combo: KeyCombo) {
        let override = KeyBinding(action: action, combo: combo)
        if let index = overrides.firstIndex(where: { $0.action == action }) {
            overrides[index] = override
        } else {
            overrides.append(override)
        }
        rebuildBindings()
        save()
    }

    func resetToDefaults() {
        overrides = []
        rebuildBindings()
        save()
    }

    func replaceBindings(_ newBindings: [KeyBinding]) {
        selectedPreset = .muxyDefault
        overrides = newBindings
        rebuildBindings()
        save()
    }

    @discardableResult
    func replaceConfiguration(_ configuration: KeyBindingConfiguration) -> KeyBindingConflict? {
        guard let conflict = configuration.conflict else {
            selectedPreset = configuration.preset
            overrides = configuration.overrides
            rebuildBindings()
            save()
            return nil
        }
        return conflict
    }

    @discardableResult
    func selectPreset(_ preset: KeymapPreset) -> KeyBindingConflict? {
        guard selectedPreset != preset else { return nil }
        let configuration = KeyBindingConfiguration(preset: preset, overrides: overrides)
        guard let conflict = configuration.conflict else {
            selectedPreset = preset
            rebuildBindings()
            save()
            return nil
        }
        return conflict
    }

    private func applyConfiguration(_ configuration: KeyBindingConfiguration) {
        selectedPreset = configuration.preset
        overrides = configuration.overrides
        rebuildBindings()
    }

    func resetBinding(action: ShortcutAction) {
        overrides.removeAll { $0.action == action }
        rebuildBindings()
        save()
    }

    func isRegisteredShortcut(event: NSEvent, scopes: Set<ShortcutScope>) -> Bool {
        action(for: event, scopes: scopes) != nil
    }

    func action(for event: NSEvent, scopes: Set<ShortcutScope>) -> ShortcutAction? {
        let normalizedKey = KeyCombo.normalized(
            key: event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode
        )
        let flags = event.modifierFlags.intersection(KeyCombo.supportedModifierMask).rawValue
        return ShortcutAction.allCases.first { action in
            guard scopes.contains(action.scope) else { return false }
            let combo = combo(for: action)
            guard combo.isAssigned else { return false }
            return combo.key == normalizedKey && combo.modifiers == flags
        }
    }

    func conflictingAction(for combo: KeyCombo, excluding: ShortcutAction) -> ShortcutAction? {
        conflictingAction(for: combo, excluding: Optional(excluding))
    }

    func conflictingAction(for combo: KeyCombo, excluding: ShortcutAction?) -> ShortcutAction? {
        bindings.first { binding in
            guard binding.combo.isAssigned else { return false }
            if let excluding {
                return binding.combo == combo && binding.action != excluding
            }
            return binding.combo == combo
        }?.action
    }

    private func load() {
        do {
            let configuration = try persistence.loadConfiguration()
            guard configuration.conflict == nil else {
                logger.error("Failed to load key bindings: duplicate shortcut assignments")
                applyConfiguration(KeyBindingConfiguration())
                return
            }
            applyConfiguration(configuration)
        } catch {
            logger.error("Failed to load key bindings: \(error.localizedDescription)")
            selectedPreset = .muxyDefault
            overrides = []
            rebuildBindings()
        }
    }

    private func save() {
        do {
            try persistence.saveConfiguration(KeyBindingConfiguration(preset: selectedPreset, overrides: overrides))
            SettingsJSONStore.syncUserSettingsFileWithCurrentSettings()
        } catch {
            logger.error("Failed to save key bindings: \(error.localizedDescription)")
        }
    }

    private func rebuildBindings() {
        bindings = KeyBindingConfiguration(preset: selectedPreset, overrides: overrides).effectiveBindings
    }
}
