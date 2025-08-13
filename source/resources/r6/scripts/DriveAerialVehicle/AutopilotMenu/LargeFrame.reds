// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class LargeFrame extends inkImage {

    public static func Create() -> ref<LargeFrame> {
		let self = new LargeFrame();
		self.SetName(n"LargeFrame");
		self.SetAtlasResource(r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas");
		self.SetTexturePart(n"button_big2_fg");
		self.SetNineSliceScale(true);
		self.SetNineSliceGrid(new inkMargin(24, 24, 24, 24));
        self.SetHAlign(inkEHorizontalAlign.Center);
		self.SetVAlign(inkEVerticalAlign.Center);
		self.SetAnchor(inkEAnchor.Fill);
		self.SetOpacity(0.5);
		self.SetTintColor(ThemeColors.Bittersweet());
		return self;
	}

}