using System;
using Godot;

namespace MightyGame;

public partial class CardView : Button
{
    public event Action<CardData>? CardClicked;

    private CardData? _cardData;
    private Suit _trumpSuit = Suit.None;
    private bool _isSelectedForDiscard;
    private bool _isLegalPlay = true;
    private bool _compactMode;

    public void Setup(CardData data, Suit trumpSuit = Suit.None, bool compact = false)
    {
        _cardData = data;
        _trumpSuit = trumpSuit;
        _compactMode = compact;
        CustomMinimumSize = compact ? new Vector2(72, 102) : new Vector2(86, 124);
        Flat = true;
        MouseDefaultCursorShape = CursorShape.PointingHand;

        Pressed += OnButtonPressed;
        MouseEntered += QueueRedraw;
        MouseExited += QueueRedraw;
        QueueRedraw();
    }

    public void SetLegal(bool legal)
    {
        _isLegalPlay = legal;
        Disabled = !legal;
        MouseDefaultCursorShape = legal ? CursorShape.PointingHand : CursorShape.Forbidden;
        QueueRedraw();
    }

    public void SetDiscardSelected(bool selected)
    {
        _isSelectedForDiscard = selected;
        QueueRedraw();
    }

    private void OnButtonPressed()
    {
        if (_isLegalPlay && _cardData != null)
            CardClicked?.Invoke(_cardData);
    }

    private void DrawDiamond(Vector2 center, float rx, float ry, Color col)
    {
        Vector2[] pts =
        {
            new(center.X, center.Y - ry),
            new(center.X + rx, center.Y),
            new(center.X, center.Y + ry),
            new(center.X - rx, center.Y)
        };
        DrawColoredPolygon(pts, col);
    }

    public override void _Draw()
    {
        if (_cardData == null) return;

        float w = Size.X;
        float h = Size.Y;
        float yOffset = ((IsHovered() && _isLegalPlay) || _isSelectedForDiscard) ? -10.0f : 0.0f;
        var rect = new Rect2(new Vector2(0, yOffset), new Vector2(w, h));

        // 그림자
        DrawRect(new Rect2(rect.Position + new Vector2(3, 4), rect.Size), new Color(0, 0, 0, 0.38f), true);

        // 배경
        var bgCol = new Color(0.99f, 0.985f, 0.96f);
        if (_isSelectedForDiscard)
            bgCol = new Color(1.0f, 0.93f, 0.72f);
        else if (!_isLegalPlay)
            bgCol = new Color(0.76f, 0.78f, 0.77f);

        DrawRect(rect, bgCol, true);

        // 테두리
        var borderCol = new Color(0.22f, 0.26f, 0.30f);
        float borderW = 2.0f;
        if (MightyRules.IsMighty(_cardData, _trumpSuit))
        {
            borderCol = new Color(0.92f, 0.68f, 0.08f);
            borderW = 3.5f;
        }
        else if (MightyRules.IsJoker(_cardData))
        {
            borderCol = new Color(0.58f, 0.24f, 0.88f);
            borderW = 3.0f;
        }
        else if (_trumpSuit != Suit.None && _cardData.Suit == _trumpSuit)
        {
            borderCol = new Color(0.14f, 0.65f, 0.38f);
            borderW = 2.5f;
        }

        if (_isSelectedForDiscard)
        {
            borderCol = new Color(0.95f, 0.32f, 0.18f);
            borderW = 3.5f;
        }

        DrawRect(rect, borderCol, false, borderW);

        Font font = ThemeDB.FallbackFont;
        var textCol = new Color(0.10f, 0.12f, 0.16f);
        if (MightyRules.IsRedSuit(_cardData.Suit))
            textCol = new Color(0.82f, 0.14f, 0.18f);
        else if (_cardData.Suit == Suit.Joker)
            textCol = new Color(0.48f, 0.16f, 0.78f);

        if (!_isLegalPlay)
            textCol = textCol.Darkened(0.35f);

        if (_cardData.Suit == Suit.Joker)
        {
            DrawString(font, rect.Position + new Vector2(8, 22), "JOKER", HorizontalAlignment.Left, -1, 13, textCol);
            DrawString(font, rect.Position + new Vector2(0, h * 0.56f), "★", HorizontalAlignment.Center, w, _compactMode ? 22 : 30, textCol);
            DrawString(font, rect.Position + new Vector2(0, h - 10), "조커", HorizontalAlignment.Center, w, 13, textCol);
        }
        else
        {
            string rStr = MightyRules.GetRankString(_cardData.Rank);
            string sStr = MightyRules.GetSuitSymbol(_cardData.Suit);
            DrawString(font, rect.Position + new Vector2(8, 22), rStr, HorizontalAlignment.Left, -1, _compactMode ? 14 : 17, textCol);
            if (_cardData.Suit == Suit.Diamond)
            {
                DrawDiamond(rect.Position + new Vector2(14, 34), _compactMode ? 3.5f : 4.2f, _compactMode ? 4.8f : 5.8f, textCol);
                DrawDiamond(rect.Position + new Vector2(w * 0.5f, h * 0.54f), _compactMode ? 8.2f : 10.5f, _compactMode ? 11.0f : 14.2f, textCol);
            }
            else
            {
                DrawString(font, rect.Position + new Vector2(8, 40), sStr, HorizontalAlignment.Left, -1, _compactMode ? 13 : 16, textCol);
                DrawString(font, rect.Position + new Vector2(0, h * 0.64f), sStr, HorizontalAlignment.Center, w, _compactMode ? 26 : 34, textCol);
            }
        }

        if (MightyRules.IsMighty(_cardData, _trumpSuit))
        {
            var badgeRect = new Rect2(rect.Position + new Vector2(w - 26, 5), new Vector2(21, 18));
            DrawRect(badgeRect, new Color(0.95f, 0.72f, 0.10f), true);
            DrawString(font, badgeRect.Position + new Vector2(0, 14), "M", HorizontalAlignment.Center, 21, 12, new Color(0.1f, 0.1f, 0.1f));
        }
        else if (_trumpSuit != Suit.None && _cardData.Suit == _trumpSuit)
        {
            var badgeRect = new Rect2(rect.Position + new Vector2(w - 28, 5), new Vector2(23, 17));
            DrawRect(badgeRect, new Color(0.14f, 0.62f, 0.36f), true);
            DrawString(font, badgeRect.Position + new Vector2(0, 13), "기루", HorizontalAlignment.Center, 23, 10, Colors.White);
        }

        if (MightyRules.IsPointCard(_cardData))
        {
            DrawString(font, rect.Position + new Vector2(6, h - 8), "★1점", HorizontalAlignment.Left, -1, 11, new Color(0.72f, 0.48f, 0.04f));
        }
    }
}