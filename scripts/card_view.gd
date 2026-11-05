extends Button

signal card_clicked(card_data: Dictionary)

const Rules = preload("res://scripts/card_data.gd")

var card_data: Dictionary = {}
var trump_suit: int = Rules.SUIT_NONE
var is_selected_for_discard: bool = false
var is_legal_play: bool = true
var compact_mode: bool = false

func setup(data: Dictionary, p_trump_suit: int = Rules.SUIT_NONE, p_compact: bool = false) -> void:
	card_data = data
	trump_suit = p_trump_suit
	compact_mode = p_compact
	custom_minimum_size = Vector2(72, 102) if compact_mode else Vector2(86, 124)
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(_on_pressed)
	mouse_entered.connect(func() -> void: queue_redraw())
	mouse_exited.connect(func() -> void: queue_redraw())
	queue_redraw()

func set_legal(legal: bool) -> void:
	is_legal_play = legal
	disabled = not legal
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if legal else Control.CURSOR_FORBIDDEN
	queue_redraw()

func set_discard_selected(sel: bool) -> void:
	is_selected_for_discard = sel
	queue_redraw()

func _on_pressed() -> void:
	if is_legal_play:
		card_clicked.emit(card_data)

func _draw_diamond(center: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(center.x, center.y - ry),
		Vector2(center.x + rx, center.y),
		Vector2(center.x, center.y + ry),
		Vector2(center.x - rx, center.y)
	])
	draw_colored_polygon(pts, col)

func _draw() -> void:
	if card_data.is_empty():
		return

	var w := size.x
	var h := size.y
	var y_offset := -10.0 if (is_hovered() and is_legal_play) or is_selected_for_discard else 0.0
	var rect := Rect2(Vector2(0, y_offset), Vector2(w, h))

	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.38), true)

	var bg_col := Color(0.99, 0.985, 0.96)
	if is_selected_for_discard:
		bg_col = Color(1.0, 0.93, 0.72)
	elif not is_legal_play:
		bg_col = Color(0.76, 0.78, 0.77)

	draw_rect(rect, bg_col, true)

	var border_col := Color(0.22, 0.26, 0.30)
	var border_w := 2.0
	if Rules.is_mighty(card_data, trump_suit):
		border_col = Color(0.92, 0.68, 0.08)
		border_w = 3.5
	elif Rules.is_joker(card_data):
		border_col = Color(0.58, 0.24, 0.88)
		border_w = 3.0
	elif trump_suit != Rules.SUIT_NONE and int(card_data["suit"]) == trump_suit:
		border_col = Color(0.14, 0.65, 0.38)
		border_w = 2.5

	if is_selected_for_discard:
		border_col = Color(0.95, 0.32, 0.18)
		border_w = 3.5

	draw_rect(rect, border_col, false, border_w)

	var font: Font = get_theme_default_font()
	var suit: int = int(card_data["suit"])
	var rank: int = int(card_data["rank"])

	var text_col := Color(0.10, 0.12, 0.16)
	if Rules.is_red_suit(suit):
		text_col = Color(0.82, 0.14, 0.18)
	elif suit == Rules.SUIT_JOKER:
		text_col = Color(0.48, 0.16, 0.78)

	if not is_legal_play:
		text_col = text_col.darkened(0.35)

	if suit == Rules.SUIT_JOKER:
		draw_string(font, rect.position + Vector2(8, 22), "JOKER", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)
		draw_string(font, rect.position + Vector2(0, h * 0.56), "★", HORIZONTAL_ALIGNMENT_CENTER, w, 30 if not compact_mode else 22, text_col)
		draw_string(font, rect.position + Vector2(0, h - 10), "조커", HORIZONTAL_ALIGNMENT_CENTER, w, 13, text_col)
	else:
		var r_str := Rules.rank_str(rank)
		var s_str: String = str(Rules.SUIT_SYMBOLS[suit])
		draw_string(font, rect.position + Vector2(8, 22), r_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if not compact_mode else 14, text_col)
		if suit == Rules.SUIT_DIAMOND:
			_draw_diamond(rect.position + Vector2(14, 34), 4.2 if not compact_mode else 3.5, 5.8 if not compact_mode else 4.8, text_col)
			_draw_diamond(rect.position + Vector2(w * 0.5, h * 0.54), 10.5 if not compact_mode else 8.2, 14.2 if not compact_mode else 11.0, text_col)
		else:
			draw_string(font, rect.position + Vector2(8, 40), s_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if not compact_mode else 13, text_col)
			draw_string(font, rect.position + Vector2(0, h * 0.64), s_str, HORIZONTAL_ALIGNMENT_CENTER, w, 34 if not compact_mode else 26, text_col)

	if Rules.is_mighty(card_data, trump_suit):
		var badge_rect := Rect2(rect.position + Vector2(w - 26, 5), Vector2(21, 18))
		draw_rect(badge_rect, Color(0.95, 0.72, 0.10), true)
		draw_string(font, badge_rect.position + Vector2(0, 14), "M", HORIZONTAL_ALIGNMENT_CENTER, 21, 12, Color(0.1, 0.1, 0.1))
	elif trump_suit != Rules.SUIT_NONE and suit == trump_suit:
		var badge_rect := Rect2(rect.position + Vector2(w - 28, 5), Vector2(23, 17))
		draw_rect(badge_rect, Color(0.14, 0.62, 0.36), true)
		draw_string(font, badge_rect.position + Vector2(0, 13), "기루", HORIZONTAL_ALIGNMENT_CENTER, 23, 10, Color.WHITE)

	if Rules.is_point_card(card_data):
		draw_string(font, rect.position + Vector2(6, h - 8), "★1점", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.72, 0.48, 0.04))