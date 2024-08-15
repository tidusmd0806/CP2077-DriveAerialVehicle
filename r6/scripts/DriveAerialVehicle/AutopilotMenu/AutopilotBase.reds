// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class AutopilotBase extends inkCustomController {
	protected let m_root: wref<inkFlex>;
	protected let m_container: wref<inkCanvas>;
	protected let m_favorite_list: wref<FavoriteList>;
	protected let m_buttonHints: wref<ButtonHintsEx>;
	protected let m_areaSize: Vector2;
	protected let m_footer: ref<InGamePopupFooter>;

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

		let base = new inkVerticalPanel();
		base.SetName(n"base");
		base.SetFitToContent(false);
		base.SetAnchor(inkEAnchor.Fill);
		base.SetChildOrder(inkEChildOrder.Forward);
		base.Reparent(autopilot_menu);

		let base_top_title = new inkCanvas();
		base_top_title.SetName(n"base_top_title");
		base_top_title.SetAnchor(inkEAnchor.Fill);
		base_top_title.SetSize(2000, 80);
		base_top_title.Reparent(base);

		let base_top = new inkHorizontalPanel();
		base_top.SetName(n"base_top");
		base_top.SetFitToContent(false);
		base_top.SetAnchor(inkEAnchor.Fill);
		base_top.SetChildOrder(inkEChildOrder.Forward);
		base_top.SetSize(2000, 120);
		base_top.Reparent(base);

		let base_top_left = new inkCanvas();
		base_top_left.SetName(n"base_top_left");
		base_top_left.SetAnchor(inkEAnchor.Fill);
		base_top_left.SetSize(1500, 120);
		base_top_left.Reparent(base_top);

		let base_top_right = new inkCanvas();
		base_top_right.SetName(n"base_top_right");
		base_top_right.SetAnchor(inkEAnchor.Fill);
		base_top_right.SetSize(500, 120);
		base_top_right.Reparent(base_top);

		let base_middle_title = new inkCanvas();
		base_middle_title.SetName(n"base_middle_title");
		base_middle_title.SetAnchor(inkEAnchor.Fill);
		base_middle_title.SetSize(2000, 80);
		base_middle_title.Reparent(base);

		let base_middle = new inkHorizontalPanel();
		base_middle.SetName(n"base_middle");
		base_middle.SetFitToContent(false);
		base_middle.SetAnchor(inkEAnchor.Fill);
		base_middle.SetChildOrder(inkEChildOrder.Forward);
		base_middle.SetSize(2000, 550);
		base_middle.Reparent(base);

		let base_middle_left = new inkCanvas();
		base_middle_left.SetName(n"base_middle_left");
		base_middle_left.SetAnchor(inkEAnchor.Fill);
		base_middle_left.SetSize(300, 550);
		base_middle_left.Reparent(base_middle);

		let base_middle_right = new inkCanvas();
		base_middle_right.SetName(n"base_middle_right");
		base_middle_right.SetAnchor(inkEAnchor.Fill);
		base_middle_right.SetSize(1700, 550);
		base_middle_right.Reparent(base_middle);

		let base_bottom_title = new inkCanvas();
		base_bottom_title.SetName(n"base_bottom_title");
		base_bottom_title.SetAnchor(inkEAnchor.Fill);
		base_bottom_title.SetSize(2000, 80);
		base_bottom_title.Reparent(base);

		let base_bottom = new inkVerticalPanel();
		base_bottom.SetName(n"base_bottom");
		base_bottom.SetFitToContent(false);
		base_bottom.SetAnchor(inkEAnchor.Fill);
		base_bottom.SetChildOrder(inkEChildOrder.Forward);
		base_bottom.SetSize(2000, 340);
		base_bottom.Reparent(base);

		let base_bottom_top = new inkCanvas();
		base_bottom_top.SetName(n"base_bottom_top");
		base_bottom_top.SetAnchor(inkEAnchor.Fill);
		base_bottom_top.SetSize(2000, 170);
		base_bottom_top.Reparent(base_bottom);

		let base_bottom_bottom = new inkCanvas();
		base_bottom_bottom.SetName(n"base_bottom_bottom");
		base_bottom_bottom.SetAnchor(inkEAnchor.Fill);
		base_bottom_bottom.SetSize(2000, 170);
		base_bottom_bottom.Reparent(base_bottom);

		let top_title = TitleText.Create();
		top_title.SetText("Destination");
		top_title.Reparent(base_top_title);

		let Middle_title = TitleText.Create();
		Middle_title.SetText("Favorite Locations");
		Middle_title.Reparent(base_middle_title);

		let bottom_title = TitleText.Create();
		bottom_title.SetText("Register Location at Current Position");
		bottom_title.Reparent(base_bottom_title);

		let favorite_list = FavoriteList.Create();
		favorite_list.SetGameController(this);
		favorite_list.Reparent(base_middle_right);

		let register_button = RegisterButton.Create();
		register_button.SetFooter(this.m_footer);
		register_button.SetGameController(this);
		register_button.Reparent(base_bottom_bottom);

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

	public func SetFooter(footer: ref<InGamePopupFooter>) {
		this.m_footer = footer;
	}

	public static func Create() -> ref<AutopilotBase> {
		let self = new AutopilotBase();
		self.CreateInstance();

		return self;
	}
}