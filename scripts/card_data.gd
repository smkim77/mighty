extends RefCounted

const SUIT_NONE := -1
const SUIT_SPADE := 0
const SUIT_DIAMOND := 1
const SUIT_HEART := 2
const SUIT_CLUB := 3
const SUIT_JOKER := 4

const SUIT_SYMBOLS := {
	SUIT_NONE: "노기루",
	SUIT_SPADE: "♠",
	SUIT_DIAMOND: "♦",
	SUIT_HEART: "♥",
	SUIT_CLUB: "♣",
	SUIT_JOKER: "★"
}

const SUIT_NAMES := {
	SUIT_NONE: "노기루",
	SUIT_SPADE: "스페이드 ♠",
	SUIT_DIAMOND: "다이아몬드 ♦",
	SUIT_HEART: "하트 ♥",
	SUIT_CLUB: "클로버 ♣",
	SUIT_JOKER: "조커 ★"
}

static func create_deck() -> Array:
	var deck: Array = []
	for s in [SUIT_SPADE, SUIT_DIAMOND, SUIT_HEART, SUIT_CLUB]:
		for r in range(2, 15):
			deck.append({
				"id": "%d_%d" % [s, r],
				"suit": s,
				"rank": r
			})
	deck.append({
		"id": "joker",
		"suit": SUIT_JOKER,
		"rank": 15
	})
	return deck

static func rank_str(rank: int) -> String:
	match rank:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
		15: return "JOKER"
		_: return str(rank)

static func card_short_name(card: Dictionary) -> String:
	if card.is_empty():
		return ""
	if int(card["suit"]) == SUIT_JOKER:
		return "★조커"
	var s: int = int(card["suit"])
	var r: int = int(card["rank"])
	return "%s%s" % [SUIT_SYMBOLS[s], rank_str(r)]

static func is_red_suit(suit: int) -> bool:
	return suit == SUIT_DIAMOND or suit == SUIT_HEART

static func is_mighty(card: Dictionary, trump_suit: int) -> bool:
	if card.is_empty():
		return false
	if trump_suit == SUIT_SPADE:
		return int(card["suit"]) == SUIT_DIAMOND and int(card["rank"]) == 14
	return int(card["suit"]) == SUIT_SPADE and int(card["rank"]) == 14

static func get_mighty_card_template(trump_suit: int) -> Dictionary:
	if trump_suit == SUIT_SPADE:
		return {"id": "%d_14" % SUIT_DIAMOND, "suit": SUIT_DIAMOND, "rank": 14}
	return {"id": "%d_14" % SUIT_SPADE, "suit": SUIT_SPADE, "rank": 14}

static func is_joker(card: Dictionary) -> bool:
	return not card.is_empty() and int(card["suit"]) == SUIT_JOKER

static func is_joker_call(card: Dictionary, trump_suit: int) -> bool:
	if card.is_empty():
		return false
	if trump_suit == SUIT_CLUB:
		return int(card["suit"]) == SUIT_SPADE and int(card["rank"]) == 3
	return int(card["suit"]) == SUIT_CLUB and int(card["rank"]) == 3

static func is_point_card(card: Dictionary) -> bool:
	if card.is_empty() or int(card["suit"]) == SUIT_JOKER:
		return false
	return int(card["rank"]) >= 10

static func count_point_cards(cards: Array) -> int:
	var pts := 0
	for c in cards:
		if is_point_card(c):
			pts += 1
	return pts

static func is_deal_miss_eligible(hand: Array, trump_suit: int = SUIT_NONE) -> bool:
	var score := 0.0
	for c in hand:
		if is_mighty(c, trump_suit):
			score += 0.0
		elif is_joker(c):
			score -= 1.0
		elif is_point_card(c):
			score += 1.0
	return score <= 0.5

static func sort_hand(hand: Array, trump_suit: int) -> void:
	hand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var weight_a := _sort_weight(a, trump_suit)
		var weight_b := _sort_weight(b, trump_suit)
		return weight_a > weight_b
	)

static func _sort_weight(c: Dictionary, trump_suit: int) -> int:
	if is_mighty(c, trump_suit):
		return 10000
	if is_joker(c):
		return 9000
	if int(c["suit"]) == trump_suit:
		return 8000 + int(c["rank"])
	var suit_order := {
		SUIT_SPADE: 400,
		SUIT_DIAMOND: 300,
		SUIT_HEART: 200,
		SUIT_CLUB: 100
	}
	return int(suit_order.get(int(c["suit"]), 0)) + int(c["rank"])

static func get_legal_card_ids(
	hand: Array,
	trick_plays: Array,
	lead_info: Dictionary,
	trump_suit: int,
	trick_number: int
) -> Array:
	var all_ids: Array = []
	for c in hand:
		all_ids.append(str(c["id"]))

	if trick_plays.is_empty():
		if trick_number == 1 and trump_suit != SUIT_NONE:
			var non_trump_ids: Array = []
			for c in hand:
				if int(c["suit"]) != trump_suit or is_mighty(c, trump_suit):
					non_trump_ids.append(str(c["id"]))
			if not non_trump_ids.is_empty():
				return non_trump_ids
		return all_ids

	var joker_call_active: bool = bool(lead_info.get("joker_call_active", false))
	if joker_call_active:
		var jc_forced: Array = []
		var has_joker := false
		for c in hand:
			if is_joker(c):
				has_joker = true
			if is_joker(c) or is_mighty(c, trump_suit):
				jc_forced.append(str(c["id"]))
		if has_joker and not jc_forced.is_empty():
			return jc_forced

	var req_suit: int = int(lead_info.get("lead_suit", SUIT_NONE))
	if req_suit == SUIT_NONE:
		return all_ids

	var matching_suit_cards: Array = []
	for c in hand:
		if int(c["suit"]) == req_suit and not is_mighty(c, trump_suit):
			matching_suit_cards.append(str(c["id"]))

	if matching_suit_cards.is_empty():
		return all_ids

	var allowed: Array = matching_suit_cards.duplicate()
	for c in hand:
		if is_mighty(c, trump_suit) or is_joker(c):
			var cid := str(c["id"])
			if not allowed.has(cid):
				allowed.append(cid)
	return allowed

static func card_trick_power(
	card: Dictionary,
	lead_info: Dictionary,
	trump_suit: int,
	trick_number: int,
	is_first_card: bool
) -> int:
	if is_mighty(card, trump_suit):
		return 1000
	if is_joker(card):
		var joker_call_active: bool = bool(lead_info.get("joker_call_active", false))
		if trick_number == 1 or trick_number == 10 or joker_call_active:
			return 2 if is_first_card else 1
		return 900
	if trump_suit != SUIT_NONE and int(card["suit"]) == trump_suit:
		return 500 + int(card["rank"])
	var req_suit: int = int(lead_info.get("lead_suit", SUIT_NONE))
	if req_suit != SUIT_NONE and int(card["suit"]) == req_suit:
		return 200 + int(card["rank"])
	return int(card["rank"])

static func determine_trick_winner(
	trick_plays: Array,
	lead_info: Dictionary,
	trump_suit: int,
	trick_number: int
) -> Dictionary:
	var best_play: Dictionary = trick_plays[0]
	var best_power: int = card_trick_power(best_play["card"], lead_info, trump_suit, trick_number, true)

	for i in range(1, trick_plays.size()):
		var play: Dictionary = trick_plays[i]
		var pwr: int = card_trick_power(play["card"], lead_info, trump_suit, trick_number, false)
		if pwr > best_power:
			best_power = pwr
			best_play = play
	return best_play

static func ai_decide_bid(hand: Array, current_high_bid: int) -> Dictionary:
	var best_suit := SUIT_SPADE
	var best_est := 0.0

	for s in [SUIT_SPADE, SUIT_DIAMOND, SUIT_HEART, SUIT_CLUB]:
		var est := 10.5
		var suit_count := 0
		var high_trump := 0
		for c in hand:
			if is_mighty(c, s):
				est += 1.4
			elif is_joker(c):
				est += 1.2
			elif int(c["suit"]) == s:
				suit_count += 1
				if int(c["rank"]) >= 12:
					high_trump += 1
			elif int(c["rank"]) == 14:
				est += 0.7
			elif int(c["rank"]) == 13:
				est += 0.3
		est += max(0, suit_count - 2) * 0.85 + high_trump * 0.45
		if est > best_est:
			best_est = est
			best_suit = s

	var target_bid := clampi(int(floor(best_est)), 0, 17)
	var min_needed := maxi(13, current_high_bid + 1)

	if target_bid >= min_needed and min_needed <= 17:
		return {
			"action": "bid",
			"suit": best_suit,
			"contract": min_needed
		}
	return {"action": "pass"}

static func ai_prepare_declarer(hand13: Array, bid_suit: int) -> Dictionary:
	var trump := bid_suit
	var scored: Array = []
	for c in hand13:
		var keep_score := 0
		if is_mighty(c, trump):
			keep_score = 1000
		elif is_joker(c):
			keep_score = 900
		elif int(c["suit"]) == trump:
			keep_score = 500 + int(c["rank"]) * 10
		elif int(c["rank"]) == 14:
			keep_score = 400
		elif int(c["rank"]) == 13:
			keep_score = 250
		elif is_point_card(c):
			keep_score = 100 + int(c["rank"])
		else:
			keep_score = int(c["rank"])
		scored.append({"card": c, "score": keep_score})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) < int(b["score"])
	)

	var discards: Array = [scored[0]["card"], scored[1]["card"], scored[2]["card"]]
	var remaining: Array = []
	for i in range(3, scored.size()):
		remaining.append(scored[i]["card"])

	var has_mighty := false
	var has_joker := false
	var has_trump_ace := false
	for c in remaining:
		if is_mighty(c, trump):
			has_mighty = true
		elif is_joker(c):
			has_joker = true
		elif int(c["suit"]) == trump and int(c["rank"]) == 14:
			has_trump_ace = true

	var friend_spec: Dictionary
	if not has_mighty:
		var m_card := get_mighty_card_template(trump)
		friend_spec = {
			"type": "card",
			"card_id": str(m_card["id"]),
			"label": "마이티 (%s) 프렌드" % card_short_name(m_card)
		}
	elif not has_joker:
		friend_spec = {
			"type": "card",
			"card_id": "joker",
			"label": "조커 (★) 프렌드"
		}
	elif trump != SUIT_NONE and not has_trump_ace:
		var ta := {"id": "%d_14" % trump, "suit": trump, "rank": 14}
		friend_spec = {
			"type": "card",
			"card_id": str(ta["id"]),
			"label": "기루다 A (%s) 프렌드" % card_short_name(ta)
		}
	else:
		friend_spec = {
			"type": "first_trick",
			"card_id": "",
			"label": "초구 프렌드 (1라운드 승자)"
		}

	return {
		"discards": discards,
		"hand": remaining,
		"friend_spec": friend_spec
	}

static func ai_choose_card(
	hand: Array,
	legal_ids: Array,
	trick_plays: Array,
	lead_info: Dictionary,
	trump_suit: int,
	trick_number: int,
	player_idx: int,
	declarer_idx: int,
	revealed_friend_idx: int,
	holding_friend_card: bool
) -> Dictionary:
	var legal_cards: Array = []
	for c in hand:
		if legal_ids.has(str(c["id"])):
			legal_cards.append(c)

	var is_ruling_team := (player_idx == declarer_idx) or (player_idx == revealed_friend_idx) or holding_friend_card

	if trick_plays.is_empty():
		if not is_ruling_team and trick_number > 1:
			for c in legal_cards:
				if is_joker_call(c, trump_suit):
					return {
						"card": c,
						"joker_call": true,
						"joker_suit": int(c["suit"])
					}

		if is_ruling_team:
			for c in legal_cards:
				if not is_mighty(c, trump_suit) and not is_joker(c) and int(c["rank"]) == 14:
					return {"card": c, "joker_call": false, "joker_suit": int(c["suit"])}
			for c in legal_cards:
				if is_joker(c) and trick_number > 1 and trick_number < 10:
					var req := trump_suit if trump_suit != SUIT_NONE else SUIT_SPADE
					return {"card": c, "joker_call": false, "joker_suit": req}

		var sorted := legal_cards.duplicate()
		sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["rank"]) < int(b["rank"])
		)
		var chosen: Dictionary = sorted[0]
		for c in sorted:
			if not is_mighty(c, trump_suit) and not is_joker(c) and not is_point_card(c):
				chosen = c
				break
		var j_suit := trump_suit if trump_suit != SUIT_NONE else SUIT_SPADE
		return {"card": chosen, "joker_call": false, "joker_suit": j_suit}

	var cur_winner_play := determine_trick_winner(trick_plays, lead_info, trump_suit, trick_number)
	var cur_winner_idx: int = int(cur_winner_play["player"])
	var cur_best_power: int = card_trick_power(
		cur_winner_play["card"],
		lead_info,
		trump_suit,
		trick_number,
		cur_winner_play == trick_plays[0]
	)

	var winner_is_ally := false
	if is_ruling_team:
		winner_is_ally = (cur_winner_idx == declarer_idx or cur_winner_idx == revealed_friend_idx)
	else:
		winner_is_ally = (cur_winner_idx != declarer_idx and cur_winner_idx != revealed_friend_idx and revealed_friend_idx != -1)

	if winner_is_ally and trick_plays.size() >= 3:
		for c in legal_cards:
			if is_point_card(c) and not is_mighty(c, trump_suit) and int(c["rank"]) <= 13:
				return {"card": c, "joker_call": false, "joker_suit": SUIT_SPADE}

	var trick_pts := 0
	for p in trick_plays:
		if is_point_card(p["card"]):
			trick_pts += 1

	if not winner_is_ally and (trick_pts >= 1 or trick_plays.size() == 4):
		var winning_options: Array = []
		for c in legal_cards:
			var pwr := card_trick_power(c, lead_info, trump_suit, trick_number, false)
			if pwr > cur_best_power:
				winning_options.append({"card": c, "power": pwr})
		if not winning_options.is_empty():
			winning_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["power"]) < int(b["power"])
			)
			return {"card": winning_options[0]["card"], "joker_call": false, "joker_suit": SUIT_SPADE}

	var dump_options := legal_cards.duplicate()
	dump_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := (100 if is_point_card(a) else 0) + int(a["rank"]) + (500 if is_mighty(a, trump_suit) or is_joker(a) else 0)
		var pb := (100 if is_point_card(b) else 0) + int(b["rank"]) + (500 if is_mighty(b, trump_suit) or is_joker(b) else 0)
		return pa < pb
	)
	return {"card": dump_options[0], "joker_call": false, "joker_suit": SUIT_SPADE}
