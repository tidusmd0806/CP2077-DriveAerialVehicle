// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import DAV.*
import Codeware.UI.*

public class FavoriteList extends inkCustomController {
	protected let m_root: wref<inkCanvas>;
	protected let m_list: wref<inkVerticalPanel>;
	protected let m_autopilot_base: ref<AutopilotBase>;
	protected let m_row_arr: array<ref<inkHorizontalPanel>>;
	protected let m_text_arr: array<ref<inkText>>;

	protected cb func OnCreate() {
		let root = new inkCanvas();
		root.SetName(n"FavoriteList");
		root.SetAnchor(inkEAnchor.Fill);
		root.SetSize(2000, 550);
		root.SetChildOrder(inkEChildOrder.Forward);

		let list = new inkVerticalPanel();
		list.SetName(n"list");
		list.SetAnchor(inkEAnchor.Fill);
		list.SetMargin(30, 20, 0, 0);
		list.SetChildOrder(inkEChildOrder.Forward);
		list.SetChildMargin(new inkMargin(0, 0, 0, 5));
		list.SetOpacity(0.6);
		list.Reparent(root);

		this.m_root = root;
		this.m_list = list;

		this.CreateFavoriteList();

		this.SetRootWidget(root);

	}

	protected func CreateFavoriteList() {		

		let row_arr = [new inkHorizontalPanel(), new inkHorizontalPanel(), new inkHorizontalPanel(), new inkHorizontalPanel(), new inkHorizontalPanel()];
		let text_arr = [new inkText(), new inkText(), new inkText(), new inkText(), new inkText()];

		let i = 0;
		while i < 5 {
			let text = ToString(i + 1);

			row_arr[i].SetName(StringToName("Column" + text));
			row_arr[i].SetSize(2000, 100);
			row_arr[i].SetMargin(30, 0, 0, 0);
			row_arr[i].SetAnchor(inkEAnchor.Fill);
			row_arr[i].SetChildOrder(inkEChildOrder.Forward);
			row_arr[i].SetOpacity(0.6);
			row_arr[i].Reparent(this.m_list);

			let button = CustomSimpleButton.Create();
			button.SetName(StringToName("Button" + text));
			button.GetRootComponent().SetSize(300, 100);
			button.SetText(text);
			button.ToggleAnimations(true);
			button.ToggleSounds(true);
			button.Reparent(row_arr[i]);

			let canvas = new inkCanvas();
			canvas.SetName(StringToName("Canvas" + text));
			canvas.SetSize(1600, 100);
			canvas.SetMargin(30, 0, 0, 0);
			canvas.SetAnchor(inkEAnchor.Fill);
			canvas.Reparent(row_arr[i]);

			text_arr[i].SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
			text_arr[i].SetFontStyle(n"Medium");
			text_arr[i].SetFontSize(30);
			text_arr[i].SetMargin(0, 30, 0, 0);
			text_arr[i].SetTintColor(ThemeColors.Bittersweet());
			text_arr[i].SetText(text);
			text_arr[i].Reparent(canvas);

			i += 1;
		}

		this.m_row_arr = row_arr;
		this.m_text_arr = text_arr;

	}

	protected cb func OnInitialize() {
		let i = 0;
		while i < 5 {
			this.RegisterListeners(this.m_row_arr[i]);
			i += 1;
		}
	}

    protected func RegisterListeners(container: wref<inkCompoundWidget>) {
		let childIndex = 0;
		let numChildren = container.GetNumChildren();

		while childIndex < numChildren {
			let widget = container.GetWidgetByIndex(childIndex);
			let button = widget.GetController() as CustomButton;

			if IsDefined(button) {
				button.RegisterToCallback(n"OnBtnClick", this, n"OnClick");
				button.RegisterToCallback(n"OnRelease", this, n"OnRelease");
				button.RegisterToCallback(n"OnEnter", this, n"OnEnter");
				button.RegisterToCallback(n"OnLeave", this, n"OnLeave");
			}

			childIndex += 1;
		}
	}

    protected cb func OnClick(widget: wref<inkWidget>) -> Bool {
		let button = widget.GetController() as CustomButton;

		let button_number = button.GetText();

		this.m_autopilot_base.SetFavoriteToDestination(StringToInt(button_number));
	}

	protected cb func OnRelease(evt: ref<inkPointerEvent>) -> Bool {
		let button = evt.GetTarget().GetController() as CustomButton;

		if evt.IsAction(n"popup_moveUp") {
			button.SetDisabled(!button.IsDisabled());

			this.UpdateHints(button);

			this.PlaySound(n"MapPin", n"OnCreate");
		}
	}

	protected cb func OnEnter(evt: ref<inkPointerEvent>) -> Bool {
		let button = evt.GetTarget().GetController() as CustomButton;
		this.UpdateHints(button);
	}

	protected cb func OnLeave(evt: ref<inkPointerEvent>) -> Bool {
		this.RemoveHints();
	}

	protected func UpdateHints(button: ref<CustomButton>) {
		if button.IsEnabled() {
			this.m_autopilot_base.GetHints().AddButtonHint(n"click", this.m_autopilot_base.GetWrapper().GetTranslation("ui_popup_favorite_input_hint"));
		} else {
			this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
		}
	}

	protected func RemoveHints() {
		this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
	}

	public static func Create(autopilot_base: ref<AutopilotBase>) -> ref<FavoriteList> {
		let self = new FavoriteList();
		self.CreateInstance();
		self.m_autopilot_base = autopilot_base;

		return self;
	}

	public func GetText(index: Int32) -> String {
		return this.m_text_arr[index].GetText();
	}

	public func GetFavoriteList() -> array<String> {
		let list = ["", "", "", "", ""];
		let i = 0;
		while i < 5 {
			list[i] = this.GetText(i);
			i += 1;
		}
		return list;
	}

	public func SetText(index: Int32, text: String) {
		this.m_text_arr[index].SetText(text);
	}

	public func SetFavoriteList(favorite_list: array<String>) {
		let i = 0;
		while i < 5 {
			this.SetText(i, favorite_list[i]);
			i += 1;
		}
	}
}
