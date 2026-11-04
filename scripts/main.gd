extends Control

const Rules = preload("res://scripts/card_data.gd")
const CardViewScript = preload("res://scripts/card_view.gd")

enum Phase {
	BIDDING,
	KITTY_EXCHANGE,
	PLAYING,
	ROUND_OVER
}

const PLAYER_NAMES := ["나 (플레이어)", "AI 민수", "AI 지영", "AI 현우", "AI 수진"]

var phase: Phase = Phase.BIDDING
var hands: Array = [[], [], [], [], []]
var kitty: Array = []
var captured_points: Array = [[], [], [], [], []]
var total_scores: Array[int] = [0, 0, 0, 0, 0]

# 경매 상태
var current_bidder: int = 0
var passed_players: Array[bool] = [false, false, false, false, false]
var highest_bid: int = 0
var highest_bid_suit: int = Rules.SUIT_SPADE
var declarer_idx: int = -1
var selected_bid_suit: int = Rules.SUIT_SPADE
var selected_bid_score: int = 13

# 주공/프렌드 상태
var trump_suit: int = Rules.SUIT_NONE
var contract_score: int = 13
var discard_selected_ids: Array = []
var friend_spec: Dictionary = {"type": "none", "card_id": "", "label": "미정"}
var friend_player_idx: int = -1
var friend_revealed: bool = false
var selected_friend_option: int = 0

# 트릭 진행 상태
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
var pending_special_card: Dictionary = {}

# UI 노드 참조
var top_status_label: Label
var contract_info_label: Label
var team_score_label: Label
var log_label: Label
var player_seat_panels: Array[PanelContainer] = []
var player_role_labels: Array[Label] = []
var player_card_count_labels: Array[Label] = []
var player_captured_labels: Array[Label] = []
var player_bubble_labels: Array[Label] = []

var trick_slots: Array[VBoxContainer] = []
var trick_info_banner: Label
var hand_container: HBoxContainer
var hand_hint_label: Label

var center_modal: PanelContainer
var modal_vbox: VBoxContainer
var help_panel: PanelContainer

func _ready() -> void:
	randomize()
	_setup_korean_font()
	_build_ui()
	start_new_round()

func _setup_korean_font() -> void:
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

func _make_panel_style(bg: Color, border: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _build_ui() -> void:
	# 전체 배경 테이블
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.19, 0.135)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 1. 상단 정보 바
	var top_bar := PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.11, 0.08, 0.95), Color(0.25, 0.48, 0.35), 0, 1))
	main_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 18)
	top_bar.add_child(top_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "♠ 마이티 (MIGHTY)"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	top_hbox.add_child(title_lbl)

	top_status_label = Label.new()
	top_status_label.text = "경매 준비 중"
	top_status_label.add_theme_font_size_override("font_size", 15)
	top_status_label.add_theme_color_override("font_color", Color(0.85, 0.96, 0.90))
	top_hbox.add_child(top_status_label)

	var sep1 := VSeparator.new()
	top_hbox.add_child(sep1)

	contract_info_label = Label.new()
	contract_info_label.text = "공약: 미정 | 주공: 미정 | 프렌드: 미정"
	contract_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contract_info_label.add_theme_font_size_override("font_size", 15)
	contract_info_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	top_hbox.add_child(contract_info_label)

	team_score_label = Label.new()
	team_score_label.text = "여당: 0점 | 야당: 0점"
	team_score_label.add_theme_font_size_override("font_size", 15)
	team_score_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	top_hbox.add_child(team_score_label)

	var help_btn := Button.new()
	help_btn.text = "규칙 안내"
	help_btn.pressed.connect(func() -> void: help_panel.visible = not help_panel.visible)
	top_hbox.add_child(help_btn)

	var restart_btn := Button.new()
	restart_btn.text = "새 판 시작"
	restart_btn.pressed.connect(func() -> void: start_new_round())
	top_hbox.add_child(restart_btn)

	# 2. 중앙 게임 테이블 영역
	var table_area := Control.new()
	table_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(table_area)

	# 플레이어 5명 좌석 패널 생성 (0: 하단 요약, 1: 좌하, 2: 좌상, 3: 우상, 4: 우하)
	var seat_anchors := [
		Vector2(0.02, 0.74), # 0: 나 (좌측 하단 상태창)
		Vector2(0.02, 0.40), # 1: AI 민수
		Vector2(0.02, 0.04), # 2: AI 지영
		Vector2(0.78, 0.04), # 3: AI 현우
		Vector2(0.78, 0.40)  # 4: AI 수진
	]

	player_seat_panels.clear()
	player_role_labels.clear()
	player_card_count_labels.clear()
	player_captured_labels.clear()
	player_bubble_labels.clear()

	for i in range(5):
		var seat := PanelContainer.new()
		seat.custom_minimum_size = Vector2(245, 118)
		seat.anchor_left = seat_anchors[i].x
		seat.anchor_top = seat_anchors[i].y
		seat.anchor_right = seat_anchors[i].x
		seat.anchor_bottom = seat_anchors[i].y
		seat.offset_right = 245
		seat.offset_bottom = 118
		seat.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.16, 0.12, 0.92), Color(0.28, 0.52, 0.38), 10, 2))
		table_area.add_child(seat)
		player_seat_panels.append(seat)

		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 4)
		seat.add_child(sv)

		var header_hb := HBoxContainer.new()
		sv.add_child(header_hb)

		var name_lbl := Label.new()
		name_lbl.text = PLAYER_NAMES[i]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		header_hb.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = "대기"
		role_lbl.add_theme_font_size_override("font_size", 13)
		role_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.30))
		header_hb.add_child(role_lbl)
		player_role_labels.append(role_lbl)

		var count_lbl := Label.new()
		count_lbl.text = "남은 패: 10장 | 누적: 0점"
		count_lbl.add_theme_font_size_override("font_size", 13)
		count_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 0.84))
		sv.add_child(count_lbl)
		player_card_count_labels.append(count_lbl)

		var cap_lbl := Label.new()
		cap_lbl.text = "획득 점수패(0점): 없음"
		cap_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap_lbl.add_theme_font_size_override("font_size", 12)
		cap_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
		sv.add_child(cap_lbl)
		player_captured_labels.append(cap_lbl)

		var bubble_lbl := Label.new()
		bubble_lbl.text = ""
		bubble_lbl.add_theme_font_size_override("font_size", 13)
		bubble_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.72))
		sv.add_child(bubble_lbl)
		player_bubble_labels.append(bubble_lbl)

	# 중앙 트릭 보드
	var trick_board := PanelContainer.new()
	trick_board.anchor_left = 0.24
	trick_board.anchor_right = 0.76
	trick_board.anchor_top = 0.04
	trick_board.anchor_bottom = 0.94
	trick_board.add_theme_stylebox_override("panel", _make_panel_style(Color(0.045, 0.15, 0.105, 0.85), Color(0.22, 0.45, 0.32), 16, 2))
	table_area.add_child(trick_board)

	var board_vbox := VBoxContainer.new()
	board_vbox.add_theme_constant_override("separation", 8)
	trick_board.add_child(board_vbox)

	trick_info_banner = Label.new()
	trick_info_banner.text = "경매를 시작합니다"
	trick_info_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_info_banner.add_theme_font_size_override("font_size", 16)
	trick_info_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.60))
	board_vbox.add_child(trick_info_banner)

	log_label = Label.new()
	log_label.text = ""
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.add_theme_font_size_override("font_size", 14)
	log_label.add_theme_color_override("font_color", Color(0.78, 0.95, 0.85))
	board_vbox.add_child(log_label)

	# 트릭에 낸 카드 5장 표시 영역
	var slots_hbox := HBoxContainer.new()
	slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_hbox.add_theme_constant_override("separation", 16)
	board_vbox.add_child(slots_hbox)

	trick_slots.clear()
	for i in range(5):
		var slot_v := VBoxContainer.new()
		slot_v.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_v.custom_minimum_size = Vector2(96, 150)
		slots_hbox.add_child(slot_v)
		trick_slots.append(slot_v)

	# 경매 / 바닥패 교환 / 특수 카드 선언 모달
	center_modal = PanelContainer.new()
	center_modal.anchor_left = 0.25
	center_modal.anchor_right = 0.75
	center_modal.anchor_top = 0.14
	center_modal.anchor_bottom = 0.88
	center_modal.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.13, 0.16, 0.97), Color(0.88, 0.72, 0.24), 14, 2))
	table_area.add_child(center_modal)

	modal_vbox = VBoxContainer.new()
	modal_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	modal_vbox.add_theme_constant_override("separation", 10)
	center_modal.add_child(modal_vbox)

	# 3. 하단 내 손패 영역
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(0, 190)
	bottom_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.11, 0.08, 0.96), Color(0.26, 0.50, 0.36), 0, 1))
	main_vbox.add_child(bottom_panel)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 6)
	bottom_panel.add_child(bottom_vbox)

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

	# 규칙 안내 오버레이
	_build_help_overlay()

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
	htitle.text = "📖 마이티(Mighty) 핵심 규칙 안내"
	htitle.add_theme_font_size_override("font_size", 20)
	htitle.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	hv.add_child(htitle)

	var hbody := Label.new()
	hbody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbody.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbody.text = (
		"1. 인원 및 구성: 5명이 53장(조커 포함)으로 플레이합니다. 각 10장씩 배분하고 3장은 바닥패로 남깁니다.\n\n" +
		"2. 경매(공약): 최소 13점부터 기루다(으뜸패) 문양과 목표 점수를 선언합니다. 최고 점수를 부른 사람이 '주공(대통령)'이 됩니다.\n\n" +
		"3. 바닥패 교환 & 프렌드 지정: 주공은 바닥패 3장을 가져와 13장 중 3장을 버리고, 함께 팀(여당)이 될 '프렌드' 카드를 지정합니다.\n" +
		"   - 프렌드로 지정된 카드를 가진 플레이어는 해당 카드를 내기 전까지 정체가 숨겨집니다.\n\n" +
		"4. 특수 카드 서열: 마이티(♠A, 단 스페이드가 기루다면 ♦A) > 조커(🃏) > 기루다(A~2) > 선공 문양(A~2)\n" +
		"   - 초구(1라운드)에는 기루다 선공이 불가하며, 초구와 막구(10라운드)에는 조커의 효력이 없습니다.\n" +
		"   - 조커 콜(♣3, 클로버가 기루다면 ♠3)로 선공하면 조커 보유자는 반드시 조커를 내야 합니다.\n\n" +
		"5. 승리 조건: 점수 카드(A, K, Q, J, 10 - 총 20점)를 여당(주공+프렌드)이 공약 점수 이상 획득하면 여당 승리, 못 미치면 야당(3명)이 승리합니다!"
	)
	hv.add_child(hbody)

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.pressed.connect(func() -> void: help_panel.visible = false)
	hv.add_child(close_btn)

# =========================================================================
# 라운드 시작 및 배분
# =========================================================================
func start_new_round() -> void:
	phase = Phase.BIDDING
	var deck := Rules.create_deck()
	deck.shuffle()

	for i in range(5):
		hands[i] = deck.slice(i * 10, (i + 1) * 10)
		Rules.sort_hand(hands[i], Rules.SUIT_NONE)
		captured_points[i] = []
		passed_players[i] = false
		player_bubble_labels[i].text = ""

	kitty = deck.slice(50, 53)

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
	pending_special_card = {}

	_clear_trick_slots()
	_refresh_all_ui()
	log_label.text = "카드가 배분되었습니다. 경매를 시작합니다!"
	_process_bidding_turn()

func _process_bidding_turn() -> void:
	_refresh_all_ui()

	# 남은 경매 참여자 수 확인
	var active_count := 0
	var last_active := -1
	for i in range(5):
		if not passed_players[i]:
			active_count += 1
			last_active = i

	if active_count == 0:
		log_label.text = "모두 패스하여 새 판을 배분합니다."
		await get_tree().create_timer(1.0).timeout
		start_new_round()
		return

	if active_count == 1 and highest_bid >= 13:
		declarer_idx = last_active
		trump_suit = highest_bid_suit
		contract_score = highest_bid
		_start_kitty_phase()
		return

	# 다음 순서 찾기
	while passed_players[current_bidder]:
		current_bidder = (current_bidder + 1) % 5

	_highlight_active_seat(current_bidder)

	if current_bidder == 0:
		waiting_for_human = true
		_show_human_bidding_modal()
	else:
		waiting_for_human = false
		center_modal.visible = false
		trick_info_banner.text = "%s님이 공약을 고민 중입니다..." % PLAYER_NAMES[current_bidder]
		await get_tree().create_timer(0.55).timeout
		var decision := Rules.ai_decide_bid(hands[current_bidder], highest_bid)
		if decision["action"] == "bid":
			highest_bid = int(decision["contract"])
			highest_bid_suit = int(decision["suit"])
			declarer_idx = current_bidder
			player_bubble_labels[current_bidder].text = "선언: %s %d점" % [Rules.SUIT_SYMBOLS[highest_bid_suit], highest_bid]
			log_label.text = "%s님이 [%s %d점] 공약을 선언했습니다!" % [
				PLAYER_NAMES[current_bidder],
				Rules.SUIT_NAMES[highest_bid_suit],
				highest_bid
			]
			if highest_bid >= 20:
				_start_kitty_phase()
				return
		else:
			passed_players[current_bidder] = true
			player_bubble_labels[current_bidder].text = "패스 (Pass)"
			log_label.text = "%s님이 패스했습니다." % PLAYER_NAMES[current_bidder]

		current_bidder = (current_bidder + 1) % 5
		_process_bidding_turn()

func _show_human_bidding_modal() -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var min_bid := maxi(13, highest_bid + 1)
	if selected_bid_score < min_bid:
		selected_bid_score = min_bid

	var title := Label.new()
	title.text = "👑 경매 (공약 선언)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	modal_vbox.add_child(title)

	var cur_lbl := Label.new()
	if highest_bid >= 13:
		cur_lbl.text = "현재 최고 공약: %s (%s %d점)" % [
			PLAYER_NAMES[declarer_idx],
			Rules.SUIT_NAMES[highest_bid_suit],
			highest_bid
		]
	else:
		cur_lbl.text = "현재 선언된 공약 없음 (최소 13점부터 가능)"
	cur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_vbox.add_child(cur_lbl)

	# 기루다 문양 선택 버튼
	var suit_hb := HBoxContainer.new()
	suit_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	suit_hb.add_theme_constant_override("separation", 8)
	modal_vbox.add_child(suit_hb)

	for s in [Rules.SUIT_SPADE, Rules.SUIT_DIAMOND, Rules.SUIT_HEART, Rules.SUIT_CLUB, Rules.SUIT_NONE]:
		var b := Button.new()
		b.text = Rules.SUIT_NAMES[s]
		b.toggle_mode = true
		b.button_pressed = (selected_bid_suit == s)
		b.pressed.connect(func() -> void:
			selected_bid_suit = s
			Rules.sort_hand(hands[0], selected_bid_suit)
			_render_human_hand()
			_show_human_bidding_modal()
		)
		suit_hb.add_child(b)

	# 목표 점수 조절
	var score_hb := HBoxContainer.new()
	score_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hb.add_theme_constant_override("separation", 12)
	modal_vbox.add_child(score_hb)

	var minus_btn := Button.new()
	minus_btn.text = "-1점"
	minus_btn.disabled = (selected_bid_score <= min_bid)
	minus_btn.pressed.connect(func() -> void:
		selected_bid_score = maxi(min_bid, selected_bid_score - 1)
		_show_human_bidding_modal()
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
		_show_human_bidding_modal()
	)
	score_hb.add_child(plus_btn)

	# 액션 버튼 (공약 선언 / 패스 / 딜미스)
	var act_hb := HBoxContainer.new()
	act_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	act_hb.add_theme_constant_override("separation", 16)
	modal_vbox.add_child(act_hb)

	var bid_btn := Button.new()
	bid_btn.text = "%s %d점 공약 선언" % [Rules.SUIT_NAMES[selected_bid_suit], selected_bid_score]
	bid_btn.disabled = (min_bid > 20)
	bid_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		highest_bid = selected_bid_score
		highest_bid_suit = selected_bid_suit
		declarer_idx = 0
		player_bubble_labels[0].text = "선언: %s %d점" % [Rules.SUIT_SYMBOLS[highest_bid_suit], highest_bid]
		log_label.text = "내가 [%s %d점] 공약을 선언했습니다!" % [Rules.SUIT_NAMES[highest_bid_suit], highest_bid]
		current_bidder = 1
		_process_bidding_turn()
	)
	act_hb.add_child(bid_btn)

	var pass_btn := Button.new()
	pass_btn.text = "패스 (Pass)"
	pass_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		passed_players[0] = true
		player_bubble_labels[0].text = "패스 (Pass)"
		log_label.text = "내가 경매를 패스했습니다."
		current_bidder = 1
		_process_bidding_turn()
	)
	act_hb.add_child(pass_btn)

	if Rules.is_deal_miss_eligible(hands[0], selected_bid_suit):
		var dm_btn := Button.new()
		dm_btn.text = "딜미스 선언 (재배분)"
		dm_btn.pressed.connect(func() -> void:
			center_modal.visible = false
			log_label.text = "딜미스를 선언하여 패를 다시 나눕니다!"
			start_new_round()
		)
		act_hb.add_child(dm_btn)

# =========================================================================
# 바닥패 교환 및 프렌드 지정 단계
# =========================================================================
func _start_kitty_phase() -> void:
	phase = Phase.KITTY_EXCHANGE
	for i in range(5):
		player_bubble_labels[i].text = ""
	player_bubble_labels[declarer_idx].text = "주공 당선! (%s %d점)" % [Rules.SUIT_SYMBOLS[trump_suit], contract_score]

	# 바닥패 3장을 주공 손패에 추가
	hands[declarer_idx].append_array(kitty)
	Rules.sort_hand(hands[declarer_idx], trump_suit)

	# 바닥패에 있던 점수 카드를 버릴 경우 주공 획득 점수에 포함하기 위해 준비
	_refresh_all_ui()

	if declarer_idx == 0:
		waiting_for_human = true
		discard_selected_ids.clear()
		selected_friend_option = 0
		hand_hint_label.text = "바닥패 3장이 추가되었습니다! 아래 내 손패(13장)에서 버릴 카드 3장을 클릭해 선택하세요."
		_render_human_hand()
		_show_human_kitty_modal()
	else:
		waiting_for_human = false
		center_modal.visible = false
		trick_info_banner.text = "주공 %s님이 바닥패를 교환하고 프렌드를 지정하고 있습니다..." % PLAYER_NAMES[declarer_idx]
		await get_tree().create_timer(1.0).timeout
		var prep := Rules.ai_prepare_declarer(hands[declarer_idx], trump_suit)
		hands[declarer_idx] = prep["hand"]
		Rules.sort_hand(hands[declarer_idx], trump_suit)
		for d in prep["discards"]:
			if Rules.is_point_card(d):
				captured_points[declarer_idx].append(d)
		friend_spec = prep["friend_spec"]
		_resolve_card_friend_owner()
		log_label.text = "주공 %s님이 [%s]를 선언했습니다!" % [PLAYER_NAMES[declarer_idx], friend_spec["label"]]
		_start_trick_play_phase()

func _show_human_kitty_modal() -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "👑 주공 당선! 바닥패 3장 버리기 & 프렌드 지정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28))
	modal_vbox.add_child(title)

	var kitty_names: Array[String] = []
	for kc in kitty:
		kitty_names.append(Rules.card_short_name(kc))
	var kitty_lbl := Label.new()
	kitty_lbl.text = "들어온 바닥패: %s  |  선택된 버릴 카드: %d / 3장" % [", ".join(kitty_names), discard_selected_ids.size()]
	kitty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kitty_lbl.add_theme_color_override("font_color", Color(0.82, 0.96, 0.88))
	modal_vbox.add_child(kitty_lbl)

	# 프렌드 옵션 목록 구성
	var m_card := Rules.get_mighty_card_Template(trump_suit)
	var friend_options := [
		{"type": "card", "card_id": m_card["id"], "label": "마이티 (%s) 프렌드" % Rules.card_short_name(m_card)},
		{"type": "card", "card_id": "joker", "label": "조커 (🃏) 프렌드"},
		{"type": "first_trick", "card_id": "", "label": "초구 프렌드 (1라운드 승자)"},
		{"type": "none", "card_id": "", "label": "노프렌드 (혼자서 승리 도전)"}
	]
	if trump_suit != Rules.SUIT_NONE:
		var ta := {"id": "%d_14" % trump_suit, "suit": trump_suit, "rank": 14}
		var tk := {"id": "%d_13" % trump_suit, "suit": trump_suit, "rank": 13}
		friend_options.insert(2, {"type": "card", "card_id": ta["id"], "label": "기루다 A (%s) 프렌드" % Rules.card_short_name(ta)})
		friend_options.insert(3, {"type": "card", "card_id": tk["id"], "label": "기루다 K (%s) 프렌드" % Rules.card_short_name(tk)})

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
		fb.text = opt["label"]
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.toggle_mode = true
		fb.button_pressed = (selected_friend_option == idx)
		fb.pressed.connect(func() -> void:
			selected_friend_option = idx
			_show_human_kitty_modal()
		)
		f_grid.add_child(fb)

	var confirm_btn := Button.new()
	confirm_btn.text = "바닥패 3장 버리기 및 프렌드 선언 완료 (%d/3)" % discard_selected_ids.size()
	confirm_btn.disabled = (discard_selected_ids.size() != 3)
	confirm_btn.pressed.connect(func() -> void:
		var new_hand: Array = []
		for c in hands[0]:
			if discard_selected_ids.has(c["id"]):
				if Rules.is_point_card(c):
					captured_points[0].append(c)
			else:
				new_hand.append(c)
		hands[0] = new_hand
		Rules.sort_hand(hands[0], trump_suit)
		friend_spec = friend_options[selected_friend_option]
		_resolve_card_friend_owner()
		center_modal.visible = false
		log_label.text = "내가 [%s]를 선언하고 본 게임을 시작합니다!" % friend_spec["label"]
		_start_trick_play_phase()
	)
	modal_vbox.add_child(confirm_btn)

func _resolve_card_friend_owner() -> void:
	friend_player_idx = -1
	friend_revealed = false
	if friend_spec["type"] == "none":
		friend_revealed = true
		return
	if friend_spec["type"] == "card":
		var target_id: String = friend_spec["card_id"]
		for p in range(5):
			for c in hands[p]:
				if c["id"] == target_id:
					if p != declarer_idx:
						friend_player_idx = p
					break

# =========================================================================
# 트릭(1~10라운드) 진행 단계
# =========================================================================
func _start_trick_play_phase() -> void:
	phase = Phase.PLAYING
	trick_number = 1
	trick_leader = declarer_idx
	turn_player = declarer_idx
	for i in range(5):
		Rules.sort_hand(hands[i], trump_suit)
	_start_single_trick()

func _start_single_trick() -> void:
	trick_plays.clear()
	lead_info = {
		"lead_suit": Rules.SUIT_NONE,
		"joker_call_active": false,
		"note": ""
	}
	turn_player = trick_leader
	_clear_trick_slots()
	_refresh_all_ui()
	_process_trick_turn()

func _process_trick_turn() -> void:
	_refresh_all_ui()
	_highlight_active_seat(turn_player)

	if trick_plays.size() == 5:
		_finish_trick()
		return

	if turn_player == 0:
		waiting_for_human = true
		center_modal.visible = false
		hand_hint_label.text = "내 차례입니다! 낼 수 있는 밝은 카드를 클릭하세요."
		_render_human_hand()
	else:
		waiting_for_human = false
		center_modal.visible = false
		hand_hint_label.text = "%s님이 카드를 내는 중입니다..." % PLAYER_NAMES[turn_player]
		_render_human_hand()
		await get_tree().create_timer(0.55).timeout

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
		_execute_card_play(turn_player, ai_choice["card"], ai_choice["joker_call"], ai_choice["joker_suit"])

func _on_human_card_clicked(card: Dictionary) -> void:
	if not waiting_for_human:
		return

	if phase == Phase.KITTY_EXCHANGE:
		var cid: String = card["id"]
		if discard_selected_ids.has(cid):
			discard_selected_ids.erase(cid)
		elif discard_selected_ids.size() < 3:
			discard_selected_ids.append(cid)
		_render_human_hand()
		_show_human_kitty_modal()
		return

	if phase == Phase.PLAYING and turn_player == 0:
		# 선공일 때 조커 또는 조커콜 카드면 옵션 모달 표시
		if trick_plays.is_empty():
			if Rules.is_joker(card) and trick_number > 1 and trick_number < 10:
				_show_joker_suit_modal(card)
				return
			if Rules.is_joker_call(card, trump_suit) and trick_number > 1:
				_show_joker_call_modal(card)
				return
		_execute_card_play(0, card, false, card["suit"])

func _show_joker_suit_modal(joker_card: Dictionary) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var t := Label.new()
	t.text = "🃏 조커 선공: 요청할 문양을 선택하세요"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 18)
	modal_vbox.add_child(t)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	modal_vbox.add_child(hb)

	for s in [Rules.SUIT_SPADE, Rules.SUIT_DIAMOND, Rules.SUIT_HEART, Rules.SUIT_CLUB]:
		var b := Button.new()
		b.text = Rules.SUIT_NAMES[s]
		b.pressed.connect(func() -> void:
			center_modal.visible = false
			_execute_card_play(0, joker_card, false, s)
		)
		hb.add_child(b)

func _show_joker_call_modal(jc_card: Dictionary) -> void:
	center_modal.visible = true
	for child in modal_vbox.get_children():
		child.queue_free()

	var t := Label.new()
	t.text = "📢 조커 콜(%s) 카드를 내시겠습니까?" % Rules.card_short_name(jc_card)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 18)
	modal_vbox.add_child(t)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	modal_vbox.add_child(hb)

	var call_btn := Button.new()
	call_btn.text = "조커 콜 선언하고 내기!"
	call_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		_execute_card_play(0, jc_card, true, jc_card["suit"])
	)
	hb.add_child(call_btn)

	var normal_btn := Button.new()
	normal_btn.text = "조커 콜 없이 일반 카드로 내기"
	normal_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		_execute_card_play(0, jc_card, false, jc_card["suit"])
	)
	hb.add_child(normal_btn)

func _execute_card_play(player_idx: int, card: Dictionary, declare_joker_call: bool, joker_req_suit: int) -> void:
	waiting_for_human = false

	# 손패에서 제거
	for i in range(hands[player_idx].size()):
		if hands[player_idx][i]["id"] == card["id"]:
			hands[player_idx].remove_at(i)
			break

	# 선공일 경우 선문양 설정
	if trick_plays.is_empty():
		if Rules.is_joker(card):
			lead_info["lead_suit"] = joker_req_suit if (trick_number > 1 and trick_number < 10) else Rules.SUIT_NONE
			lead_info["joker_call_active"] = false
			lead_info["note"] = "조커 선공 (요청 문양: %s)" % Rules.SUIT_NAMES[lead_info["lead_suit"]]
		elif declare_joker_call and Rules.is_joker_call(card, trump_suit):
			lead_info["lead_suit"] = card["suit"]
			lead_info["joker_call_active"] = true
			lead_info["note"] = "📢 조커 콜 발동! (%s)" % Rules.card_short_name(card)
		else:
			lead_info["lead_suit"] = card["suit"]
			lead_info["joker_call_active"] = false
			lead_info["note"] = "선문양: %s" % Rules.SUIT_NAMES[card["suit"]]

	trick_plays.append({
		"player": player_idx,
		"card": card
	})

	# 프렌드 카드 공개 확인
	if friend_spec["type"] == "card" and card["id"] == friend_spec["card_id"]:
		if player_idx != declarer_idx:
			friend_player_idx = player_idx
			friend_revealed = true
			log_label.text = "🤝 %s님이 프렌드 카드(%s)를 내어 여당(프렌드)임이 밝혀졌습니다!" % [
				PLAYER_NAMES[player_idx],
				Rules.card_short_name(card)
			]

	_render_trick_slot(trick_plays.size() - 1, player_idx, card)
	turn_player = (turn_player + 1) % 5
	_process_trick_turn()

func _finish_trick() -> void:
	var win_play := Rules.determine_trick_winner(trick_plays, lead_info, trump_suit, trick_number)
	var winner_idx: int = win_play["player"]
	var win_card: Dictionary = win_play["card"]

	# 초구 프렌드 확인
	if trick_number == 1 and friend_spec["type"] == "first_trick":
		if winner_idx != declarer_idx:
			friend_player_idx = winner_idx
		friend_revealed = true
		log_label.text = "🤝 초구 승리자 %s님이 프렌드(여당)가 되었습니다!" % PLAYER_NAMES[winner_idx]

	# 트릭의 점수 카드 수거
	var pts_won := 0
	for p in trick_plays:
		var c: Dictionary = p["card"]
		if Rules.is_point_card(c):
			captured_points[winner_idx].append(c)
			pts_won += 1

	trick_info_banner.text = "%d라운드 승자: %s (%s) — 점수 +%d점 획득!" % [
		trick_number,
		PLAYER_NAMES[winner_idx],
		Rules.card_short_name(win_card),
		pts_won
	]
	_refresh_all_ui()

	await get_tree().create_timer(1.35).timeout

	if trick_number >= 10:
		_finish_round()
	else:
		trick_number += 1
		trick_leader = winner_idx
		_start_single_trick()

# =========================================================================
# 라운드 종료 및 정산
# =========================================================================
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
			delta_base *= 2 # 런(Run) 2배
	else:
		delta_base = (contract_score - ruling_pts)
		if def_pts >= 11:
			delta_base *= 2 # 백런(Back-run) 2배

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
	title.text = "🎉 여당(주공+프렌드) 공약 달성 승리!" if ruling_won else "🛡️ 야당(수비팀) 공약 저지 승리!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.28) if ruling_won else Color(0.55, 0.90, 1.0))
	modal_vbox.add_child(title)

	var summary := Label.new()
	var f_name := PLAYER_NAMES[friend_player_idx] if friend_player_idx != -1 else "없음(노프렌드)"
	summary.text = "주공: %s | 프렌드: %s (%s)\n공약: %s %d점  →  여당 획득: %d점 / 야당 획득: %d점" % [
		PLAYER_NAMES[declarer_idx],
		f_name,
		friend_spec["label"],
		Rules.SUIT_NAMES[trump_suit],
		contract_score,
		ruling_pts,
		def_pts
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_vbox.add_child(summary)

	for i in range(5):
		var row := Label.new()
		var role_tag := "야당"
		if i == declarer_idx:
			role_tag = "주공👑"
		elif i == friend_player_idx:
			role_tag = "프렌드🤝"
		var diff_str := "+%d" % score_changes[i] if score_changes[i] >= 0 else str(score_changes[i])
		row.text = "%s [%s] : 이번 판 %s점  (누적 %d점)" % [PLAYER_NAMES[i], role_tag, diff_str, total_scores[i]]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal_vbox.add_child(row)

	var next_btn := Button.new()
	next_btn.text = "다음 판 시작하기"
	next_btn.pressed.connect(func() -> void:
		center_modal.visible = false
		start_new_round()
	)
	modal_vbox.add_child(next_btn)

# =========================================================================
# 화면 갱신 헬퍼
# =========================================================================
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
	slot.add_child(who)

	var cv := Button.new()
	cv.set_script(CardViewScript)
	slot.add_child(cv)
	cv.setup(card, trump_suit, true)
	cv.set_legal(false)

func _highlight_active_seat(active_idx: int) -> void:
	for i in range(5):
		var border_col := Color(0.96, 0.80, 0.22) if i == active_idx else Color(0.28, 0.52, 0.38)
		var bw := 3 if i == active_idx else 2
		player_seat_panels[i].add_theme_stylebox_override(
			"panel",
			_make_panel_style(Color(0.07, 0.16, 0.12, 0.92), border_col, 10, bw)
		)

func _refresh_all_ui() -> void:
	match phase:
		Phase.BIDDING:
			top_status_label.text = "[경매 단계]"
		Phase.KITTY_EXCHANGE:
			top_status_label.text = "[바닥패 교환 & 프렌드 선언]"
		Phase.PLAYING:
			top_status_label.text = "[%d / 10 라운드]" % trick_number
			var note_str: String = lead_info.get("note", "")
			trick_info_banner.text = "%d라운드 진행 중 %s" % [
				trick_number,
				("— " + note_str) if not note_str.is_empty() else ""
			]
		Phase.ROUND_OVER:
			top_status_label.text = "[라운드 종료]"

	if declarer_idx == -1:
		contract_info_label.text = "공약: 경매 중 | 주공: 미정 | 프렌드: 미정"
	else:
		var f_status := friend_spec["label"]
		if friend_revealed and friend_player_idx != -1:
			f_status += " (%s)" % PLAYER_NAMES[friend_player_idx]
		elif phase == Phase.PLAYING and friend_spec["type"] != "none":
			f_status += " (정체 숨김)"
		contract_info_label.text = "공약: %s %d점 | 주공: %s | 프렌드: %s" % [
			Rules.SUIT_NAMES[trump_suit],
			contract_score,
			PLAYER_NAMES[declarer_idx],
			f_status
		]

	# 여당/야당 실시간 공개 점수 집계
	var known_ruling := 0
	var known_def := 0
	for i in range(5):
		var pts := Rules.count_point_cards(captured_points[i])
		if i == declarer_idx or (friend_revealed and i == friend_player_idx):
			known_ruling += pts
		else:
			known_def += pts
	team_score_label.text = "여당(공개): %d / %d점 | 기타 획득: %d점" % [known_ruling, contract_score, known_def]

	# 각 좌석 정보 업데이트
	for i in range(5):
		var role_txt := "경매 중"
		if declarer_idx != -1:
			if i == declarer_idx:
				role_txt = "👑 주공"
			elif friend_revealed and i == friend_player_idx:
				role_txt = "🤝 프렌드"
			elif friend_revealed:
				role_txt = "🛡️ 야당"
			else:
				role_txt = "❓ 미상"
		player_role_labels[i].text = role_txt
		player_card_count_labels[i].text = "남은 패: %d장 | 누적: %d점" % [hands[i].size(), total_scores[i]]

		var cap_list: Array[String] = []
		for c in captured_points[i]:
			cap_list.append(Rules.card_short_name(c))
		player_captured_labels[i].text = "획득(%d점): %s" % [
			cap_list.size(),
			" ".join(cap_list) if not cap_list.is_empty() else "없음"
		]

	_render_human_hand()

func _render_human_hand() -> void:
	for c in hand_container.get_children():
		c.queue_free()

	var legal_ids: Array = []
	if phase == Phase.PLAYING and turn_player == 0 and waiting_for_human:
		legal_ids = Rules.get_legal_card_ids(hands[0], trick_plays, lead_info, trump_suit, trick_number)
	elif phase == Phase.KITTY_EXCHANGE and declarer_idx == 0:
		for c in hands[0]:
			legal_ids.append(c["id"])

	for card in hands[0]:
		var cv := Button.new()
		cv.set_script(CardViewScript)
		hand_container.add_child(cv)
		var display_trump := trump_suit if declarer_idx != -1 else selected_bid_suit
		cv.setup(card, display_trump, false)

		if phase == Phase.KITTY_EXCHANGE and declarer_idx == 0:
			cv.set_legal(true)
			cv.set_discard_selected(discard_selected_ids.has(card["id"]))
		elif phase == Phase.PLAYING and turn_player == 0 and waiting_for_human:
			cv.set_legal(legal_ids.has(card["id"]))
		else:
			cv.set_legal(false)

		cv.card_clicked.connect(_on_human_card_clicked)
