using System;
using System.Collections.Generic;
using System.Linq;
using Godot;

namespace MightyGame;

public enum Suit
{
    None = -1,
    Spade = 0,
    Diamond = 1,
    Heart = 2,
    Club = 3,
    Joker = 4
}

public enum FriendType
{
    None,
    Card,
    FirstTrick
}

public sealed class CardData
{
    public string Id { get; init; } = "";
    public Suit Suit { get; init; } = Suit.Spade;
    public int Rank { get; init; } = 2; // 2..14 (11=J, 12=Q, 13=K, 14=A), 15=Joker
}

public sealed class FriendSpec
{
    public FriendType Type { get; init; } = FriendType.None;
    public string CardId { get; init; } = "";
    public string Label { get; init; } = "노프렌드";
}

public sealed class TrickPlay
{
    public int PlayerIndex { get; init; }
    public CardData Card { get; init; } = new();
}

public sealed class LeadInfo
{
    public Suit LeadSuit { get; set; } = Suit.None;
    public bool JokerCallActive { get; set; } = false;
    public string Note { get; set; } = "";
}

public static class MightyRules
{
    public static string GetSuitSymbol(Suit suit) => suit switch
    {
        Suit.None => "노기루",
        Suit.Spade => "♠",
        Suit.Diamond => "◆",
        Suit.Heart => "♥",
        Suit.Club => "♣",
        Suit.Joker => "★",
        _ => ""
    };

    public static string GetSuitName(Suit suit) => suit switch
    {
        Suit.None => "노기루",
        Suit.Spade => "스페이드 ♠",
        Suit.Diamond => "다이아몬드 ◆",
        Suit.Heart => "하트 ♥",
        Suit.Club => "클로버 ♣",
        Suit.Joker => "조커",
        _ => ""
    };

    public static string GetRankString(int rank) => rank switch
    {
        11 => "J",
        12 => "Q",
        13 => "K",
        14 => "A",
        15 => "JOKER",
        _ => rank.ToString()
    };

    public static string GetCardShortName(CardData? card)
    {
        if (card == null) return "";
        if (card.Suit == Suit.Joker) return "★조커";
        return $"{GetSuitSymbol(card.Suit)}{GetRankString(card.Rank)}";
    }

    public static bool IsRedSuit(Suit suit) => suit == Suit.Diamond || suit == Suit.Heart;

    public static List<CardData> CreateDeck()
    {
        var deck = new List<CardData>(53);
        foreach (var suit in new[] { Suit.Spade, Suit.Diamond, Suit.Heart, Suit.Club })
        {
            for (int r = 2; r <= 14; r++)
            {
                deck.Add(new CardData
                {
                    Id = $"{(int)suit}_{r}",
                    Suit = suit,
                    Rank = r
                });
            }
        }
        deck.Add(new CardData
        {
            Id = "joker",
            Suit = Suit.Joker,
            Rank = 15
        });
        return deck;
    }

    public static void ShuffleDeck(List<CardData> deck, Random rng)
    {
        for (int i = deck.Count - 1; i > 0; i--)
        {
            int j = rng.Next(i + 1);
            (deck[i], deck[j]) = (deck[j], deck[i]);
        }
    }

    public static bool IsMighty(CardData? card, Suit trumpSuit)
    {
        if (card == null) return false;
        if (trumpSuit == Suit.Spade)
            return card.Suit == Suit.Diamond && card.Rank == 14;
        return card.Suit == Suit.Spade && card.Rank == 14;
    }

    public static CardData GetMightyCardTemplate(Suit trumpSuit)
    {
        if (trumpSuit == Suit.Spade)
            return new CardData { Id = $"{(int)Suit.Diamond}_14", Suit = Suit.Diamond, Rank = 14 };
        return new CardData { Id = $"{(int)Suit.Spade}_14", Suit = Suit.Spade, Rank = 14 };
    }

    public static bool IsJoker(CardData? card) => card != null && card.Suit == Suit.Joker;

    public static bool IsJokerCall(CardData? card, Suit trumpSuit)
    {
        if (card == null) return false;
        if (trumpSuit == Suit.Club)
            return card.Suit == Suit.Spade && card.Rank == 3;
        return card.Suit == Suit.Club && card.Rank == 3;
    }

    public static bool IsPointCard(CardData? card)
    {
        if (card == null || card.Suit == Suit.Joker) return false;
        return card.Rank >= 10;
    }

    public static int CountPointCards(IEnumerable<CardData> cards) => cards.Count(IsPointCard);

    public static bool IsDealMissEligible(IEnumerable<CardData> hand, Suit trumpSuit)
    {
        double score = 0.0;
        foreach (var c in hand)
        {
            if (IsMighty(c, trumpSuit)) score += 0.0;
            else if (IsJoker(c)) score -= 1.0;
            else if (IsPointCard(c)) score += 1.0;
        }
        return score <= 0.5;
    }

    public static void SortHand(List<CardData> hand, Suit trumpSuit)
    {
        hand.Sort((a, b) => GetSortWeight(b, trumpSuit).CompareTo(GetSortWeight(a, trumpSuit)));
    }

    private static int GetSortWeight(CardData c, Suit trumpSuit)
    {
        if (IsMighty(c, trumpSuit)) return 10000;
        if (IsJoker(c)) return 9000;
        if (c.Suit == trumpSuit) return 8000 + c.Rank;

        int suitBase = c.Suit switch
        {
            Suit.Spade => 400,
            Suit.Diamond => 300,
            Suit.Heart => 200,
            Suit.Club => 100,
            _ => 0
        };
        return suitBase + c.Rank;
    }

    public static HashSet<string> GetLegalCardIds(
        List<CardData> hand,
        List<TrickPlay> trickPlays,
        LeadInfo leadInfo,
        Suit trumpSuit,
        int trickNumber)
    {
        var allIds = hand.Select(c => c.Id).ToHashSet();

        // 선공일 때
        if (trickPlays.Count == 0)
        {
            if (trickNumber == 1 && trumpSuit != Suit.None)
            {
                var nonTrump = hand
                    .Where(c => c.Suit != trumpSuit || IsMighty(c, trumpSuit))
                    .Select(c => c.Id)
                    .ToHashSet();
                if (nonTrump.Count > 0)
                    return nonTrump;
            }
            return allIds;
        }

        // 후공일 때: 조커 콜 확인
        if (leadInfo.JokerCallActive && hand.Any(IsJoker))
        {
            var forcedIds = hand
                .Where(c => IsJoker(c) || IsMighty(c, trumpSuit))
                .Select(c => c.Id)
                .ToHashSet();
            if (forcedIds.Count > 0)
                return forcedIds;
        }

        if (leadInfo.LeadSuit == Suit.None)
            return allIds;

        var matchingSuitIds = hand
            .Where(c => c.Suit == leadInfo.LeadSuit && !IsMighty(c, trumpSuit))
            .Select(c => c.Id)
            .ToHashSet();

        if (matchingSuitIds.Count == 0)
            return allIds;

        // 선문양 보유 시: 해당 문양 + 마이티 + 조커 가능
        foreach (var c in hand)
        {
            if (IsMighty(c, trumpSuit) || IsJoker(c))
                matchingSuitIds.Add(c.Id);
        }
        return matchingSuitIds;
    }

    public static int GetCardTrickPower(
        CardData card,
        LeadInfo leadInfo,
        Suit trumpSuit,
        int trickNumber,
        bool isFirstCard)
    {
        if (IsMighty(card, trumpSuit))
            return 1000;

        if (IsJoker(card))
        {
            if (trickNumber == 1 || trickNumber == 10 || leadInfo.JokerCallActive)
                return isFirstCard ? 2 : 1;
            return 900;
        }

        if (trumpSuit != Suit.None && card.Suit == trumpSuit)
            return 500 + card.Rank;

        if (leadInfo.LeadSuit != Suit.None && card.Suit == leadInfo.LeadSuit)
            return 200 + card.Rank;

        return card.Rank;
    }

    public static TrickPlay DetermineTrickWinner(
        List<TrickPlay> trickPlays,
        LeadInfo leadInfo,
        Suit trumpSuit,
        int trickNumber)
    {
        var bestPlay = trickPlays[0];
        int bestPower = GetCardTrickPower(bestPlay.Card, leadInfo, trumpSuit, trickNumber, true);

        for (int i = 1; i < trickPlays.Count; i++)
        {
            var play = trickPlays[i];
            int power = GetCardTrickPower(play.Card, leadInfo, trumpSuit, trickNumber, false);
            if (power > bestPower)
            {
                bestPower = power;
                bestPlay = play;
            }
        }
        return bestPlay;
    }

    // AI 경매 판단
    public static (bool ShouldBid, Suit BidSuit, int ContractScore) AiDecideBid(List<CardData> hand, int currentHighBid)
    {
        Suit bestSuit = Suit.Spade;
        double bestEstimate = 0.0;

        foreach (var s in new[] { Suit.Spade, Suit.Diamond, Suit.Heart, Suit.Club })
        {
            double est = 10.5;
            int suitCount = 0;
            int highTrump = 0;

            foreach (var c in hand)
            {
                if (IsMighty(c, s)) est += 1.4;
                else if (IsJoker(c)) est += 1.2;
                else if (c.Suit == s)
                {
                    suitCount++;
                    if (c.Rank >= 12) highTrump++;
                }
                else if (c.Rank == 14) est += 0.7;
                else if (c.Rank == 13) est += 0.3;
            }

            est += Math.Max(0, suitCount - 2) * 0.85 + highTrump * 0.45;
            if (est > bestEstimate)
            {
                bestEstimate = est;
                bestSuit = s;
            }
        }

        int targetBid = Math.Clamp((int)Math.Floor(bestEstimate), 0, 17);
        int minNeeded = Math.Max(13, currentHighBid + 1);

        if (targetBid >= minNeeded && minNeeded <= 17)
            return (true, bestSuit, minNeeded);

        return (false, Suit.Spade, 0);
    }

    // AI 주공 바닥패 버리기 & 프렌드 선택
    public static (List<CardData> Discards, List<CardData> RemainingHand, FriendSpec Friend) AiPrepareDeclarer(
        List<CardData> hand13,
        Suit trumpSuit)
    {
        var scored = hand13.Select(c =>
        {
            int keepScore;
            if (IsMighty(c, trumpSuit)) keepScore = 1000;
            else if (IsJoker(c)) keepScore = 900;
            else if (c.Suit == trumpSuit) keepScore = 500 + c.Rank * 10;
            else if (c.Rank == 14) keepScore = 400;
            else if (c.Rank == 13) keepScore = 250;
            else if (IsPointCard(c)) keepScore = 100 + c.Rank;
            else keepScore = c.Rank;
            return (Card: c, Score: keepScore);
        }).OrderBy(x => x.Score).ToList();

        var discards = scored.Take(3).Select(x => x.Card).ToList();
        var remaining = scored.Skip(3).Select(x => x.Card).ToList();

        bool hasMighty = remaining.Any(c => IsMighty(c, trumpSuit));
        bool hasJoker = remaining.Any(IsJoker);
        bool hasTrumpAce = trumpSuit != Suit.None && remaining.Any(c => c.Suit == trumpSuit && c.Rank == 14);

        FriendSpec friendSpec;
        if (!hasMighty)
        {
            var m = GetMightyCardTemplate(trumpSuit);
            friendSpec = new FriendSpec
            {
                Type = FriendType.Card,
                CardId = m.Id,
                Label = $"마이티 ({GetCardShortName(m)}) 프렌드"
            };
        }
        else if (!hasJoker)
        {
            friendSpec = new FriendSpec
            {
                Type = FriendType.Card,
                CardId = "joker",
                Label = "조커 (🃏) 프렌드"
            };
        }
        else if (trumpSuit != Suit.None && !hasTrumpAce)
        {
            var ta = new CardData { Id = $"{(int)trumpSuit}_14", Suit = trumpSuit, Rank = 14 };
            friendSpec = new FriendSpec
            {
                Type = FriendType.Card,
                CardId = ta.Id,
                Label = $"기루다 A ({GetCardShortName(ta)}) 프렌드"
            };
        }
        else
        {
            friendSpec = new FriendSpec
            {
                Type = FriendType.FirstTrick,
                CardId = "",
                Label = "초구 프렌드 (1라운드 승자)"
            };
        }

        return (discards, remaining, friendSpec);
    }

    // AI 카드 내기 판단
    public static (CardData Card, bool DeclareJokerCall, Suit JokerRequestedSuit) AiChooseCard(
        List<CardData> hand,
        HashSet<string> legalIds,
        List<TrickPlay> trickPlays,
        LeadInfo leadInfo,
        Suit trumpSuit,
        int trickNumber,
        int playerIdx,
        int declarerIdx,
        int revealedFriendIdx,
        bool holdingFriendCard)
    {
        var legalCards = hand.Where(c => legalIds.Contains(c.Id)).ToList();
        bool isRulingTeam = (playerIdx == declarerIdx) || (playerIdx == revealedFriendIdx) || holdingFriendCard;
        Suit defaultJokerSuit = trumpSuit != Suit.None ? trumpSuit : Suit.Spade;

        // 선공일 때
        if (trickPlays.Count == 0)
        {
            if (!isRulingTeam && trickNumber > 1)
            {
                var jc = legalCards.FirstOrDefault(c => IsJokerCall(c, trumpSuit));
                if (jc != null)
                    return (jc, true, jc.Suit);
            }

            if (isRulingTeam)
            {
                var sideAce = legalCards.FirstOrDefault(c => !IsMighty(c, trumpSuit) && !IsJoker(c) && c.Rank == 14);
                if (sideAce != null)
                    return (sideAce, false, sideAce.Suit);

                var joker = legalCards.FirstOrDefault(c => IsJoker(c) && trickNumber > 1 && trickNumber < 10);
                if (joker != null)
                    return (joker, false, defaultJokerSuit);
            }

            var lowNonPoint = legalCards
                .Where(c => !IsMighty(c, trumpSuit) && !IsJoker(c) && !IsPointCard(c))
                .OrderBy(c => c.Rank)
                .FirstOrDefault();

            var chosen = lowNonPoint ?? legalCards.OrderBy(c => c.Rank).First();
            return (chosen, false, defaultJokerSuit);
        }

        // 후공일 때
        var curWinnerPlay = DetermineTrickWinner(trickPlays, leadInfo, trumpSuit, trickNumber);
        int curWinnerIdx = curWinnerPlay.PlayerIndex;
        int curBestPower = GetCardTrickPower(
            curWinnerPlay.Card,
            leadInfo,
            trumpSuit,
            trickNumber,
            curWinnerPlay == trickPlays[0]);

        bool winnerIsAlly = isRulingTeam
            ? (curWinnerIdx == declarerIdx || curWinnerIdx == revealedFriendIdx)
            : (curWinnerIdx != declarerIdx && curWinnerIdx != revealedFriendIdx && revealedFriendIdx != -1);

        if (winnerIsAlly && trickPlays.Count >= 3)
        {
            var pointGift = legalCards.FirstOrDefault(c => IsPointCard(c) && !IsMighty(c, trumpSuit) && c.Rank <= 13);
            if (pointGift != null)
                return (pointGift, false, Suit.Spade);
        }

        int trickPts = trickPlays.Count(p => IsPointCard(p.Card));
        if (!winnerIsAlly && (trickPts >= 1 || trickPlays.Count == 4))
        {
            var winningCard = legalCards
                .Select(c => (Card: c, Power: GetCardTrickPower(c, leadInfo, trumpSuit, trickNumber, false)))
                .Where(x => x.Power > curBestPower)
                .OrderBy(x => x.Power)
                .Select(x => x.Card)
                .FirstOrDefault();

            if (winningCard != null)
                return (winningCard, false, Suit.Spade);
        }

        var dump = legalCards
            .OrderBy(c => (IsPointCard(c) ? 100 : 0) + c.Rank + (IsMighty(c, trumpSuit) || IsJoker(c) ? 500 : 0))
            .First();

        return (dump, false, Suit.Spade);
    }
}
