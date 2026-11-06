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
    private bool _isFriendCard;
    private bool _compactMode;
    private bool _miniMode;
    private bool _suitTileMode;
    private Suit _tileSuit = Suit.Spade;
    private bool _tileSelected;

    public void Setup(CardData data, Suit trumpSuit = Suit.None, bool compact = false, bool mini = false)
    {
        _suitTileMode = false;
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

    public void SetupSuitTile(Suit suit, string title = "", bool selected = false)
    {
        _suitTileMode = true;
        _tileSuit = suit;
        _tileSelected = selected;
        CustomMinimumSize = new Vector2(68, 82);
        Size = new Vector2(68, 82);
        Flat = true;
        Disabled = false;
        MouseDefaultCursorShape = CursorShape.PointingHand;
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

    public void SetFriendCard(bool val)
    {
        _isFriendCard = val;
        QueueRedraw();
    }

    private void OnButtonPressed()
    {
        if (_isLegalPlay && !_suitTileMode && _cardData != null)
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
        Font font = ThemeDB.FallbackFont;
        float w = Size.X;
        float h = Size.Y;

        if (_suitTileMode)
        {
            float yOff = (IsHovered() || _tileSelected) ? -4.0f : 0.0f;
            var tRect = new Rect2(new Vector2(0, yOff), new Vector2(w, h));
            DrawRect(new Rect2(tRect.Position + new Vector2(2, 3), tRect.Size), new Color(0, 0, 0, 0.38f), true);
            var tBg = _tileSelected ? new Color(1.0f, 0.95f, 0.78f) : new Color(0.99f, 0.985f, 0.96f);
            DrawRect(tRect, tBg, true);
            var tBorder = _tileSelected ? new Color(0.14f, 0.78f, 0.40f) : new Color(0.26f, 0.30f, 0.34f);
            float tBw = _tileSelected ? 3.2f : 2.0f;
            DrawRect(tRect, tBorder, false, tBw);

            var sCol = new Color(0.10f, 0.12f, 0.16f);
            if (MightyRules.IsRedSuit(_tileSuit))
                sCol = new Color(0.82f, 0.14f, 0.18f);
            else if (_tileSuit == Suit.None)
                sCol = new Color(0.14f, 0.46f, 0.32f);

            if (_tileSuit == Suit.Diamond)
            {
                DrawDiamond(tRect.Position + new Vector2(w * 0.5f, h * 0.42f), 11.5f, 15.5f, sCol);
            }
            else if (_tileSuit == Suit.None)
            {
                DrawCircle(tRect.Position + new Vector2(w * 0.5f, h * 0.42f), 13.0f, new Color(0.14f, 0.46f, 0.32f, 0.18f));
                DrawString(font, tRect.Position + new Vector2(0, h * 0.49f), "NO", HorizontalAlignment.Center, w, 18, sCol);
            }
            else
            {
                string sym = MightyRules.GetSuitSymbol(_tileSuit);
                DrawString(font, tRect.Position + new Vector2(0, h * 0.54f), sym, HorizontalAlignment.Center, w, 32, sCol);
            }

            string shortLbl = _tileSuit switch
            {
                Suit.Spade => "스페이드",
                Suit.Diamond => "다이아",
                Suit.Heart => "하트",
                Suit.Club => "클로버",
                _ => "노기루"
            };
            DrawString(font, tRect.Position + new Vector2(0, h - 10), shortLbl, HorizontalAlignment.Center, w, 12, sCol);
            return;
        }

        if (_cardData == null) return;

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
            DrawString(font, rect.Position + new Vector2(0, h * 0.56f), "★", HorizontalAlignment.Center, w, 30, textCol);
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

        if (_isFriendCard)
        {
            var fRect = new Rect2(rect.Position + new Vector2(w - 30, 25), new Vector2(25, 16));
            DrawRect(fRect, new Color(0.95f, 0.52f, 0.14f), true);
            DrawString(font, fRect.Position + new Vector2(0, 12), "프렌", HorizontalAlignment.Center, 25, 10, Colors.White);
        }

        if (MightyRules.IsPointCard(_cardData))
        {
            DrawString(font, rect.Position + new Vector2(6, h - 8), "★1", HorizontalAlignment.Left, -1, 11, new Color(0.72f, 0.48f, 0.04f));
        }
    }
}