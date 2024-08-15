// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class MainContents extends inkCustomController {
	protected let m_root: wref<inkFlex>;
	protected let m_container: wref<inkCanvas>;
	protected let m_favorite_list: wref<FavoriteList>;
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

		let column_1 = new inkHorizontalPanel();
		column_1.SetFitToContent(true);
		column_1.SetAnchor(inkEAnchor.Fill);
		column_1.Reparent(autopilot_menu);

		let canvas_2 = new inkCanvas();
		canvas_2.SetName(n"canvas_2");
		canvas_2.SetAnchor(inkEAnchor.Fill);
		canvas_2.SetSize(500, 500);
		canvas_2.Reparent(column_1);

		let canvas_3 = new inkCanvas();
		canvas_3.SetName(n"canvas_3");
		canvas_3.SetAnchor(inkEAnchor.Fill);
		canvas_3.SetSize(500, 500);
		canvas_3.Reparent(column_1);

		let favorite_list = FavoriteList.Create();
		favorite_list.SetGameController(this);
		favorite_list.Reparent(canvas_2);

		let register_button = RegisterButton.Create();
		register_button.SetGameController(this);
		register_button.Reparent(canvas_3);

		this.m_root = autopilot_menu;
		this.m_container = container;
		this.m_favorite_list = favorite_list;

		this.SetRootWidget(autopilot_menu);
		this.SetContainerWidget(container);
    }

	public func GetFavoriteList() -> wref<FavoriteList> {
		return this.m_favorite_list;
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