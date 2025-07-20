// This code was created based on psiberx's CodeWare SimpleButton. (https://github.com/psiberx/cp2077-codeware/blob/main/scripts/UI/Buttons/SimpleButton.reds)

module DAV.AutopilotMenu
import Codeware.UI.*

public class CustomSimpleButton extends SimpleButton {
    public func GetRootComponent() -> wref<inkCompoundWidget> {
        return this.m_root;
    }

    public func GetBackgroundImage() -> wref<inkImage> {
        return this.m_bg;
    }

    public func GetFillImage() -> wref<inkImage> {
        return this.m_fill;
    }

    public func GetFrameImage() -> wref<inkImage> {
        return this.m_frame;
    }

    public func GetLabel() -> wref<inkText> {
        return this.m_label;
    }

    public static func Create() -> ref<CustomSimpleButton> {
       let self: ref<CustomSimpleButton> = new CustomSimpleButton();
        self.CreateInstance();
        return self;
    }
}