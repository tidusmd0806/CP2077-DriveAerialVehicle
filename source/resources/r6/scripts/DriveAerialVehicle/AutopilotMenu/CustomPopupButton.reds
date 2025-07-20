// This code was created based on psiberx's CodeWare PopupButton. (https://github.com/psiberx/cp2077-codeware/blob/main/scripts/UI/Buttons/PopupButton.reds)

module DAV.AutopilotMenu
import Codeware.UI.*

public class CustomPopupButton extends PopupButton {
    public func GetRootComponent() -> wref<inkCompoundWidget> {
        return this.m_root;
    }

    public func GetBackgroundImage() -> wref<inkImage> {
        return this.m_bg;
    }

    public func GetFrameImage() -> wref<inkImage> {
        return this.m_frame;
    }

    public func GetInputController() -> wref<inkInputDisplayController> {
        return this.m_input;
    }

    public func GetLabel() -> wref<inkText> {
        return this.m_label;
    }

    public static func Create() -> ref<CustomPopupButton> {
       let self: ref<CustomPopupButton> = new CustomPopupButton();
        self.CreateInstance();
        return self;
    }
}