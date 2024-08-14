// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module AutopilotMenu
import Codeware.UI.*

public class MainContents extends inkCustomController {
	protected let m_root: wref<inkFlex>;
	protected let m_container: wref<inkCanvas>;
	protected let m_history: wref<History>;
	protected let m_buttonHints: wref<ButtonHintsEx>;
	protected let m_areaSize: Vector2;

	protected cb func OnCreate() {
		let autopilot_menu = new inkFlex();
		autopilot_menu.SetName(n"AutopilotMenu");
		autopilot_menu.SetAnchor(inkEAnchor.Fill);

		let background = new inkRectangle();
		background.SetName(n"background");
		background.SetAnchor(inkEAnchor.Fill);
		background.SetMargin(new inkMargin(8.0, 8.0, 8.0, 8.0));
		// background.SetTintColor(ThemeColors.PureBlack());
		background.SetTintColor(new HDRColor(0.055, 0.055, 0.090, 1.0));
		background.SetOpacity(0.610);
		background.Reparent(autopilot_menu);

		let emblem = new inkImage();
		emblem.SetName(n"emblem");
		emblem.SetAtlasResource(r"base\\gameplay\\gui\\common\\icons\\weapon_manufacturers.inkatlas");
		emblem.SetTexturePart(n"rayfield");
		emblem.SetContentHAlign(inkEHorizontalAlign.Center);
		emblem.SetContentVAlign(inkEVerticalAlign.Center);
		// emblem.SetBrushTileType(inkBrushTileType.Both);
		// emblem.SetTileHAlign(inkEHorizontalAlign.Center);
		// emblem.SetTileVAlign(inkEVerticalAlign.Center);
		emblem.SetAnchor(inkEAnchor.Centered);
		emblem.SetOpacity(0.1);
		emblem.SetTintColor(ThemeColors.Bittersweet());
		emblem.SetMargin(new inkMargin(8.0, 4.0, 8.0, 2.0));
		emblem.Reparent(autopilot_menu);

		let frame = new inkImage();
		frame.SetName(n"frame");
		frame.SetAtlasResource(r"base\\gameplay\\gui\\fullscreen\\inventory\\inventory4_atlas.inkatlas");
		frame.SetTexturePart(n"itemGridFrame3Big");
		frame.SetNineSliceScale(true);
		frame.SetNineSliceGrid(new inkMargin(24, 24, 24, 24));
		frame.SetAnchor(inkEAnchor.Fill);
		frame.SetOpacity(0.5);
		frame.SetTintColor(ThemeColors.Bittersweet());
		frame.Reparent(autopilot_menu);

		let container = new inkCanvas();
		container.SetName(n"container");
		container.SetAnchor(inkEAnchor.Fill);
		container.Reparent(autopilot_menu);

		let history = History.Create(inkEAnchor.RightFillVerticaly);
		history.SetGameController(this);
		history.Reparent(autopilot_menu);

		this.m_root = autopilot_menu;
		this.m_container = container;
		this.m_history = history;

		this.SetRootWidget(autopilot_menu);
		this.SetContainerWidget(container);
    }

	public func GetHistory() -> wref<History> {
		return this.m_history;
	}

	public func SetSize(areaSize: Vector2) {
		this.m_areaSize = areaSize;
	}

	public static func Create() -> ref<MainContents> {
		let self = new MainContents();
		self.CreateInstance();

		return self;
	}
}