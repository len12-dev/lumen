import AppKit
import Combine
import GameController
import SwiftUI

enum InputAction: Equatable {
    case up, down, left, right, confirm, back, guide, banner, prevTab, nextTab
}

/// Entrées manette (GameController) + repli clavier pour le développement.
@MainActor
final class ControllerInput: ObservableObject {
    /// Dernière action émise, consommée par les vues.
    @Published private(set) var lastAction: InputAction?
    @Published private(set) var actionID: Int = 0

    private var keyMonitor: Any?
    private var stickDirection: InputAction?
    private var repeatTask: Task<Void, Never>?

    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Ne pas avaler les touches quand un champ de texte a le focus (espace, Entrée…).
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            let action: InputAction? = switch event.keyCode {
            case 126: .up
            case 125: .down
            case 123: .left
            case 124: .right
            case 36, 49: .confirm   // Entrée / Espace
            case 53, 51: .back      // Échap / Retour arrière
            case 11: .banner        // B : modifier le jeu
            case 12: .prevTab       // Q : catégorie précédente (L1)
            case 14: .nextTab       // E : catégorie suivante (R1)
            default: nil
            }
            if let action {
                self.emit(action)
                return nil
            }
            return event
        }

        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.bind(controller) }
        }
        GCController.controllers().forEach { bind($0) }
        GCController.startWirelessControllerDiscovery {}
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in
                if y > 0.5 { self?.emit(.up) }
                else if y < -0.5 { self?.emit(.down) }
                else if x > 0.5 { self?.emit(.right) }
                else if x < -0.5 { self?.emit(.left) }
            }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.confirm) } }
        }
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.back) } }
        }
        // Stick gauche : direction dominante, avec répétition tant que le stick reste poussé.
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.updateStick(x: x, y: y) }
        }
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.prevTab) } }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.nextTab) } }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.emit(.banner) } }
        }
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            // La touche Guide est le sujet de l'overlay (jalon 2). Ici on la reçoit si l'OS la transmet.
            if pressed { Task { @MainActor in self?.emit(.guide) } }
        }
    }

    private func updateStick(x: Float, y: Float) {
        let threshold: Float = 0.5
        let direction: InputAction?
        if abs(x) < threshold && abs(y) < threshold {
            direction = nil
        } else if abs(y) > abs(x) {
            direction = y > 0 ? .up : .down
        } else {
            direction = x > 0 ? .right : .left
        }
        guard direction != stickDirection else { return }
        stickDirection = direction
        repeatTask?.cancel()
        repeatTask = nil
        guard let direction else { return }
        emit(direction)
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                self?.emit(direction)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func emit(_ action: InputAction) {
        lastAction = action
        actionID &+= 1
    }
}
