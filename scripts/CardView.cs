using System;
using Godot;

namespace MightyGame;

public partial class CardView : Button
{
    public event Action<CardData>? CardClicked;

    private CardData? _cardData;
    private Suit _trumpSuit = Suit.None;
    private bool _isSelectedForDiscard;
    private bool _isLegalPlay;
    private bool _isDimmed;
    private bool _compactMode;
    private bool _miniMode;

    public void Setup(CardData data, Suit trumpSuit = Suit.None, bool compact = false, bool mini = false)
    {
        _cardData = data;
        _trumpSuit = trumpSuit;
        _compactMode = compact;
        _miniMode = mini;
        if (_miniMode)
        {
            CustomMinimumSize = new Vector2(40, 54);
            Size = new Vector2(40, 54);
        }
        else
        {
            CustomMinimumSize = compact ? new Vector2(72, 102) : new Vector2(86, 124);
        }
        Flat = true;
        Disabled = true;
        MouseDefaultCursorShape = CursorShape.Arrow;

        Pressed += OnButtonPressed;
        MouseEntered += QueueRedraw;
        MouseExited += QueueRedraw;
        QueueRedraw();
    }

    public void SetLegal(bool legal, bool dimWhenIllegal = false)
    {
        _isLegalPlay = legal;
        _isDimmed = !legal && dimWhenIllegal;
        Disabled = !legal;
        MouseDefaultCursorShape = legal ? CursorShape.PointingHand : CursorShape.Arrow;
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
        float yOffset = (!_miniMode && ((IsHovered() && _isLegalPlay) || _isSelectedForDiscard)) ? -10.0f : 0.0f;
        var rect = new Rect2(new Vector2(0, yOffset), new Vector2(w, h));

        var shadowOffset = _miniMode ? new Vector2(2, 2) : new Vector2(3, 4);
        DrawRect(new Rect2(rect.Position + shadowOffset, rect.Size), new Color(0, 0, 0, 0.38f), true);

        var bgCol = new Color(0.99f, 0.985f, 0.96f);
        if (_isSelectedForDiscard)
            bgCol = new Color(1.0f, 0.93f, 0.72f);
        else if (_isDimmed && !_miniMode)
            bgCol = new Color(0.84f, 0.86f, 0.85f);

        DrawRect(rect, bgCol, true);

        var borderCol = new Color(0.22f, 0.26f, 0.30f);
        float borderW = _miniMode ? 1.5f : 2.0f;
        if (_isSelectedForDiscard)
        {
            borderCol = new Color(0.95f, 0.32f, 0.18f);
            borderW = 3.5f;
        }
        else if (_isLegalPlay && !_miniMode)
        {
            borderCol = new Color(0.14f, 0.75f, 0.38f);
            borderW = 3.2f;
        }

        DrawRect(rect, borderCol, false, borderW);

        Font font = ThemeDB.FallbackFont;
        var textCol = new Color(0.10f, 0.12f, 0.16f);
        if (MightyRules.IsRedSuit(_cardData.Suit))
            textCol = new Color(0.82f, 0.14f, 0.18f);
        else if (_cardData.Suit == Suit.Joker)
            textCol = new Color(0.48f, 0.16f, 0.78f);

        if (_isDimmed && !_miniMode)
            textCol = textCol.Darkened(0.25f);

        if (_miniMode)
        {
            if (_cardData.Suit == Suit.Joker)
            {
                DrawString(font, rect.Position + new Vector2(3, 14), "JK", HorizontalAlignment.Left, -1, 11, textCol);
                DrawString(font, rect.Position + new Vector2(0, h * 0.68f), "★", HorizontalAlignment.Center, w, 18, textCol);
            }
            else
            {
                string rStrM = MightyRules.GetRankString(_cardData.Rank);
                string sStrM = MightyRules.GetSuitSymbol(_cardData.Suit);
                DrawString(font, rect.Position + new Vector2(3, 14), rStrM, HorizontalAlignment.Left, -1, 12, textCol);
                if (_cardData.Suit == Suit.Diamond)
                {
                    DrawDiamond(rect.Position + new Vector2(8, 23), 3.0f, 4.0f, textCol);
                    DrawDiamond(rect.Position + new Vector2(w * 0.62f, h * 0.64f), 5.5f, 7.2f, textCol);
                }
                else
                {
                    DrawString(font, rect.Position + new Vector2(3, 27), sStrM, HorizontalAlignment.Left, -1, 11, textCol);
                    DrawString(font, rect.Position + new Vector2(6, h * 0.76f), sStrM, HorizontalAlignment.Center, w - 6, 17, textCol);
                }
            }
            return;
        }

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