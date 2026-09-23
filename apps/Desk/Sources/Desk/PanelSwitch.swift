import CoreGraphics
import DeskRule
import Foundation

struct PanelSwitch {
    static let builtinPanelIdOnAppleSilicon: CGDirectDisplayID = 1

    let state = DeskState()
    let keyboard = KeyboardLight()

    func turnPanelOn(because reason: String) {
        let id = state.panelId ?? Self.builtinPanelIdOnAppleSilicon
        let result = Panel.setEnabled(true, display: id)
        giveTheKeyboardItsLightBack()
        state.record("panel-on reason=\(reason) display=\(id) result=\(result)")
    }

    func turnPanelOff(_ panel: DisplayFacts, because reason: String) {
        state.rememberPanelId(panel.id)
        if state.keyboardBeforeDesk == nil {
            state.rememberKeyboardBeforeDesk(keyboard.current())
        }
        keyboard.turnOff()
        let result = Panel.setEnabled(false, display: panel.id)
        if result != "ok" { giveTheKeyboardItsLightBack() }
        state.record("panel-off reason=\(reason) display=\(panel.id) result=\(result)")
    }

    func giveTheKeyboardItsLightBack() {
        guard let before = state.keyboardBeforeDesk else { return }
        keyboard.apply(before)
        state.forgetKeyboardBeforeDesk()
    }

    func keepKeyboardDarkWhilePanelIsOff() {
        if state.keyboardBeforeDesk != nil { keyboard.turnOff() }
    }
}
