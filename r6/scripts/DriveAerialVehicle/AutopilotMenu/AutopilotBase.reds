// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class AutopilotBase extends inkCustomController {
	protected let m_root: wref<inkFlex>;
	protected let m_container: wref<inkCanvas>;
	protected let m_destination: wref<Destination>;
	protected let m_favorite_list: wref<FavoriteList>;
	protected let m_register_location: wref<RegisterLocation>;
	protected let m_buttonHints: wref<ButtonHintsEx>;
	protected let m_areaSize: Vector2;
	protected let m_mappin_address: String;
	protected let m_selected_number: Int32;
	protected let m_changed_number_list: array<Bool>;

	protected cb func OnCreate() {
		let autopilot_menu = new inkFlex();
		autopilot_menu.SetName(n"AutopilotMenu");
		autopilot_menu.SetAnchor(inkEAnchor.Fill);

		let background = new inkRectangle();
		background.SetName(n"background");
		background.SetAnchor(inkEAnchor.Fill);
		background.SetMargin(new inkMargin(8.0, 8.0, 8.0, 8.0));
		background.SetTintColor(ThemeColors.BlackPearl());
		// background.SetTintColor(new HDRColor(0.055, 0.055, 0.090, 1.0));
		background.SetOpacity(0.610);
		background.Reparent(autopilot_menu);

		// let pattern = new inkImage();
		// pattern.SetName(n"pattern");
		// pattern.SetAtlasResource(r"base\\gameplay\\gui\\fullscreen\\inventory\\atlas_inventory.inkatlas");
		// pattern.SetTexturePart(n"BLUEPRINT_3slot");
		// pattern.SetBrushTileType(inkBrushTileType.Both);
		// pattern.SetTileHAlign(inkEHorizontalAlign.Center);
		// pattern.SetTileVAlign(inkEVerticalAlign.Center);
		// pattern.SetAnchor(inkEAnchor.Centered);
		// pattern.SetOpacity(0.1);
		// pattern.SetTintColor(ThemeColors.Bittersweet());
		// pattern.SetMargin(new inkMargin(8.0, 4.0, 8.0, 2.0));
		// pattern.Reparent(autopilot_menu);

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

		let base_top = new inkFlex();
		base_top.SetName(n"base_top");
		base_top.SetFitToContent(false);
		base_top.SetAnchor(inkEAnchor.Fill);
		base_top.SetSize(2000, 120);
		base_top.Reparent(base);

		let base_top_frame = LargeFrame.Create();
		base_top_frame.SetSize(1850, 120);
		base_top_frame.SetMargin(20, 0, 0, 0);
		base_top_frame.Reparent(base_top);

		let base_top_content = new inkHorizontalPanel();
		base_top_content.SetName(n"base_top_content");
		base_top_content.SetFitToContent(false);
		base_top_content.SetAnchor(inkEAnchor.Fill);
		base_top_content.SetChildOrder(inkEChildOrder.Forward);
		base_top_content.SetSize(2000, 120);
		base_top_content.Reparent(base_top);

		let base_middle_title = new inkCanvas();
		base_middle_title.SetName(n"base_middle_title");
		base_middle_title.SetAnchor(inkEAnchor.Fill);
		base_middle_title.SetSize(2000, 80);
		base_middle_title.Reparent(base);

		let base_middle = new inkFlex();
		base_middle.SetName(n"base_middle");
		base_middle.SetFitToContent(false);
		base_middle.SetAnchor(inkEAnchor.Fill);
		base_middle.SetSize(2000, 550);
		base_middle.Reparent(base);

		let base_middle_frame = LargeFrame.Create();
		base_middle_frame.SetSize(1850, 550);
		base_middle_frame.SetMargin(20, 0, 0, 0);
		base_middle_frame.Reparent(base_middle);

		let base_middle_content = new inkHorizontalPanel();
		base_middle_content.SetName(n"base_middle_content");
		base_middle_content.SetFitToContent(false);
		base_middle_content.SetAnchor(inkEAnchor.Fill);
		base_middle_content.SetChildOrder(inkEChildOrder.Forward);
		base_middle_content.SetSize(2000, 550);
		base_middle_content.Reparent(base_middle);

		let base_bottom_title = new inkCanvas();
		base_bottom_title.SetName(n"base_bottom_title");
		base_bottom_title.SetAnchor(inkEAnchor.Fill);
		base_bottom_title.SetSize(2000, 80);
		base_bottom_title.Reparent(base);

		let base_bottom = new inkFlex();
		base_bottom.SetName(n"base_bottom");
		base_bottom.SetFitToContent(false);
		base_bottom.SetAnchor(inkEAnchor.Fill);
		base_bottom.SetSize(2000, 340);
		base_bottom.Reparent(base);

		let base_bottom_frame = LargeFrame.Create();
		base_bottom_frame.SetSize(1850, 320);
		base_bottom_frame.SetMargin(20, 0, 0, 0);
		base_bottom_frame.Reparent(base_bottom);

		let base_bottom_content = new inkVerticalPanel();
		base_bottom_content.SetName(n"base_bottom_content");
		base_bottom_content.SetFitToContent(false);
		base_bottom_content.SetAnchor(inkEAnchor.Fill);
		base_bottom_content.SetChildOrder(inkEChildOrder.Forward);
		base_bottom_content.SetSize(2000, 340);
		base_bottom_content.Reparent(base_bottom);

		let top_title = TitleText.Create();
		top_title.SetText("Destination");
		top_title.Reparent(base_top_title);

		let Middle_title = TitleText.Create();
		Middle_title.SetText("Favorite Locations");
		Middle_title.Reparent(base_middle_title);

		let bottom_title = TitleText.Create();
		bottom_title.SetText("Register Location at Current Position");
		bottom_title.Reparent(base_bottom_title);

		let destination = Destination.Create(this);
		destination.SetGameController(this);
		destination.Reparent(base_top);

		let favorite_list = FavoriteList.Create(this);
		favorite_list.SetGameController(this);
		favorite_list.Reparent(base_middle);

		let register_location = RegisterLocation.Create(this);
		register_location.SetGameController(this);
		register_location.Reparent(base_bottom);

		this.m_root = autopilot_menu;
		this.m_container = container;
		this.m_destination = destination;
		this.m_favorite_list = favorite_list;
		this.m_register_location = register_location;

		this.SetRootWidget(autopilot_menu);
		this.SetContainerWidget(container);
    }

	public func GetFavoriteList() -> wref<FavoriteList> {
		return this.m_favorite_list;
	}

	public func GetHints() -> wref<ButtonHintsEx> {
		return this.m_buttonHints;
	}

	public func SetSize(areaSize: Vector2) {
		this.m_areaSize = areaSize;
	}

	public func SetHints(buttonHints: wref<ButtonHintsEx>) {
		this.m_buttonHints = buttonHints;
	}

	public static func Create() -> ref<AutopilotBase> {
		let self = new AutopilotBase();
		self.CreateInstance();

		return self;
	}

	public func SetDestination(dest_address: String, mappim_address: String, selected_number: Int32) {
		this.m_destination.SetDestination(dest_address);
		this.m_mappin_address = mappim_address;
		this.m_selected_number = selected_number;
	}

	public func SetFavoriteList(favorite_list: array<String>) {
		this.m_favorite_list.SetFavoriteList(favorite_list);
	}

	public func GetCurrentAddress() -> String {
		return this.m_register_location.GetCurrentAddress();
	}

	public func SetCurrentAddress(address: String) {
		this.m_register_location.SetCurrentAddress(address);
		
	}

	public func ResetDestination() {
		this.m_destination.SetDestination(this.m_mappin_address);
		this.m_selected_number = 0;
	}

	public func SetFavoriteToDestination(selected_number: Int32) {
		this.m_selected_number = selected_number;
		this.m_destination.SetDestination(this.m_favorite_list.GetText(selected_number - 1));
	}
}