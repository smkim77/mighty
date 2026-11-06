extends Control

const Rules = preload("res://scripts/card_data.gd")
const CardViewScript = preload("res://scripts/card_view.gd")

enum Phase {
	BIDDING,
	KITTY_EXCHANGE,
	PLAYING,
	ROUND_OVER
}

const PLAYER_NAMES: Array[String] = ["나 (플레이어)", "AI 민수", "AI 지영", "AI 현우", "AI 수진"]
const PLAYER_COLORS: Array[Color] = [
	Color(0.48, 0.98, 0.64),
	Color(0.45, 0.84, 1.00),
	Color(1.00, 0.58, 0.68),
	Color(0.82, 0.68, 1.00),
	Color(1.00, 0.85, 0.45)
]

const COLOR_RULING_MAIN := Color(1.00, 0.80, 0.22)
const COLOR_RULING_FRIEND := Color(1.00, 0.64, 0.26)
const COLOR_OPPOSITION := Color(0.42, 0.86, 1.00)
const COLOR_UNKNOWN_ROLE := Color(0.78, 0.86, 0.80)

const CARD_COLOR_RED := Color(0.82, 0.14, 0.18)
const CARD_COLOR_BLACK := Color(0.10, 0.12, 0.16)
const CARD_COLOR_JOKER := Color(0.48, 0.16, 0.78)
const CARD_BG_IVORY := Color(0.99, 0.985, 0.96)

var phase: Phase = Phase.BIDDING
var hands: Array = [[], [], [], [], []]
var kitty: Array = []
var captured_points: Array = [[], [], [], [], []]
var played_cards_history: Array = []
var total_scores: Array[int] = [0, 0, 0, 0, 0]

var current_bidder: int = 0
var passed_players: Array[bool] = [false, false, false, false, false]
var highest_bid: int = 0
var highest_bid_suit: int = Rules.SUIT_SPADE
var declarer_idx: int = -1
var selected_bid_suit: int = Rules.SUIT_SPADE
var selected_bid_score: int = 13

var trump_suit: int = Rules.SUIT_NONE
var contract_score: int = 13
var discard_selected_ids: Array = []
var friend_spec: Dictionary = {"type": "none", "card_id": "", "label": "미정"}
var friend_player_idx: int = -1
var friend_revealed: bool = false
var selected_friend_option: int = 0

var trick_number: int = 1
var turn_player: int = 0
var trick_leader: int = 0
var trick_plays: Array = []
var lead_info: Dictionary = {
	"lead_suit": Rules.SUIT_NONE,
	"joker_call_active": false,
	"note": ""
}
var waiting_for_human: bool = false
var round_generation: int = 0
var active_seat_idx: int = -1
var suit_regex: RegEx

var top_status_label: Label
var contract_info_label: RichTextLabel
var team_score_label: Label
var played_cards_btn: Button
var log_label: RichTextLabel
var player_seat_panels: Array[PanelContainer] = []
var player_name_labels: Array[Label] = []
var player_role_labels: Array[Label] = []
var player_card_count_labels: Array[Label] = []
var player_captured_boxes: Array[Control] = []
var player_bubble_labels: Array[RichTextLabel] = []

var trick_slots: Array[VBoxContainer] = []
var trick_info_banner: RichTextLabel
var hand_container: HBoxContainer
var hand_hint_label: Label

var center_modal: PanelContainer
var modal_vbox: VBoxContainer
var help_panel: PanelContainer
var played_cards_panel: PanelContainer
var played_cards_vbox: VBoxContainer

func _ready() -> void:
	randomize()
	suit_regex = RegEx.new()
	suit_regex.compile("(스페이드\\s*♠|다이아몬드\\s*◆|하트\\s*♥|클로버\\s*♣|조커\\s*★|★조커|스페이드|다이아몬드|하트|클로버|[♠◆♥♣](?:10|[2-9JQKA])?)")
	_setup_korean_font()
	_build_ui()
	start_new_round()

func _setup_korean_font() -> void:
	if ResourceLoader.exists("res://fonts/NanumSquareRoundB.ttf"):
		var kr_font: FontFile = load("res://fonts/NanumSquareRoundB.ttf")
		var fb: Array[Font] = [ThemeDB.fallback_font]
		kr_font.fallbacks = fb
		var custom_theme := Theme.new()
		custom_theme.default_font = kr_font
		theme = custom_theme
	else:
		var sys_font := SystemFont.new()
		sys_font.font_names = PackedStringArray([
			"Malgun Gothic",
			"맑은 고딕",
			"Apple SD Gothic Neo",
			"Noto Sans CJK KR",
			"Noto Sans KR",
			"NanumGothic",
			"Segoe UI Symbol",
			"Arial"
		])
		ThemeDB.fallback_font = sys_font

func _colorize_suits(raw_text: String) -> String:
	if suit_regex == null or raw_text.is_empty():
		return raw_text
	var matches := suit_regex.search_all(raw_text)
	if matches.is_empty():
		return raw_text
	var out := ""
	var last_idx := 0
	for m in matches:
		var s_idx := m.get_start()
		var e_idx := m.get_end()
		out += raw_text.substr(last_idx, s_idx - last_idx)
		var token := m.get_string()
		var fg_hex := "#1A1F29"
		if token.contains("다이아몬드") or token.contains("하트") or token.contains("◆") or token.contains("♥"):
			fg_hex = "#D1242E"
		elif token.contains("조커"):
			fg_hex = "#7A29C7"
		out += "[bgcolor=#FAF8F0][color=%s] %s [/color][/bgcolor]" % [fg_hex, token]
		last_idx = e_idx
	out += raw_text.substr(last_idx)
	return out

func _create_rich_label(font_sz: int, min_h: float = 24.0) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.custom_minimum_size = Vector2(0, min_h)
	rtl.add_theme_font_size_override("normal_font_size", font_sz)
	return rtl

func _set_rich_text(rtl: RichTextLabel, raw_text: String, base_hex: String = "#EAF6F0", centered: bool = false) -> void:
	if rtl == null:
		return
	if raw_text.is_empty():
		rtl.text = ""
		return
	var body := "[color=%s]%s[/color]" % [base_hex, _colorize_suits(raw_text)]
	if centered:
		body = "[center]" + body + "[/center]"
	rtl.text = body

func _style_suit_button(btn: Button, suit: int, is_selected: bool = false) -> void:
	var fg := CARD_COLOR_BLACK
	if Rules.is_red_suit(suit):
		fg = CARD_COLOR_RED
	elif suit == Rules.SUIT_JOKER:
		fg = CARD_COLOR_JOKER
	elif suit == Rules.SUIT_NONE:
		fg = Color(0.12, 0.36, 0.24)

	var bg := Color(1.0, 0.94, 0.74) if is_selected else CARD_BG_IVORY
	var border := Color(0.95, 0.58, 0.12) if is_selected else Color(0.32, 0.36, 0.40)
	var bw := 3 if is_selected else 2

	var sb_normal := _make_panel_style(bg, border, 8, bw)
	var sb_hover := _make_panel_style(bg.lightened(0.04), Color(0.95, 0.68, 0.18), 8, bw)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_normal)
	btn.add_theme_stylebox_override("focus", sb_normal)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color", fg)

func _make_panel_style(bg: Color, border: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _create_player_seat_panel(i: int) -> PanelContainer:
	var seat := PanelContainer.new()
	seat.custom_minimum_size = Vector2(262, 154)
	seat.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.16, 0.12, 0.92), Color(0.28, 0.52, 0.38), 10, 2))

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	seat.add_child(sv)

	var header_hb := HBoxContainer.new()
	sv.add_child(header_hb)

	var name_lbl := Label.new()
	name_lbl.text = "● " + PLAYER_NAMES[i]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", PLAYER_COLORS[i])
	header_hb.add_child(name_lbl)
	player_name_labels.append(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = "대기"
	role_lbl.add_theme_font_size_override("font_size", 13)
	role_lbl.add_theme_color_override("font_color", COLOR_UNKNOWN_ROLE)
	header_hb.add_child(role_lbl)
	player_role_labels.append(role_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "남은 패: 10장 | 획득: 0점 | 누적: 0점"
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(0.84, 0.92, 0.88))
	sv.add_child(count_lbl)
	player_card_count_labels.append(count_lbl)

	var cap_box := Control.new()
	cap_box.custom_minimum_size = Vector2(240, 56)
	sv.add_child(cap_box)
	player_captured_boxes.append(cap_box)

	var bubble_lbl := _create_rich_label(12, 22.0)
	sv.add_child(bubble_lbl)
	player_bubble_labels.append(bubble_lbl)

	return seat

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.19, 0.135)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	var top_bar := PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.11, 0.08, 0.95), Color(0.25, 0.48, 0.35), 0, 1))
	main_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 14)
	top_bar.add_child(top_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "♠ 마이티 (MIGHTY)"
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	top_hbox.add_child(title_lbl)

	top_status_label = Label.new()
	top_status_label.text = "경매 준비 중"
	top_status_label.add_theme_font_size_override("font_size", 14)
	top_status_label.add_theme_color_override("font_color", Color(0.85, 0.96, 0.90))
	top_hbox.add_child(top_status_label)

	var sep1 := VSeparator.new()
	top_hbox.add_child(sep1)

	contract_info_label = _create_rich_label(14, 24.0)
	contract_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_rich_text(contract_info_label, "공약: 미정 | 주공: 미정 | 프렌드: 미정", "#FFF2C6", false)
	top_hbox.add_child(contract_info_label)

	team_score_label = Label.new()
	team_score_label.text = "★여당: 0점 | ◆야당: 0점"
	team_score_label.add_theme_font_size_override("font_size", 14)
	team_score_label.add_theme_color_override("font_color", COLOR_RULING_MAIN)
	top_hbox.add_child(team_score_label)

	played_cards_btn = Button.new()
	played_cards_btn.text = "나온 카드 보기 (0장)"
	played_cards_btn.pressed.connect(func() -> void:
		played_cards_panel.visible = not played_cards_panel.visible
		if played_cards_panel.visible:
			_refresh_played_cards_modal()
	)
	top_hbox.add_child(played_cards_btn)

	var help_btn := Button.new()
	help_btn.text = "규칙 안내"
	help_btn.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	top_hbox.add_child(help_btn)

	var restart_btn := Button.new()
	restart_btn.text = "새 판 시작"
	restart_btn.pressed.connect(func() -> void: start_new_round())
	top_hbox.add_child(restart_btn)

	var table_area := Control.new()
	table_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(table_area)

	# AI 좌석 4개만 상단/중앙 테이블 영역에 좌2, 우2로 대칭 배치 (내 현황판 i=0은 하단 패널로 분리)
	var ai_seat_anchors := {
		1: Vector2(0.015, 0.52),
		2: Vector2(0.015, 0.04),
		3: Vector2(0.775, 0.04),
		4: Vector2(0.775, 0.52)
	}

	player_seat_panels.clear()
	player_name_labels.clear()
	player_role_labels.clear()
	player_card_count_labels.clear()
	player_captured_boxes.clear()
	player_bubble_labels.clear()

	for i in range(5):
		var seat := _create_player_seat_panel(i)
		player_seat_panels.append(seat)
		if i > 0:
			var anc: Vector2 = ai_seat_anchors[i]
			seat.anchor_left = anc.x
			seat.anchor_top = anc.y
			seat.anchor_right = anc.x
			seat.anchor_bottom = anc.y
			seat.offset_right = 262
			seat.offset_bottom = 154
			table_area.add_child(seat)

	var trick_board := PanelContainer.new()
	trick_board.anchor_left = 0.235
	trick_board.anchor_right = 0.765
	trick_board.anchor_top = 0.03
	trick_board.anchor_bottom = 0.96
	trick_board.add_theme_stylebox_override("panel", _make_panel_style(Color(0.045, 0.15, 0.105, 0.85), Color(0.22, 0.45, 0.32), 16, 2))
	table_area.add_child(trick_board)

	var board_vbox := VBoxContainer.new()
	board_vbox.add_theme_constant_override("separation", 8)
	trick_board.add_child(board_vbox)

	trick_info_banner = _create_rich_label(16, 28.0)
	_set_rich_text(trick_info_banner, "경매를 시작합니다", "#FFE899", true)
	board_vbox.add_child(trick_info_banner)

	log_label = _create_rich_label(14, 24.0)
	_set_rich_text(log_label, "", "#C7F2D9", true)
	board_vbox.add_child(log_label)

	var slots_hbox := HBoxContainer.new()
	slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_hbox.add_theme_constant_override("separation", 14)
	board_vbox.add_child(slots_hbox)

	trick_slots.clear()
	for i in range(5):
		var slot_v := VBoxContainer.new()
		slot_v.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_v.custom_minimum_size = Vector2(92, 150)
		slots_hbox.add_child(slot_v)
		trick_slots.append(slot_v)

	center_modal = PanelContainer.new()
	center_modal.anchor_left = 0.24
	center_modal.anchor_right = 0.76
	center_modal.anchor_top = 0.08
	center_modal.anchor_bottom = 0.92
	center_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.13, 0.16, 0.97), Color(0.88, 0.72, 0.24), 14, 2))
	table_area.add_child(center_modal)

	modal_vbox = VBoxContainer.new()
	modal_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_vbox.add_theme_constant_override("separation", 10)
	center_modal.add_child(modal_vbox)

	# 하단 영역: 좌측에 내 현황판(player_seat_panels[0]), 우측 옆에 내 손패 카드(hand_container) 배치
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(0, 188)
	bottom_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.10, 0.075, 0.98), Color(0.32, 0.62, 0.44), 0, 2))
	main_vbox.add_child(bottom_panel)

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 14)
	bottom_panel.add_child(bottom_hbox)

	player_seat_panels[0].custom_minimum_size = Vector2(268, 164)
	player_seat_panels[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom_hbox.add_child(player_seat_panels[0])

	var bottom_sep := VSeparator.new()
	bottom_hbox.add_child(bottom_sep)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_hbox.add_child(bottom_vbox)

	hand_hint_label = Label.new()
	hand_hint_label.text = "내 손패"
	hand_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand_hint_label.add_theme_font_size_override("font_size", 14)
	hand_hint_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.88))
	bottom_vbox.add_child(hand_hint_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom_vbox.add_child(scroll)

	hand_container = HBoxContainer.new()
	hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_container.add_theme_constant_override("separation", 8)
	scroll.add_child(hand_container)

	_build_played_cards_overlay()
	_build_help_overlay()

func _build_played_cards_overlay() -> void:
	played_cards_panel = PanelContainer.new()
	played_cards_panel.visible = false
	played_cards_panel.anchor_left = 0.14
	played_cards_panel.anchor_right = 0.86
	played_cards_panel.anchor_top = 0.08
	played_cards_panel.anchor_bottom = 0.88
	played_cards_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.10, 0.14, 0.98), Color(0.45, 0.82, 0.96), 14, 2))
	add_child(played_cards_panel)

	played_cards_vbox = VBoxContainer.new()
	played_cards_vbox.add_theme_constant_override("separation", 8)
	played_cards_panel.add_child(played_cards_vbox)

func _refresh_played_cards_modal() -> void:
	if played_cards_vbox == null:
		return
	for child in played_cards_vbox.get_children():
		child.queue_free()

	var header_hb := HBoxContainer.new()
	played_cards_vbox.add_child(header_hb)

	var title := Label.new()
	title.text = "♠ 이미 나온 카드 기록 (총 %d장)" % played_cards_history.size()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	header_hb.add_child(title)

	var sub_lbl := Label.new()
	sub_lbl.text = "문양별 카드와 낸 플레이어(라운드)가 표시됩니다"
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 0.82))
	header_hb.add_child(sub_lbl)

	var suits_order := [Rules.SUIT_SPADE, Rules.SUIT_DIAMOND, Rules.SUIT_HEART, Rules.SUIT_CLUB, Rules.SUIT_JOKER]
	for s in suits_order:
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.15, 0.19, 0.92), Color(0.22, 0.38, 0.46), 8, 1))
		played_cards_vbox.add_child(row_panel)

		var row_hb := HBoxContainer.new()
		row_hb.add_theme_constant_override("separation", 12)
		row_panel.add_child(row_hb)

		var suit_items: Array = []
		for item in played_cards_history:
			var c: Dictionary = item["card"]
			if int(c["suit"]) == s:
				suit_items.append(item)

		suit_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["card"]["rank"]) > int(b["card"]["rank"])
		)

		var suit_badge := PanelContainer.new()
		suit_badge.custom_minimum_size = Vector2(142, 34)
		suit_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		suit_badge.add_theme_stylebox_override("panel", _make_panel_style(CARD_BG_IVORY, Color(0.30, 0.34, 0.38), 6, 1))
		row_hb.add_child(suit_badge)

		var s_lbl := Label.new()
		s_lbl.text = "%s (%d장)" % [str(Rules.SUIT_NAMES[s]), suit_items.size()]
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		s_lbl.add_theme_font_size_override("font_size", 14)
		if Rules.is_red_suit(s):
			s_lbl.add_theme_color_override("font_color", CARD_COLOR_RED)
		elif s == Rules.SUIT_JOKER:
			s_lbl.add_theme_color_override("font_color", CARD_COLOR_JOKER)
		else:
			s_lbl.add_theme_color_override("font_color", CARD_COLOR_BLACK)
		suit_badge.add_child(s_lbl)

		if suit_items.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "아직 나온 카드 없음"
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.add_theme_color_override("font_color", Color(0.52, 0.62, 0.58))
			row_hb.add_child(empty_lbl)
		else:
			var cards_hb := HBoxContainer.new()
			cards_hb.add_theme_constant_override("separation", 6)
			row_hb.add_child(cards_hb)

			for item in suit_items:
				var item_vbox := VBoxContainer.new()
				item_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
				item_vbox.add_theme_constant_override("separation", 2)
				cards_hb.add_child(item_vbox)

				var c_dict: Dictionary = item["card"]
				var p_idx: int = int(item["player"])
				var t_num: int = int(item["trick"])

				var cv := Button.new()
				cv.set_script(CardViewScript)
				item_vbox.add_child(cv)
				cv.setup(c_dict, trump_suit, false, true)
				cv.set_legal(false)

				var p_lbl := Label.new()
				var short_p: String = PLAYER_NAMES[p_idx].replace(" (플레이어)", "").replace("AI ", "")
				p_lbl.text = "%s(R%d)" % [short_p, t_num]
				p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				p_lbl.add_theme_font_size_override("font_size", 10)
				p_lbl.add_theme_color_override("font_color", PLAYER_COLORS[p_idx])
				item_vbox.add_child(p_lbl)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.pressed.connect(func() -> void: played_cards_panel.visible = false)
	played_cards_vbox.add_child(close_btn)

func _build_help_overlay() -> void:
	help_panel = PanelContainer.new()
	help_panel.visible = false
	help_panel.anchor_left = 0.18
	help_panel.anchor_right = 0.82
	help_panel.anchor_top = 0.10
	help_panel.anchor_bottom = 0.86
	help_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.10, 0.14, 0.98), Color(0.92, 0.76, 0.25), 14, 2))
	add_child(help_panel)

	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 10)
	help_panel.add_child(hv)

	var htitle := Label.new()
	htitle.text = "★ 마이티(Mighty) 핵심 규칙 안내"
	htitle.add_theme_font_size_override("font_size", 20)
	htitle.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	hv.add_child(htitle)

	var hbody := _create_rich_label(14, 340.0)
	hbody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_rich_text(
		hbody,
		"1. 인원 및 구성: 5명이 53장(조커 포함)으로 플레이합니다. 각 10장씩 배분하고 3장은 바닥패로 남깁니다.\n\n" +
		"2. 경매(공약): 최소 13점부터 기루다(으뜸패) 문양과 목표 점수를 선언합니다. 최고 점수를 부른 사람이 '주공(대통령)'이 됩니다.\n\n" +
		"3. 바닥패 교환 & 프렌드 지정: 주공은 바닥패 3장을 가져와 13장 중 3장을 버리고, 함께 팀(여당)이 될 '프렌드' 카드를 지정합니다.\n" +
		"   - 여당(주공·프렌드)은 따뜻한 황금색/주황색, 야당(수비팀)은 시원한 하늘색으로 구분됩니다.\n\n" +
		"4. 특수 카드 서열: 마이티(♠A, 단 스페이드가 기루다면 ◆A) > 조커 ★ > 기루다(A~2) > 선공 문양(A~2)\n" +
		"   - 초구(1라운드)에는 기루다 선공이 불가하며, 초구와 막구(10라운드)에는 조커의 효력이 없습니다.\n" +
		"   - 조커 콜(♣3, 클로버가 기루다면 ♠3)로 선공하면 조커 보유자는 반드시 조커를 내야 합니다.\n\n" +
		"5. 승리 조건: 점수 카드(A, K, Q, J, 10 - 총 20점)를 여당(주공+프렌드)이 공약 점수 이상 획득하면 여당 승리, 못 미치면 야당(3명)이 승리합니다!",
		"#E8F4EE",
		false
	)
	hv.add_child(hbody)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.pressed.connect(func() -> void: help_panel.visible = false)
	hv.add_child(close_btn)

func start_new_round() -> void:
	round_generation += 1
	var gen := round_generation
	phase = Phase.BIDDING
	var deck := Rules.create_deck()
	deck.shuffle()

	for i in range(5):
		hands[i] = deck.slice(i * 10, (i + 1) * 10)
		Rules.sort_hand(hands[i], Rules.SUIT_NONE)
		captured_points[i] = []
		passed_players[i] = false
		_set_rich_text(player_bubble_labels[i], "")

	kitty = deck.slice(50, 53)
	played_cards_history.clear()
	if played_cards_panel != null:
		played_cards_panel.visible = false

	current_bidder = 0
	highest_bid = 0
	highest_bid_suit = Rules.SUIT_SPADE
	declarer_idx = -1
	trump_suit = Rules.SUIT_NONE
	contract_score = 13
	selected_bid_suit = Rules.SUIT_SPADE
	selected_bid_score = 13
	discard_selected_ids.clear()
	friend_spec = {"type": "none", "card_id": "", "label": "미정"}
	friend_player_idx = -1
	friend_revealed = false
	trick_number = 1
	trick_plays.clear()
	active_seat_idx = 0

	_clear_trick_slots()
	_refresh_all_ui()
	_set_rich_text(log_label, "카드가 배분되었습니다. 경매를 시작합니다!", "#C7F2D9", true)
	_process_bidding_turn(gen)

func _process_bidding_turn(gen: int) -> void:
	if gen != round_generation:
		return
	_refresh_all_ui()

	var active_count := 0
	var last_active := -1
	for i in range(5):
		if not passed_players[i]:
			active_count += 1
			last_active = i

	if active_count == 0:
		_set_rich_text(log_label, "모두 패스하여 새 판을 배분합니다.", "#C7F2D9", true)
		await get_tree().create_timer(1.0).timeout
		if gen == round_generation:
			start_new_round()
		return

	if active_count == 1 and highest_bid >= 13:
		declarer_idx = last_active
		trump_suit = highest_bid_suit
		contract_score = highest_bid
		_start_kitty_phase(gen)
		return

	while passed_players[current_bidder]:
		current_bidder = (current_bidder + 1) % 5

	_highlight_active_seat(current_bidder)

	if current_bidder == 0:
		waiting_for_human = true
		_show_human_bidding_modal(gen)
	else:
		waiting_for_human = false
		center_modal.visible = false
		_set_rich_text(trick_info_banner, "%s님이 공약을 고민 중입니다..." % PLAYER_NAMES[current_bidder], "#FFE899", true)
		await get_tree().create_timer(0.55).timeout
		if gen != round_generation:
			return
		var decision := Rules.ai_decide_bid(hands[current_bidder], highest_bid)
		if str(decision["action"]) == "bid":
			highest_bid = int(decision["contract"])
			highest_bid_suit = int(decision["suit"])
			declarer_idx = current_bidder
			_set_rich_text(player_bubble_labels[current_bidder], "선언: %s %d점" % [Rules.SUIT_NAMES[highest_bid_suit], highest_bid], "#A6FAC8", false)
			_set_rich_text(log_label, "%s님이 [%s %d점] 공약을 선언했습니다!" % [
				PLAYER_NAMES[current_bidder],
				Rules.SUIT_NAMES[highest_bid_suit],
				highest_bid
			], "#C7F2D9", true)
			if highest_bid >= 20:
				trump_suit = highest_bid_suit
				contract_score = highest_bid
				_start_kitty_phase(gen)
				return
		else:
			passed_players[current_bidder] = true
			_set_rich_text(player_bubble_labels[current_bidder], "패스 (Pass)", "#A6FAC8", false)
			_set_rich_text(log_label, "%s님이 패스했습니다." % PLAYER_NAMES[current_bidder], "#C7F2D9", true)

		current_bidder = (current_bidder + 1) % 5
		_process_bidding_turn(gen)

func _show_human_bidding_modal(gen: int) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var min_bid := maxi(13, highest_bid + 1)
	if selected_bid_score < min_bid:
		selected_bid_score = min_bid

	var title := Label.new()
	title.text = "★ 경매 (공약 선언)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	modal_vbox.add_child(title)

	var cur_lbl := _create_rich_label(15, 26.0)
	if highest_bid >= 13:
		_set_rich_text(cur_lbl, "현재 최고 공약: %s (%s %d점)" % [
			PLAYER_NAMES[declarer_idx],
			Rules.SUIT_NAMES[highest_bid_suit],
			highest_bid
		], "#EAF6F0", true)
	else:
		_set_rich_text(cur_lbl, "현재 선언된 공약 없음 (최소 13점부터 가능)", "#EAF6F0", true)
	modal_vbox.add_child(cur_lbl)

	var suit_hb := HBoxContainer.new()
	suit_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	suit_hb.add_theme_constant_override("separation", 8)
	modal_vbox.add_child(suit_hb)

	for s in [Rules.SUIT_SPADE, Rules.SUIT_DIAMOND, Rules.SUIT_HEART, Rules.SUIT_CLUB, Rules.SUIT_NONE]:
		var b := Button.new()
		b.text = str(Rules.SUIT_NAMES[s])
		b.toggle_mode = true
		b.button_pressed = (selected_bid_suit == s)
		_style_suit_button(b, s, selected_bid_suit == s)
		b.pressed.connect(func() -> void:
			selected_bid_suit = s
			Rules.sort_hand(hands[0], selected_bid_suit)
			_render_human_hand()
			_show_human_bidding_modal(gen)
		)
		suit_hb.add_child(b)

	var score_hb := HBoxContainer.new()
	score_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hb.add_theme_constant_override("separation", 12)
	modal_vbox.add_child(score_hb)

	var minus_btn := Button.new()
	minus_btn.text = "-1점"
	minus_btn.disabled = (selected_bid_score <= min_bid)
	minus_btn.pressed.connect(func() -> void:
		selected_bid_score = maxi(min_bid, selected_bid_score - 1)
		_show_human_bidding_modal(gen)
	)
	score_hb.add_child(minus_btn)

	var score_val := Label.new()
	score_val.text = "목표 공약: %d점" % selected_bid_score
	score_val.add_theme_font_size_override("font_size", 18)
	score_val.add_theme_color_override("font_color", Color(1.0, 0.92, 0.50))
	score_hb.add_child(score_val)

	var plus_btn := Button.new()
	plus_btn.text = "+1점"
	plus_btn.disabled = (selected_bid_score >= 20)
	plus_btn.pressed.connect(func() -> void:
		selected_bid_score = mini(20, selected_bid_score + 1)
		_show_human_bidding_modal(gen)
	)
	score_hb.add_child(plus_btn)

	var act_hb := HBoxContainer.new()
	act_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	act_hb.add_theme_constant_override("separation", 16)
	modal_vbox.add_child(act_hb)

	var bid_btn := Button.new()
	bid_btn.text = "%s %d점 공약 선언" % [Rules.SUIT_NAMES[selected_bid_suit], selected_bid_score]
	bid_btn.disabled = (min_bid > 20)
	_style_suit_button(bid_btn, selected_bid_suit, true)
	bid_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		highest_bid = selected_bid_score
		highest_bid_suit = selected_bid_suit
		declarer_idx = 0
		_set_rich_text(player_bubble_labels[0], "선언: %s %d점" % [Rules.SUIT_NAMES[highest_bid_suit], highest_bid], "#A6FAC8", false)
		_set_rich_text(log_label, "내가 [%s %d점] 공약을 선언했습니다!" % [Rules.SUIT_NAMES[highest_bid_suit], highest_bid], "#C7F2D9", true)
		current_bidder = 1
		_process_bidding_turn(gen)
	)
	act_hb.add_child(bid_btn)

	var pass_btn := Button.new()
	pass_btn.text = "패스 (Pass)"
	pass_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		passed_players[0] = true
		_set_rich_text(player_bubble_labels[0], "패스 (Pass)", "#A6FAC8", false)
		_set_rich_text(log_label, "내가 경매를 패스했습니다.", "#C7F2D9", true)
		current_bidder = 1
		_process_bidding_turn(gen)
	)
	act_hb.add_child(pass_btn)

	if Rules.is_deal_miss_eligible(hands[0], selected_bid_suit):
		var dm_btn := Button.new()
		dm_btn.text = "딜미스 선언 (재배분)"
		dm_btn.pressed.connect(func() -> void:
			center_modal.visible = false
			_set_rich_text(log_label, "딜미스를 선언하여 패를 다시 나눕니다!", "#C7F2D9", true)
			start_new_round()
		)
		act_hb.add_child(dm_btn)

func _start_kitty_phase(gen: int) -> void:
	if gen != round_generation:
		return
	phase = Phase.KITTY_EXCHANGE
	for i in range(5):
		_set_rich_text(player_bubble_labels[i], "")
	_set_rich_text(player_bubble_labels[declarer_idx], "주공 당선! (%s %d점)" % [Rules.SUIT_NAMES[trump_suit], contract_score], "#A6FAC8", false)
	_highlight_active_seat(declarer_idx)

	hands[declarer_idx].append_array(kitty)
	Rules.sort_hand(hands[declarer_idx], trump_suit)
	_refresh_all_ui()

	if declarer_idx == 0:
		waiting_for_human = true
		discard_selected_ids.clear()
		selected_friend_option = 0
		hand_hint_label.text = "바닥패 3장이 추가되었습니다! 아래 내 손패(13장)에서 버릴 카드 3장을 클릭해 선택하세요."
		_render_human_hand()
		_show_human_kitty_modal(gen)
	else:
		waiting_for_human = false
		center_modal.visible = false
		_set_rich_text(trick_info_banner, "주공 %s님이 바닥패를 교환하고 프렌드를 지정하고 있습니다..." % PLAYER_NAMES[declarer_idx], "#FFE899", true)
		await get_tree().create_timer(1.0).timeout
		if gen != round_generation:
			return
		var prep := Rules.ai_prepare_declarer(hands[declarer_idx], trump_suit)
		hands[declarer_idx] = prep["hand"]
		Rules.sort_hand(hands[declarer_idx], trump_suit)
		for d in prep["discards"]:
			if Rules.is_point_card(d):
				captured_points[declarer_idx].append(d)
		friend_spec = prep["friend_spec"]
		_resolve_card_friend_owner()
		_set_rich_text(log_label, "주공 %s님이 [%s]를 선언했습니다!" % [PLAYER_NAMES[declarer_idx], str(friend_spec["label"])], "#C7F2D9", true)
		_start_trick_play_phase(gen)

func _show_human_kitty_modal(gen: int) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "★ 주공 당선! 바닥패 3장 버리기 & 프렌드 지정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	modal_vbox.add_child(title)

	var kitty_names: Array[String] = []
	for kc in kitty:
		kitty_names.append(Rules.card_short_name(kc))
	var kitty_lbl := _create_rich_label(14, 24.0)
	_set_rich_text(kitty_lbl, "들어온 바닥패: %s  |  선택된 버릴 카드: %d / 3장" % [", ".join(kitty_names), discard_selected_ids.size()], "#D2F5E1", true)
	modal_vbox.add_child(kitty_lbl)

	var m_card := Rules.get_mighty_card_template(trump_suit)
	var friend_options := [
		{"type": "card", "card_id": str(m_card["id"]), "suit": int(m_card["suit"]), "label": "마이티 (%s) 프렌드" % Rules.card_short_name(m_card)},
		{"type": "card", "card_id": "joker", "suit": Rules.SUIT_JOKER, "label": "조커 ★ 프렌드"},
		{"type": "first_trick", "card_id": "", "suit": Rules.SUIT_NONE, "label": "초구 프렌드 (1라운드 승자)"},
		{"type": "none", "card_id": "", "suit": Rules.SUIT_NONE, "label": "노프렌드 (혼자서 승리 도전)"}
	]
	if trump_suit != Rules.SUIT_NONE:
		var ta := {"id": "%d_14" % trump_suit, "suit": trump_suit, "rank": 14}
		var tk := {"id": "%d_13" % trump_suit, "suit": trump_suit, "rank": 13}
		friend_options.insert(2, {"type": "card", "card_id": str(ta["id"]), "suit": trump_suit, "label": "기루다 A (%s) 프렌드" % Rules.card_short_name(ta)})
		friend_options.insert(3, {"type": "card", "card_id": str(tk["id"]), "suit": trump_suit, "label": "기루다 K (%s) 프렌드" % Rules.card_short_name(tk)})

	selected_friend_option = clampi(selected_friend_option, 0, friend_options.size() - 1)

	var f_lbl := Label.new()
	f_lbl.text = "함께할 프렌드(여당) 지정:"
	f_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_vbox.add_child(f_lbl)

	var f_grid := GridContainer.new()
	f_grid.columns = 2
	f_grid.add_theme_constant_override("h_separation", 8)
	f_grid.add_theme_constant_override("v_separation", 6)
	modal_vbox.add_child(f_grid)

	for idx in range(friend_options.size()):
		var opt: Dictionary = friend_options[idx]
		var fb := Button.new()
		fb.text = str(opt["label"])
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.toggle_mode = true
		fb.button_pressed = (selected_friend_option == idx)
		_style_suit_button(fb, int(opt["suit"]), selected_friend_option == idx)
		fb.pressed.connect(func() -> void:
			selected_friend_option = idx
			_show_human_kitty_modal(gen)
		)
		f_grid.add_child(fb)

	var confirm_btn := Button.new()
	confirm_btn.text = "바닥패 3장 버리기 및 프렌드 선언 완료 (%d/3)" % discard_selected_ids.size()
	confirm_btn.disabled = (discard_selected_ids.size() != 3)
	confirm_btn.pressed.connect(func() -> void:
		var new_hand: Array = []
		for c in hands[0]:
			if discard_selected_ids.has(str(c["id"])):
				if Rules.is_point_card(c):
					captured_points[0].append(c)
			else:
				new_hand.append(c)
		hands[0] = new_hand
		Rules.sort_hand(hands[0], trump_suit)
		friend_spec = friend_options[selected_friend_option]
		_resolve_card_friend_owner()
		center_modal.visible = false
		_set_rich_text(log_label, "내가 [%s]를 선언하고 본 게임을 시작합니다!" % str(friend_spec["label"]), "#C7F2D9", true)
		_start_trick_play_phase(gen)
	)
	modal_vbox.add_child(confirm_btn)

func _resolve_card_friend_owner() -> void:
	friend_player_idx = -1
	friend_revealed = false
	if str(friend_spec["type"]) == "none":
		friend_revealed = true
		return
	if str(friend_spec["type"]) == "card":
		var target_id: String = str(friend_spec["card_id"])
		for p in range(5):
			for c in hands[p]:
				if str(c["id"]) == target_id:
					if p != declarer_idx:
						friend_player_idx = p
					break

func _start_trick_play_phase(gen: int) -> void:
	phase = Phase.PLAYING
	trick_number = 1
	trick_leader = declarer_idx
	turn_player = declarer_idx
	for i in range(5):
		Rules.sort_hand(hands[i], trump_suit)
	_start_single_trick(gen)

func _start_single_trick(gen: int) -> void:
	trick_plays.clear()
	lead_info = {
		"lead_suit": Rules.SUIT_NONE,
		"joker_call_active": false,
		"note": ""
	}
	turn_player = trick_leader
	_clear_trick_slots()
	_refresh_all_ui()
	_process_trick_turn(gen)

func _process_trick_turn(gen: int) -> void:
	if gen != round_generation:
		return
	_highlight_active_seat(turn_player)
	_refresh_all_ui()

	if trick_plays.size() == 5:
		_finish_trick(gen)
		return

	if turn_player == 0:
		waiting_for_human = true
		center_modal.visible = false
		hand_hint_label.text = "내 차례입니다! 녹색 테두리로 표시된 낼 수 있는 카드를 클릭하세요."
		_render_human_hand()
	else:
		waiting_for_human = false
		center_modal.visible = false
		hand_hint_label.text = "%s님이 카드를 내는 중입니다..." % PLAYER_NAMES[turn_player]
		_render_human_hand()
		await get_tree().create_timer(0.55).timeout
		if gen != round_generation:
			return

		var legal_ids := Rules.get_legal_card_ids(hands[turn_player], trick_plays, lead_info, trump_suit, trick_number)
		var ai_choice := Rules.ai_choose_card(
			hands[turn_player],
			legal_ids,
			trick_plays,
			lead_info,
			trump_suit,
			trick_number,
			turn_player,
			declarer_idx,
			friend_player_idx if friend_revealed else -1,
			turn_player == friend_player_idx
		)
		_execute_card_play(gen, turn_player, ai_choice["card"], bool(ai_choice["joker_call"]), int(ai_choice["joker_suit"]))

func _on_human_card_clicked(card: Dictionary) -> void:
	if not waiting_for_human:
		return

	if phase == Phase.KITTY_EXCHANGE:
		var cid: String = str(card["id"])
		if discard_selected_ids.has(cid):
			discard_selected_ids.erase(cid)
		elif discard_selected_ids.size() < 3:
			discard_selected_ids.append(cid)
		_render_human_hand()
		_show_human_kitty_modal(round_generation)
		return

	if phase == Phase.PLAYING and turn_player == 0:
		if trick_plays.is_empty():
			if Rules.is_joker(card) and trick_number > 1 and trick_number < 10:
				_show_joker_suit_modal(round_generation, card)
				return
			if Rules.is_joker_call(card, trump_suit) and trick_number > 1:
				_show_joker_call_modal(round_generation, card)
				return
		_execute_card_play(round_generation, 0, card, false, int(card["suit"]))

func _show_joker_suit_modal(gen: int, joker_card: Dictionary) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var t := _create_rich_label(18, 28.0)
	_set_rich_text(t, "★조커 선공: 요청할 문양을 선택하세요", "#FFE899", true)
	modal_vbox.add_child(t)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	modal_vbox.add_child(hb)

	for s in [Rules.SUIT_SPADE, Rules.SUIT_DIAMOND, Rules.SUIT_HEART, Rules.SUIT_CLUB]:
		var b := Button.new()
		b.text = str(Rules.SUIT_NAMES[s])
		_style_suit_button(b, s, false)
		b.pressed.connect(func() -> void:
			center_modal.visible = false
			_execute_card_play(gen, 0, joker_card, false, s)
		)
		hb.add_child(b)

func _show_joker_call_modal(gen: int, jc_card: Dictionary) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var t := _create_rich_label(18, 28.0)
	_set_rich_text(t, "▶ 조커 콜(%s) 카드를 내시겠습니까?" % Rules.card_short_name(jc_card), "#FFE899", true)
	modal_vbox.add_child(t)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	modal_vbox.add_child(hb)

	var call_btn := Button.new()
	call_btn.text = "조커 콜 선언하고 내기!"
	call_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		_execute_card_play(gen, 0, jc_card, true, int(jc_card["suit"]))
	)
	hb.add_child(call_btn)

	var normal_btn := Button.new()
	normal_btn.text = "조커 콜 없이 일반 카드로 내기"
	normal_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		_execute_card_play(gen, 0, jc_card, false, int(jc_card["suit"]))
	)
	hb.add_child(normal_btn)

func _execute_card_play(gen: int, player_idx: int, card: Dictionary, declare_joker_call: bool, joker_req_suit: int) -> void:
	if gen != round_generation:
		return
	waiting_for_human = false

	for i in range(hands[player_idx].size()):
		if str(hands[player_idx][i]["id"]) == str(card["id"]):
			hands[player_idx].remove_at(i)
			break

	if trick_plays.is_empty():
		if Rules.is_joker(card):
			var ls: int = joker_req_suit if (trick_number > 1 and trick_number < 10) else Rules.SUIT_NONE
			lead_info["lead_suit"] = ls
			lead_info["joker_call_active"] = false
			lead_info["note"] = "★조커 선공 (요청 문양: %s)" % str(Rules.SUIT_NAMES[ls])
		elif declare_joker_call and Rules.is_joker_call(card, trump_suit):
			lead_info["lead_suit"] = int(card["suit"])
			lead_info["joker_call_active"] = true
			lead_info["note"] = "▶ 조커 콜 발동! (%s)" % Rules.card_short_name(card)
		else:
			lead_info["lead_suit"] = int(card["suit"])
			lead_info["joker_call_active"] = false
			lead_info["note"] = "선문양: %s" % str(Rules.SUIT_NAMES[int(card["suit"])])

	trick_plays.append({
		"player": player_idx,
		"card": card
	})

	played_cards_history.append({
		"player": player_idx,
		"card": card,
		"trick": trick_number
	})
	if played_cards_panel != null and played_cards_panel.visible:
		_refresh_played_cards_modal()

	if str(friend_spec["type"]) == "card" and str(card["id"]) == str(friend_spec["card_id"]):
		if player_idx != declarer_idx:
			friend_player_idx = player_idx
			friend_revealed = true
			_set_rich_text(log_label, "[프렌드 공개] %s님이 프렌드 카드(%s)를 내어 여당임이 밝혀졌습니다!" % [
				PLAYER_NAMES[player_idx],
				Rules.card_short_name(card)
			], "#C7F2D9", true)

	_render_trick_slot(trick_plays.size() - 1, player_idx, card)
	turn_player = (turn_player + 1) % 5
	_process_trick_turn(gen)

func _finish_trick(gen: int) -> void:
	if gen != round_generation:
		return
	var win_play := Rules.determine_trick_winner(trick_plays, lead_info, trump_suit, trick_number)
	var winner_idx: int = int(win_play["player"])
	var win_card: Dictionary = win_play["card"]

	if trick_number == 1 and str(friend_spec["type"]) == "first_trick":
		if winner_idx != declarer_idx:
			friend_player_idx = winner_idx
		friend_revealed = true
		_set_rich_text(log_label, "[프렌드 공개] 초구 승리자 %s님이 프렌드(여당)가 되었습니다!" % PLAYER_NAMES[winner_idx], "#C7F2D9", true)

	var pts_won := 0
	for p in trick_plays:
		var c: Dictionary = p["card"]
		if Rules.is_point_card(c):
			captured_points[winner_idx].append(c)
			pts_won += 1

	_set_rich_text(trick_info_banner, "%d라운드 승자: %s (%s) — 점수 +%d점 획득!" % [
		trick_number,
		PLAYER_NAMES[winner_idx],
		Rules.card_short_name(win_card),
		pts_won
	], "#FFE899", true)
	_refresh_all_ui()

	await get_tree().create_timer(1.35).timeout
	if gen != round_generation:
		return

	if trick_number >= 10:
		_finish_round()
	else:
		trick_number += 1
		trick_leader = winner_idx
		_start_single_trick(gen)

func _finish_round() -> void:
	phase = Phase.ROUND_OVER
	friend_revealed = true

	var ruling_pts := Rules.count_point_cards(captured_points[declarer_idx])
	if friend_player_idx != -1 and friend_player_idx != declarer_idx:
		ruling_pts += Rules.count_point_cards(captured_points[friend_player_idx])
	var def_pts := 20 - ruling_pts

	var ruling_won := (ruling_pts >= contract_score)
	var delta_base := 0
	if ruling_won:
		delta_base = (ruling_pts - contract_score + 1) + (contract_score - 13)
		if ruling_pts == 20:
			delta_base *= 2
	else:
		delta_base = (contract_score - ruling_pts)
		if def_pts >= 11:
			delta_base *= 2

	if trump_suit == Rules.SUIT_NONE:
		delta_base *= 2

	var score_changes: Array[int] = [0, 0, 0, 0, 0]
	for i in range(5):
		var is_declarer := (i == declarer_idx)
		var is_friend := (i == friend_player_idx and friend_player_idx != declarer_idx)
		if ruling_won:
			if is_declarer:
				score_changes[i] = delta_base * (4 if friend_player_idx == -1 else 2)
			elif is_friend:
				score_changes[i] = delta_base
			else:
				score_changes[i] = -delta_base
		else:
			if is_declarer:
				score_changes[i] = -delta_base * (4 if friend_player_idx == -1 else 2)
			elif is_friend:
				score_changes[i] = -delta_base
			else:
				score_changes[i] = delta_base
		total_scores[i] += score_changes[i]

	_refresh_all_ui()
	_show_round_result_modal(ruling_won, ruling_pts, def_pts, score_changes)

func _show_round_result_modal(ruling_won: bool, ruling_pts: int, def_pts: int, score_changes: Array[int]) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "★ 여당(주공+프렌드) 공약 달성 승리!" if ruling_won else "◆ 야당(수비팀) 공약 저지 승리!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", COLOR_RULING_MAIN if ruling_won else COLOR_OPPOSITION)
	modal_vbox.add_child(title)

	var summary := _create_rich_label(14, 48.0)
	var f_name: String = PLAYER_NAMES[friend_player_idx] if friend_player_idx != -1 else "없음(노프렌드)"
	_set_rich_text(summary, "주공: %s | 프렌드: %s (%s)\n공약: %s %d점  →  ★여당 획득: %d점 / ◆야당 획득: %d점" % [
		PLAYER_NAMES[declarer_idx],
		f_name,
		str(friend_spec["label"]),
		str(Rules.SUIT_NAMES[trump_suit]),
		contract_score,
		ruling_pts,
		def_pts
	], "#EAF6F0", true)
	modal_vbox.add_child(summary)

	for i in range(5):
		var row_hb := HBoxContainer.new()
		row_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		row_hb.add_theme_constant_override("separation", 8)
		modal_vbox.add_child(row_hb)

		var p_lbl := Label.new()
		p_lbl.text = PLAYER_NAMES[i]
		p_lbl.add_theme_color_override("font_color", PLAYER_COLORS[i])
		row_hb.add_child(p_lbl)

		var r_lbl := Label.new()
		var role_tag := "◆ 야당"
		var r_col := COLOR_OPPOSITION
		if i == declarer_idx:
			role_tag = "★ 여당(주공)"
			r_col = COLOR_RULING_MAIN
		elif i == friend_player_idx:
			role_tag = "★ 여당(프렌드)"
			r_col = COLOR_RULING_FRIEND
		r_lbl.text = "[%s]" % role_tag
		r_lbl.add_theme_color_override("font_color", r_col)
		row_hb.add_child(r_lbl)

		var sc_lbl := Label.new()
		var diff_str := "+%d" % score_changes[i] if score_changes[i] >= 0 else str(score_changes[i])
		sc_lbl.text = ": 이번 판 %s점  (누적 %d점)" % [diff_str, total_scores[i]]
		row_hb.add_child(sc_lbl)

	var next_btn := Button.new()
	next_btn.text = "다음 판 시작하기"
	next_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		start_new_round()
	)
	modal_vbox.add_child(next_btn)

func _clear_trick_slots() -> void:
	for slot in trick_slots:
		for c in slot.get_children():
			c.queue_free()

func _render_trick_slot(slot_idx: int, player_idx: int, card: Dictionary) -> void:
	if slot_idx < 0 or slot_idx >= trick_slots.size():
		return
	var slot := trick_slots[slot_idx]
	for c in slot.get_children():
		c.queue_free()

	var who := Label.new()
	who.text = "%d. %s" % [slot_idx + 1, PLAYER_NAMES[player_idx]]
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color", PLAYER_COLORS[player_idx])
	slot.add_child(who)

	var cv := Button.new()
	cv.set_script(CardViewScript)
	slot.add_child(cv)
	cv.setup(card, trump_suit, true, false)
	cv.set_legal(false, false)

func _highlight_active_seat(active_idx: int) -> void:
	active_seat_idx = active_idx
	_update_seat_styles()

func _update_seat_styles() -> void:
	for i in range(5):
		var bg_col := Color(0.07, 0.16, 0.12, 0.92)
		var border_col := Color(0.28, 0.52, 0.38)
		if declarer_idx != -1:
			if i == declarer_idx:
				bg_col = Color(0.24, 0.15, 0.05, 0.94)
				border_col = COLOR_RULING_MAIN
			elif friend_revealed and i == friend_player_idx:
				bg_col = Color(0.22, 0.13, 0.06, 0.94)
				border_col = COLOR_RULING_FRIEND
			elif friend_revealed:
				bg_col = Color(0.05, 0.14, 0.23, 0.94)
				border_col = COLOR_OPPOSITION

		var bw := 2
		if i == active_seat_idx:
			border_col = Color(1.0, 0.96, 0.42)
			bw = 3

		player_seat_panels[i].add_theme_stylebox_override(
			"panel",
			_make_panel_style(bg_col, border_col, 10, bw)
		)

func _render_captured_solitaire(player_idx: int) -> void:
	var box := player_captured_boxes[player_idx]
	for child in box.get_children():
		child.queue_free()

	var cards: Array = captured_points[player_idx]
	if cards.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "획득 점수패 없음"
		empty_lbl.position = Vector2(2, 16)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.58, 0.68, 0.62))
		box.add_child(empty_lbl)
		return

	var count := cards.size()
	var max_span := 196.0
	var step_x := 20.0
	if count > 1:
		step_x = minf(20.0, max_span / float(count - 1))

	for idx in range(count):
		var c_data: Dictionary = cards[idx]
		var cv := Button.new()
		cv.set_script(CardViewScript)
		box.add_child(cv)
		cv.setup(c_data, trump_suit, false, true)
		cv.set_legal(false, false)
		cv.position = Vector2(float(idx) * step_x, 1.0)
		cv.size = Vector2(40, 54)

func _refresh_all_ui() -> void:
	match phase:
		Phase.BIDDING:
			top_status_label.text = "[경매 단계]"
		Phase.KITTY_EXCHANGE:
			top_status_label.text = "[바닥패 교환 & 프렌드 선언]"
		Phase.PLAYING:
			top_status_label.text = "[%d / 10 라운드]" % trick_number
			var note_str: String = str(lead_info.get("note", ""))
			_set_rich_text(trick_info_banner, "%d라운드 진행 중 %s" % [
				trick_number,
				("— " + note_str) if not note_str.is_empty() else ""
			], "#FFE899", true)
		Phase.ROUND_OVER:
			top_status_label.text = "[라운드 종료]"

	if played_cards_btn != null:
		played_cards_btn.text = "나온 카드 보기 (%d장)" % played_cards_history.size()

	if declarer_idx == -1:
		_set_rich_text(contract_info_label, "공약: 경매 중 | 주공: 미정 | 프렌드: 미정", "#FFF2C6", false)
	else:
		var f_status: String = str(friend_spec["label"])
		if friend_revealed and friend_player_idx != -1:
			f_status += " (%s)" % PLAYER_NAMES[friend_player_idx]
		elif phase == Phase.PLAYING and str(friend_spec["type"]) != "none":
			f_status += " (정체 숨김)"
		_set_rich_text(contract_info_label, "공약: %s %d점 | ★주공: %s | ★프렌드: %s" % [
			str(Rules.SUIT_NAMES[trump_suit]),
			contract_score,
			PLAYER_NAMES[declarer_idx],
			f_status
		], "#FFF2C6", false)

	var known_ruling := 0
	var known_def := 0
	for i in range(5):
		var pts := Rules.count_point_cards(captured_points[i])
		if i == declarer_idx or (friend_revealed and i == friend_player_idx):
			known_ruling += pts
		else:
			known_def += pts
	team_score_label.text = "★여당(공개): %d/%d점 | ◆야당/기타: %d점" % [known_ruling, contract_score, known_def]

	for i in range(5):
		var role_txt := "경매 중"
		var role_col := COLOR_UNKNOWN_ROLE
		if declarer_idx != -1:
			if i == declarer_idx:
				role_txt = "★ 여당 [주공]"
				role_col = COLOR_RULING_MAIN
			elif friend_revealed and i == friend_player_idx:
				role_txt = "★ 여당 [프렌드]"
				role_col = COLOR_RULING_FRIEND
			elif friend_revealed:
				role_txt = "◆ 야당 [수비]"
				role_col = COLOR_OPPOSITION
			else:
				role_txt = "? [정체 미상]"
				role_col = COLOR_UNKNOWN_ROLE
		player_role_labels[i].text = role_txt
		player_role_labels[i].add_theme_color_override("font_color", role_col)

		var pts_i := Rules.count_point_cards(captured_points[i])
		player_card_count_labels[i].text = "남은 패: %d장 | 획득: %d점 | 누적: %d점" % [hands[i].size(), pts_i, total_scores[i]]
		_render_captured_solitaire(i)

	_update_seat_styles()
	_render_human_hand()

func _render_human_hand() -> void:
	for c in hand_container.get_children():
		c.queue_free()

	var legal_ids: Array = []
	if phase == Phase.PLAYING and turn_player == 0 and waiting_for_human:
		legal_ids = Rules.get_legal_card_ids(hands[0], trick_plays, lead_info, trump_suit, trick_number)
	elif phase == Phase.KITTY_EXCHANGE and declarer_idx == 0:
		for c in hands[0]:
			legal_ids.append(str(c["id"]))

	for card in hands[0]:
		var cv := Button.new()
		cv.set_script(CardViewScript)
		hand_container.add_child(cv)
		var display_trump := trump_suit if declarer_idx != -1 else selected_bid_suit
		cv.setup(card, display_trump, false, false)

		if phase == Phase.KITTY_EXCHANGE and declarer_idx == 0:
			cv.set_legal(true, false)
			cv.set_discard_selected(discard_selected_ids.has(str(card["id"])))
		elif phase == Phase.PLAYING and turn_player == 0 and waiting_for_human:
			var can_play := legal_ids.has(str(card["id"]))
			cv.set_legal(can_play, true)
		else:
			cv.set_legal(false, false)

		cv.card_clicked.connect(_on_human_card_clicked)