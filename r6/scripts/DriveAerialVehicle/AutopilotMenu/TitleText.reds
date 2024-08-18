// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class TitleText extends inkText {

    public static func Create() -> ref<TitleText> {
		let self = new TitleText();
		self.SetName(n"Title");
        self.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        self.SetFontStyle(n"Medium");
        self.SetFontSize(50);
        self.SetLetterCase(textLetterCase.OriginalCase);
        self.SetFitToContent(true);
        self.SetMargin(new inkMargin(48.0, 28.0, 200.0, 6.0));
        self.SetHAlign(inkEHorizontalAlign.Left);
        self.SetVAlign(inkEVerticalAlign.Center);
        self.SetTintColor(ThemeColors.ElectricBlue());
		return self;
	}

}