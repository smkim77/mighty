using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Godot;

namespace MightyGame;

public partial class Main : Control
{
    private enum Phase
    {
        Bidding,
        KittyExchange,
        Playing,
        RoundOver
    }

    private static readonly string[] PlayerNames =
    {
        "나 (플레이어)",
        "AI 민수",
        "AI 지영",
        "AI 현우",
        "AI 수진"
    };

    private readonly Random _rng = new();
    private Phase _phase = Phase.Bidding;
    private readonly List<CardData>[] _hands = { new(), new(), new(), new(), new() };
    private List<CardData> _kitty = new();
    private readonly List<CardData>[] _capturedPoints = { new(), new(), new(), new(), new() };
    private readonly int[] _totalScores = new int[5];

    // 경매 상태
    private int _currentBidder;
    private readonly bool[] _passedPlayers = new bool[5];
    private int _highestBid;
    private Suit _highestBidSuit = Suit.Spade;
    private int _declarerIdx = -1;
    private Suit _selectedBidSuit = Suit.Spade;
    private int _selectedBidScore = 13;

    // 주공 / 프렌드 상태
    private Suit _trumpSuit = Suit.None;
    private int _contractScore = 13;
    private readonly HashSet<string> _discardSelectedIds = new();
    private FriendSpec _friendSpec = new();
    private int _friendPlayerIdx = -1;
    private bool _friendRevealed;
    private int _selectedFriendOption;

    // 트릭 진행 상태
    private int _trickNumber = 1;
    private int _turnPlayer;
    private int _trickLeader;
    private readonly List<TrickPlay> _trickPlays = new();
    private LeadInfo _leadInfo = new();
    private bool _waitingForHuman;
    private int _roundGeneration;

    // UI 참조
    private Label _topStatusLabel = null!;
    private Label _contractInfoLabel = null!;
    private Label _teamScoreLabel = null!;
    private Label _logLabel = null!;
    private readonly List<PanelContainer> _playerSeatPanels = new();
    private readonly List<Label> _playerRoleLabels = new();
    private readonly List<Label> _playerCardCountLabels = new();
    private readonly List<Label> _playerCapturedLabels = new();
    private readonly List<Label> _playerBubbleLabels = new();

    private readonly List<VBoxContainer> _trickSlots = new();
    private Label _trickInfoBanner = null!;
    private HBoxContainer _handContainer = null!;
    private Label _handHintLabel = null!;

    private PanelContainer _centerModal = null!;
    private VBoxContainer _modalVbox = null!;
    private PanelContainer _helpPanel = null!;

    public override void _Ready()
    {
        SetupKoreanFont();
        BuildUi();
        StartNewRound();
    }

    private static void SetupKoreanFont()
    {
        if (ResourceLoader.Exists("res://fonts/NanumSquareRoundB.ttf"))
        {
            var bundledFont = GD.Load<FontFile>("res://fonts/NanumSquareRoundB.ttf");
            if (bundledFont != null)
            {
                ThemeDB.FallbackFont = bundledFont;
                return;
            }
        }
        var sysFont = new SystemFont
        {
            FontNames = new[]
            {
                "Malgun Gothic",
                "맑은 고딕",
                "Apple SD Gothic Neo",
                "Noto Sans CJK KR",
                "Noto Sans KR",
                "NanumGothic",
                "Segoe UI Symbol",
                "Arial"
            }
        };
        ThemeDB.FallbackFont = sysFont;
    }

    private static StyleBoxFlat MakePanelStyle(Color bg, Color border, int radius = 10, int borderW = 2)
    {
        var sb = new StyleBoxFlat
        {
            BgColor = bg,
            BorderColor = border,
            ContentMarginLeft = 12,
            ContentMarginRight = 12,
            ContentMarginTop = 8,
            ContentMarginBottom = 8
        };
        sb.SetBorderWidthAll(borderW);
        sb.SetCornerRadiusAll(radius);
        return sb;
    }

    private void BuildUi()
    {
        var bg = new ColorRect
        {
            Color = new Color(0.055f, 0.19f, 0.135f)
        };
        bg.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(bg);

        var mainVbox = new VBoxContainer();
        mainVbox.SetAnchorsPreset(LayoutPreset.FullRect);
        mainVbox.AddThemeConstantOverride("separation", 8);
        AddChild(mainVbox);

        // 1. 상단 정보 바
        var topBar = new PanelContainer();
        topBar.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.04f, 0.11f, 0.08f, 0.95f), new Color(0.25f, 0.48f, 0.35f), 0, 1));
        mainVbox.AddChild(topBar);

        var topHbox = new HBoxContainer();
        topHbox.AddThemeConstantOverride("separation", 18);
        topBar.AddChild(topHbox);

        var titleLbl = new Label { Text = "♠ 마이티 (MIGHTY C#)" };
        titleLbl.AddThemeFontSizeOverride("font_size", 20);
        titleLbl.AddThemeColorOverride("font_color", new Color(0.98f, 0.84f, 0.28f));
        topHbox.AddChild(titleLbl);

        _topStatusLabel = new Label { Text = "경매 준비 중" };
        _topStatusLabel.AddThemeFontSizeOverride("font_size", 15);
        _topStatusLabel.AddThemeColorOverride("font_color", new Color(0.85f, 0.96f, 0.90f));
        topHbox.AddChild(_topStatusLabel);

        topHbox.AddChild(new VSeparator());

        _contractInfoLabel = new Label
        {
            Text = "공약: 미정 | 주공: 미정 | 프렌드: 미정",
            SizeFlagsHorizontal = SizeFlags.ExpandFill
        };
        _contractInfoLabel.AddThemeFontSizeOverride("font_size", 15);
        _contractInfoLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.95f, 0.78f));
        topHbox.AddChild(_contractInfoLabel);

        _teamScoreLabel = new Label { Text = "여당: 0점 | 야당: 0점" };
        _teamScoreLabel.AddThemeFontSizeOverride("font_size", 15);
        _teamScoreLabel.AddThemeColorOverride("font_color", new Color(0.75f, 0.95f, 1.0f));
        topHbox.AddChild(_teamScoreLabel);

        var helpBtn = new Button { Text = "규칙 안내" };
        helpBtn.Pressed += () => _helpPanel.Visible = !_helpPanel.Visible;
        topHbox.AddChild(helpBtn);

        var restartBtn = new Button { Text = "새 판 시작" };
        restartBtn.Pressed += StartNewRound;
        topHbox.AddChild(restartBtn);

        // 2. 중앙 테이블 영역
        var tableArea = new Control
        {
            SizeFlagsVertical = SizeFlags.ExpandFill
        };
        mainVbox.AddChild(tableArea);

        Vector2[] seatAnchors =
        {
            new(0.02f, 0.74f),
            new(0.02f, 0.40f),
            new(0.02f, 0.04f),
            new(0.78f, 0.04f),
            new(0.78f, 0.40f)
        };

        for (int i = 0; i < 5; i++)
        {
            var seat = new PanelContainer
            {
                CustomMinimumSize = new Vector2(245, 118),
                AnchorLeft = seatAnchors[i].X,
                AnchorTop = seatAnchors[i].Y,
                AnchorRight = seatAnchors[i].X,
                AnchorBottom = seatAnchors[i].Y,
                OffsetRight = 245,
                OffsetBottom = 118
            };
            seat.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.07f, 0.16f, 0.12f, 0.92f), new Color(0.28f, 0.52f, 0.38f), 10, 2));
            tableArea.AddChild(seat);
            _playerSeatPanels.Add(seat);

            var sv = new VBoxContainer();
            sv.AddThemeConstantOverride("separation", 4);
            seat.AddChild(sv);

            var headerHb = new HBoxContainer();
            sv.AddChild(headerHb);

            var nameLbl = new Label
            {
                Text = PlayerNames[i],
                SizeFlagsHorizontal = SizeFlags.ExpandFill
            };
            nameLbl.AddThemeFontSizeOverride("font_size", 15);
            nameLbl.AddThemeColorOverride("font_color", Colors.White);
            headerHb.AddChild(nameLbl);

            var roleLbl = new Label { Text = "대기" };
            roleLbl.AddThemeFontSizeOverride("font_size", 13);
            roleLbl.AddThemeColorOverride("font_color", new Color(0.95f, 0.82f, 0.30f));
            headerHb.AddChild(roleLbl);
            _playerRoleLabels.Add(roleLbl);

            var countLbl = new Label { Text = "남은 패: 10장 | 누적: 0점" };
            countLbl.AddThemeFontSizeOverride("font_size", 13);
            countLbl.AddThemeColorOverride("font_color", new Color(0.80f, 0.90f, 0.84f));
            sv.AddChild(countLbl);
            _playerCardCountLabels.Add(countLbl);

            var capLbl = new Label
            {
                Text = "획득 점수패(0점): 없음",
                AutowrapMode = TextServer.AutowrapMode.WordSmart
            };
            capLbl.AddThemeFontSizeOverride("font_size", 12);
            capLbl.AddThemeColorOverride("font_color", new Color(0.98f, 0.88f, 0.55f));
            sv.AddChild(capLbl);
            _playerCapturedLabels.Add(capLbl);

            var bubbleLbl = new Label { Text = "" };
            bubbleLbl.AddThemeFontSizeOverride("font_size", 13);
            bubbleLbl.AddThemeColorOverride("font_color", new Color(0.55f, 0.95f, 0.72f));
            sv.AddChild(bubbleLbl);
            _playerBubbleLabels.Add(bubbleLbl);
        }

        // 중앙 트릭 보드
        var trickBoard = new PanelContainer
        {
            AnchorLeft = 0.24f,
            AnchorRight = 0.76f,
            AnchorTop = 0.04f,
            AnchorBottom = 0.94f
        };
        trickBoard.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.045f, 0.15f, 0.105f, 0.85f), new Color(0.22f, 0.45f, 0.32f), 16, 2));
        tableArea.AddChild(trickBoard);

        var boardVbox = new VBoxContainer();
        boardVbox.AddThemeConstantOverride("separation", 8);
        trickBoard.AddChild(boardVbox);

        _trickInfoBanner = new Label
        {
            Text = "경매를 시작합니다",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _trickInfoBanner.AddThemeFontSizeOverride("font_size", 16);
        _trickInfoBanner.AddThemeColorOverride("font_color", new Color(1.0f, 0.92f, 0.60f));
        boardVbox.AddChild(_trickInfoBanner);

        _logLabel = new Label
        {
            Text = "",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _logLabel.AddThemeFontSizeOverride("font_size", 14);
        _logLabel.AddThemeColorOverride("font_color", new Color(0.78f, 0.95f, 0.85f));
        boardVbox.AddChild(_logLabel);

        var slotsHbox = new HBoxContainer
        {
            Alignment = BoxContainer.AlignmentMode.Center,
            SizeFlagsVertical = SizeFlags.ExpandFill
        };
        slotsHbox.AddThemeConstantOverride("separation", 16);
        boardVbox.AddChild(slotsHbox);

        for (int i = 0; i < 5; i++)
        {
            var slotV = new VBoxContainer
            {
                Alignment = BoxContainer.AlignmentMode.Center,
                CustomMinimumSize = new Vector2(96, 150)
            };
            slotsHbox.AddChild(slotV);
            _trickSlots.Add(slotV);
        }

        _centerModal = new PanelContainer
        {
            AnchorLeft = 0.25f,
            AnchorRight = 0.75f,
            AnchorTop = 0.14f,
            AnchorBottom = 0.88f
        };
        _centerModal.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.08f, 0.13f, 0.16f, 0.97f), new Color(0.88f, 0.72f, 0.24f), 14, 2));
        tableArea.AddChild(_centerModal);

        _modalVbox = new VBoxContainer
        {
            Alignment = BoxContainer.AlignmentMode.Center
        };
        _modalVbox.AddThemeConstantOverride("separation", 10);
        _centerModal.AddChild(_modalVbox);

        // 3. 하단 내 손패 영역
        var bottomPanel = new PanelContainer
        {
            CustomMinimumSize = new Vector2(0, 190)
        };
        bottomPanel.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.04f, 0.11f, 0.08f, 0.96f), new Color(0.26f, 0.50f, 0.36f), 0, 1));
        mainVbox.AddChild(bottomPanel);

        var bottomVbox = new VBoxContainer();
        bottomVbox.AddThemeConstantOverride("separation", 6);
        bottomPanel.AddChild(bottomVbox);

        _handHintLabel = new Label
        {
            Text = "내 손패",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _handHintLabel.AddThemeFontSizeOverride("font_size", 14);
        _handHintLabel.AddThemeColorOverride("font_color", new Color(0.92f, 0.96f, 0.88f));
        bottomVbox.AddChild(_handHintLabel);

        var scroll = new ScrollContainer
        {
            SizeFlagsVertical = SizeFlags.ExpandFill,
            VerticalScrollMode = ScrollContainer.ScrollMode.Disabled
        };
        bottomVbox.AddChild(scroll);

        _handContainer = new HBoxContainer
        {
            Alignment = BoxContainer.AlignmentMode.Center,
            SizeFlagsHorizontal = SizeFlags.ExpandFill
        };
        _handContainer.AddThemeConstantOverride("separation", 8);
        scroll.AddChild(_handContainer);

        BuildHelpOverlay();
    }

    private void BuildHelpOverlay()
    {
        _helpPanel = new PanelContainer
        {
            Visible = false,
            AnchorLeft = 0.18f,
            AnchorRight = 0.82f,
            AnchorTop = 0.10f,
            AnchorBottom = 0.86f
        };
        _helpPanel.AddThemeStyleboxOverride("panel", MakePanelStyle(new Color(0.06f, 0.10f, 0.14f, 0.98f), new Color(0.92f, 0.76f, 0.25f), 14, 2));
        AddChild(_helpPanel);

        var hv = new VBoxContainer();
        hv.AddThemeConstantOverride("separation", 10);
        _helpPanel.AddChild(hv);

        var htitle = new Label { Text = "📖 마이티(Mighty) 핵심 규칙 안내" };
        htitle.AddThemeFontSizeOverride("font_size", 20);
        htitle.AddThemeColorOverride("font_color", new Color(0.98f, 0.84f, 0.28f));
        hv.AddChild(htitle);

        var hbody = new Label
        {
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            SizeFlagsVertical = SizeFlags.ExpandFill,
            Text =
                "1. 인원 및 구성: 5명이 53장(조커 포함)으로 플레이합니다. 각 10장씩 배분하고 3장은 바닥패로 남깁니다.\n\n" +
                "2. 경매(공약): 최소 13점부터 기루다(으뜸패) 문양과 목표 점수를 선언합니다. 최고 점수를 부른 사람이 '주공(대통령)'이 됩니다.\n\n" +
                "3. 바닥패 교환 & 프렌드 지정: 주공은 바닥패 3장을 가져와 13장 중 3장을 버리고, 함께 팀(여당)이 될 '프렌드' 카드를 지정합니다.\n" +
                "   - 프렌드로 지정된 카드를 가진 플레이어는 해당 카드를 내기 전까지 정체가 숨겨집니다.\n\n" +
                "4. 특수 카드 서열: 마이티(♠A, 단 스페이드가 기루다면 ♦A) > 조커(★) > 기루다(A~2) > 선공 문양(A~2)\n" +
                "   - 초구(1라운드)에는 기루다 선공이 불가하며, 초구와 막구(10라운드)에는 조커의 효력이 없습니다.\n" +
                "   - 조커 콜(♣3, 클로버가 기루다면 ♠3)로 선공하면 조커 보유자는 반드시 조커를 내야 합니다.\n\n" +
                "5. 승리 조건: 점수 카드(A, K, Q, J, 10 - 총 20점)를 여당(주공+프렌드)이 공약 점수 이상 획득하면 여당 승리, 못 미치면 야당(3명)이 승리합니다!"
        };
        hv.AddChild(hbody);

        var closeBtn = new Button { Text = "닫기" };
        closeBtn.Pressed += () => _helpPanel.Visible = false;
        hv.AddChild(closeBtn);
    }

    private async Task DelaySeconds(double seconds)
    {
        await ToSignal(GetTree().CreateTimer(seconds), SceneTreeTimer.SignalName.Timeout);
    }

    // =========================================================================
    // 라운드 시작 및 배분
    // =========================================================================
    private void StartNewRound()
    {
        _roundGeneration++;
        _phase = Phase.Bidding;

        var deck = MightyRules.CreateDeck();
        MightyRules.ShuffleDeck(deck, _rng);

        for (int i = 0; i < 5; i++)
        {
            _hands[i] = deck.GetRange(i * 10, 10);
            MightyRules.SortHand(_hands[i], Suit.None);
            _capturedPoints[i].Clear();
            _passedPlayers[i] = false;
            _playerBubbleLabels[i].Text = "";
        }

        _kitty = deck.GetRange(50, 3);

        _currentBidder = 0;
        _highestBid = 0;
        _highestBidSuit = Suit.Spade;
        _declarerIdx = -1;
        _trumpSuit = Suit.None;
        _contractScore = 13;
        _selectedBidSuit = Suit.Spade;
        _selectedBidScore = 13;
        _discardSelectedIds.Clear();
        _friendSpec = new FriendSpec { Type = FriendType.None, CardId = "", Label = "미정" };
        _friendPlayerIdx = -1;
        _friendRevealed = false;
        _trickNumber = 1;
        _trickPlays.Clear();

        ClearTrickSlots();
        RefreshAllUi();
        _logLabel.Text = "카드가 배분되었습니다. 경매를 시작합니다!";
        _ = ProcessBiddingTurnAsync(_roundGeneration);
    }

    private async Task ProcessBiddingTurnAsync(int gen)
    {
        if (gen != _roundGeneration) return;
        RefreshAllUi();

        int activeCount = 0;
        int lastActive = -1;
        for (int i = 0; i < 5; i++)
        {
            if (!_passedPlayers[i])
            {
                activeCount++;
                lastActive = i;
            }
        }

        if (activeCount == 0)
        {
            _logLabel.Text = "모두 패스하여 새 판을 배분합니다.";
            await DelaySeconds(1.0);
            if (gen == _roundGeneration) StartNewRound();
            return;
        }

        if (activeCount == 1 && _highestBid >= 13)
        {
            _declarerIdx = lastActive;
            _trumpSuit = _highestBidSuit;
            _contractScore = _highestBid;
            await StartKittyPhaseAsync(gen);
            return;
        }

        while (_passedPlayers[_currentBidder])
            _currentBidder = (_currentBidder + 1) % 5;

        HighlightActiveSeat(_currentBidder);

        if (_currentBidder == 0)
        {
            _waitingForHuman = true;
            ShowHumanBiddingModal(gen);
        }
        else
        {
            _waitingForHuman = false;
            _centerModal.Visible = false;
            _trickInfoBanner.Text = $"{PlayerNames[_currentBidder]}님이 공약을 고민 중입니다...";
            await DelaySeconds(0.55);
            if (gen != _roundGeneration) return;

            var decision = MightyRules.AiDecideBid(_hands[_currentBidder], _highestBid);
            if (decision.ShouldBid)
            {
                _highestBid = decision.ContractScore;
                _highestBidSuit = decision.BidSuit;
                _declarerIdx = _currentBidder;
                _playerBubbleLabels[_currentBidder].Text = $"선언: {MightyRules.GetSuitSymbol(_highestBidSuit)} {_highestBid}점";
                _logLabel.Text = $"{PlayerNames[_currentBidder]}님이 [{MightyRules.GetSuitName(_highestBidSuit)} {_highestBid}점] 공약을 선언했습니다!";
                if (_highestBid >= 20)
                {
                    _trumpSuit = _highestBidSuit;
                    _contractScore = _highestBid;
                    await StartKittyPhaseAsync(gen);
                    return;
                }
            }
            else
            {
                _passedPlayers[_currentBidder] = true;
                _playerBubbleLabels[_currentBidder].Text = "패스 (Pass)";
                _logLabel.Text = $"{PlayerNames[_currentBidder]}님이 패스했습니다.";
            }

            _currentBidder = (_currentBidder + 1) % 5;
            await ProcessBiddingTurnAsync(gen);
        }
    }

    private void ShowHumanBiddingModal(int gen)
    {
        _centerModal.Visible = true;
        ClearModalChildren();

        int minBid = Math.Max(13, _highestBid + 1);
        if (_selectedBidScore < minBid)
            _selectedBidScore = minBid;

        var title = new Label
        {
            Text = "★ 경매 (공약 선언)",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        title.AddThemeFontSizeOverride("font_size", 20);
        title.AddThemeColorOverride("font_color", new Color(0.98f, 0.84f, 0.28f));
        _modalVbox.AddChild(title);

        var curLbl = new Label
        {
            Text = _highestBid >= 13
                ? $"현재 최고 공약: {PlayerNames[_declarerIdx]} ({MightyRules.GetSuitName(_highestBidSuit)} {_highestBid}점)"
                : "현재 선언된 공약 없음 (최소 13점부터 가능)",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _modalVbox.AddChild(curLbl);

        var suitHb = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        suitHb.AddThemeConstantOverride("separation", 8);
        _modalVbox.AddChild(suitHb);

        foreach (var s in new[] { Suit.Spade, Suit.Diamond, Suit.Heart, Suit.Club, Suit.None })
        {
            Suit capturedSuit = s;
            var b = new Button
            {
                Text = MightyRules.GetSuitName(capturedSuit),
                ToggleMode = true,
                ButtonPressed = _selectedBidSuit == capturedSuit
            };
            b.Pressed += () =>
            {
                _selectedBidSuit = capturedSuit;
                MightyRules.SortHand(_hands[0], _selectedBidSuit);
                RenderHumanHand();
                ShowHumanBiddingModal(gen);
            };
            suitHb.AddChild(b);
        }

        var scoreHb = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        scoreHb.AddThemeConstantOverride("separation", 12);
        _modalVbox.AddChild(scoreHb);

        var minusBtn = new Button
        {
            Text = "-1점",
            Disabled = _selectedBidScore <= minBid
        };
        minusBtn.Pressed += () =>
        {
            _selectedBidScore = Math.Max(minBid, _selectedBidScore - 1);
            ShowHumanBiddingModal(gen);
        };
        scoreHb.AddChild(minusBtn);

        var scoreVal = new Label { Text = $"목표 공약: {_selectedBidScore}점" };
        scoreVal.AddThemeFontSizeOverride("font_size", 18);
        scoreVal.AddThemeColorOverride("font_color", new Color(1.0f, 0.92f, 0.50f));
        scoreHb.AddChild(scoreVal);

        var plusBtn = new Button
        {
            Text = "+1점",
            Disabled = _selectedBidScore >= 20
        };
        plusBtn.Pressed += () =>
        {
            _selectedBidScore = Math.Min(20, _selectedBidScore + 1);
            ShowHumanBiddingModal(gen);
        };
        scoreHb.AddChild(plusBtn);

        var actHb = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        actHb.AddThemeConstantOverride("separation", 16);
        _modalVbox.AddChild(actHb);

        var bidBtn = new Button
        {
            Text = $"{MightyRules.GetSuitName(_selectedBidSuit)} {_selectedBidScore}점 공약 선언",
            Disabled = minBid > 20
        };
        bidBtn.Pressed += () =>
        {
            _centerModal.Visible = false;
            _highestBid = _selectedBidScore;
            _highestBidSuit = _selectedBidSuit;
            _declarerIdx = 0;
            _playerBubbleLabels[0].Text = $"선언: {MightyRules.GetSuitSymbol(_highestBidSuit)} {_highestBid}점";
            _logLabel.Text = $"내가 [{MightyRules.GetSuitName(_highestBidSuit)} {_highestBid}점] 공약을 선언했습니다!";
            _currentBidder = 1;
            _ = ProcessBiddingTurnAsync(gen);
        };
        actHb.AddChild(bidBtn);

        var passBtn = new Button { Text = "패스 (Pass)" };
        passBtn.Pressed += () =>
        {
            _centerModal.Visible = false;
            _passedPlayers[0] = true;
            _playerBubbleLabels[0].Text = "패스 (Pass)";
            _logLabel.Text = "내가 경매를 패스했습니다.";
            _currentBidder = 1;
            _ = ProcessBiddingTurnAsync(gen);
        };
        actHb.AddChild(passBtn);

        if (MightyRules.IsDealMissEligible(_hands[0], _selectedBidSuit))
        {
            var dmBtn = new Button { Text = "딜미스 선언 (재배분)" };
            dmBtn.Pressed += () =>
            {
                _centerModal.Visible = false;
                _logLabel.Text = "딜미스를 선언하여 패를 다시 나눕니다!";
                StartNewRound();
            };
            actHb.AddChild(dmBtn);
        }
    }

    // =========================================================================
    // 바닥패 교환 및 프렌드 지정 단계
    // =========================================================================
    private async Task StartKittyPhaseAsync(int gen)
    {
        if (gen != _roundGeneration) return;
        _phase = Phase.KittyExchange;

        for (int i = 0; i < 5; i++)
            _playerBubbleLabels[i].Text = "";
        _playerBubbleLabels[_declarerIdx].Text = $"주공 당선! ({MightyRules.GetSuitSymbol(_trumpSuit)} {_contractScore}점)";

        _hands[_declarerIdx].AddRange(_kitty);
        MightyRules.SortHand(_hands[_declarerIdx], _trumpSuit);
        RefreshAllUi();

        if (_declarerIdx == 0)
        {
            _waitingForHuman = true;
            _discardSelectedIds.Clear();
            _selectedFriendOption = 0;
            _handHintLabel.Text = "바닥패 3장이 추가되었습니다! 아래 내 손패(13장)에서 버릴 카드 3장을 클릭해 선택하세요.";
            RenderHumanHand();
            ShowHumanKittyModal(gen);
        }
        else
        {
            _waitingForHuman = false;
            _centerModal.Visible = false;
            _trickInfoBanner.Text = $"주공 {PlayerNames[_declarerIdx]}님이 바닥패를 교환하고 프렌드를 지정하고 있습니다...";
            await DelaySeconds(1.0);
            if (gen != _roundGeneration) return;

            var prep = MightyRules.AiPrepareDeclarer(_hands[_declarerIdx], _trumpSuit);
            _hands[_declarerIdx] = prep.RemainingHand;
            MightyRules.SortHand(_hands[_declarerIdx], _trumpSuit);
            foreach (var d in prep.Discards)
            {
                if (MightyRules.IsPointCard(d))
                    _capturedPoints[_declarerIdx].Add(d);
            }
            _friendSpec = prep.Friend;
            ResolveCardFriendOwner();
            _logLabel.Text = $"주공 {PlayerNames[_declarerIdx]}님이 [{_friendSpec.Label}]를 선언했습니다!";
            StartTrickPlayPhase(gen);
        }
    }

    private List<FriendSpec> BuildFriendOptions()
    {
        var mCard = MightyRules.GetMightyCardTemplate(_trumpSuit);
        var list = new List<FriendSpec>
        {
            new() { Type = FriendType.Card, CardId = mCard.Id, Label = $"마이티 ({MightyRules.GetCardShortName(mCard)}) 프렌드" },
            new() { Type = FriendType.Card, CardId = "joker", Label = "조커 (★) 프렌드" }
        };

        if (_trumpSuit != Suit.None)
        {
            var ta = new CardData { Id = $"{(int)_trumpSuit}_14", Suit = _trumpSuit, Rank = 14 };
            var tk = new CardData { Id = $"{(int)_trumpSuit}_13", Suit = _trumpSuit, Rank = 13 };
            list.Add(new FriendSpec { Type = FriendType.Card, CardId = ta.Id, Label = $"기루다 A ({MightyRules.GetCardShortName(ta)}) 프렌드" });
            list.Add(new FriendSpec { Type = FriendType.Card, CardId = tk.Id, Label = $"기루다 K ({MightyRules.GetCardShortName(tk)}) 프렌드" });
        }

        list.Add(new FriendSpec { Type = FriendType.FirstTrick, CardId = "", Label = "초구 프렌드 (1라운드 승자)" });
        list.Add(new FriendSpec { Type = FriendType.None, CardId = "", Label = "노프렌드 (혼자서 승리 도전)" });
        return list;
    }

    private void ShowHumanKittyModal(int gen)
    {
        _centerModal.Visible = true;
        ClearModalChildren();

        var title = new Label
        {
            Text = "★ 주공 당선! 바닥패 3장 버리기 & 프렌드 지정",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        title.AddThemeFontSizeOverride("font_size", 19);
        title.AddThemeColorOverride("font_color", new Color(0.98f, 0.84f, 0.28f));
        _modalVbox.AddChild(title);

        string kittyNames = string.Join(", ", _kitty.Select(MightyRules.GetCardShortName));
        var kittyLbl = new Label
        {
            Text = $"들어온 바닥패: {kittyNames}  |  선택된 버릴 카드: {_discardSelectedIds.Count} / 3장",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        kittyLbl.AddThemeColorOverride("font_color", new Color(0.82f, 0.96f, 0.88f));
        _modalVbox.AddChild(kittyLbl);

        var friendOptions = BuildFriendOptions();
        _selectedFriendOption = Math.Clamp(_selectedFriendOption, 0, friendOptions.Count - 1);

        var fLbl = new Label
        {
            Text = "함께할 프렌드(여당) 지정:",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _modalVbox.AddChild(fLbl);

        var fGrid = new GridContainer { Columns = 2 };
        fGrid.AddThemeConstantOverride("h_separation", 8);
        fGrid.AddThemeConstantOverride("v_separation", 6);
        _modalVbox.AddChild(fGrid);

        for (int idx = 0; idx < friendOptions.Count; idx++)
        {
            int capturedIdx = idx;
            var opt = friendOptions[capturedIdx];
            var fb = new Button
            {
                Text = opt.Label,
                SizeFlagsHorizontal = SizeFlags.ExpandFill,
                ToggleMode = true,
                ButtonPressed = _selectedFriendOption == capturedIdx
            };
            fb.Pressed += () =>
            {
                _selectedFriendOption = capturedIdx;
                ShowHumanKittyModal(gen);
            };
            fGrid.AddChild(fb);
        }

        var confirmBtn = new Button
        {
            Text = $"바닥패 3장 버리기 및 프렌드 선언 완료 ({_discardSelectedIds.Count}/3)",
            Disabled = _discardSelectedIds.Count != 3
        };
        confirmBtn.Pressed += () =>
        {
            var newHand = new List<CardData>();
            foreach (var c in _hands[0])
            {
                if (_discardSelectedIds.Contains(c.Id))
                {
                    if (MightyRules.IsPointCard(c))
                        _capturedPoints[0].Add(c);
                }
                else
                {
                    newHand.Add(c);
                }
            }
            _hands[0] = newHand;
            MightyRules.SortHand(_hands[0], _trumpSuit);
            _friendSpec = friendOptions[_selectedFriendOption];
            ResolveCardFriendOwner();
            _centerModal.Visible = false;
            _logLabel.Text = $"내가 [{_friendSpec.Label}]를 선언하고 본 게임을 시작합니다!";
            StartTrickPlayPhase(gen);
        };
        _modalVbox.AddChild(confirmBtn);
    }

    private void ResolveCardFriendOwner()
    {
        _friendPlayerIdx = -1;
        _friendRevealed = false;
        if (_friendSpec.Type == FriendType.None)
        {
            _friendRevealed = true;
            return;
        }

        if (_friendSpec.Type == FriendType.Card)
        {
            for (int p = 0; p < 5; p++)
            {
                if (_hands[p].Any(c => c.Id == _friendSpec.CardId))
                {
                    if (p != _declarerIdx)
                        _friendPlayerIdx = p;
                    break;
                }
            }
        }
    }

    // =========================================================================
    // 트릭(1~10라운드) 진행 단계
    // =========================================================================
    private void StartTrickPlayPhase(int gen)
    {
        _phase = Phase.Playing;
        _trickNumber = 1;
        _trickLeader = _declarerIdx;
        _turnPlayer = _declarerIdx;
        for (int i = 0; i < 5; i++)
            MightyRules.SortHand(_hands[i], _trumpSuit);
        StartSingleTrick(gen);
    }

    private void StartSingleTrick(int gen)
    {
        _trickPlays.Clear();
        _leadInfo = new LeadInfo();
        _turnPlayer = _trickLeader;
        ClearTrickSlots();
        RefreshAllUi();
        _ = ProcessTrickTurnAsync(gen);
    }

    private async Task ProcessTrickTurnAsync(int gen)
    {
        if (gen != _roundGeneration) return;
        RefreshAllUi();
        HighlightActiveSeat(_turnPlayer);

        if (_trickPlays.Count == 5)
        {
            await FinishTrickAsync(gen);
            return;
        }

        if (_turnPlayer == 0)
        {
            _waitingForHuman = true;
            _centerModal.Visible = false;
            _handHintLabel.Text = "내 차례입니다! 낼 수 있는 밝은 카드를 클릭하세요.";
            RenderHumanHand();
        }
        else
        {
            _waitingForHuman = false;
            _centerModal.Visible = false;
            _handHintLabel.Text = $"{PlayerNames[_turnPlayer]}님이 카드를 내는 중입니다...";
            RenderHumanHand();
            await DelaySeconds(0.55);
            if (gen != _roundGeneration) return;

            var legalIds = MightyRules.GetLegalCardIds(_hands[_turnPlayer], _trickPlays, _leadInfo, _trumpSuit, _trickNumber);
            var aiChoice = MightyRules.AiChooseCard(
                _hands[_turnPlayer],
                legalIds,
                _trickPlays,
                _leadInfo,
                _trumpSuit,
                _trickNumber,
                _turnPlayer,
                _declarerIdx,
                _friendRevealed ? _friendPlayerIdx : -1,
                _turnPlayer == _friendPlayerIdx);

            ExecuteCardPlay(gen, _turnPlayer, aiChoice.Card, aiChoice.DeclareJokerCall, aiChoice.JokerRequestedSuit);
        }
    }

    private void OnHumanCardClicked(CardData card)
    {
        if (!_waitingForHuman) return;

        if (_phase == Phase.KittyExchange)
        {
            if (_discardSelectedIds.Contains(card.Id))
                _discardSelectedIds.Remove(card.Id);
            else if (_discardSelectedIds.Count < 3)
                _discardSelectedIds.Add(card.Id);

            RenderHumanHand();
            ShowHumanKittyModal(_roundGeneration);
            return;
        }

        if (_phase == Phase.Playing && _turnPlayer == 0)
        {
            if (_trickPlays.Count == 0)
            {
                if (MightyRules.IsJoker(card) && _trickNumber > 1 && _trickNumber < 10)
                {
                    ShowJokerSuitModal(_roundGeneration, card);
                    return;
                }
                if (MightyRules.IsJokerCall(card, _trumpSuit) && _trickNumber > 1)
                {
                    ShowJokerCallModal(_roundGeneration, card);
                    return;
                }
            }
            ExecuteCardPlay(_roundGeneration, 0, card, false, card.Suit);
        }
    }

    private void ShowJokerSuitModal(int gen, CardData jokerCard)
    {
        _centerModal.Visible = true;
        ClearModalChildren();

        var t = new Label
        {
            Text = "★ 조커 선공: 요청할 문양을 선택하세요",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        t.AddThemeFontSizeOverride("font_size", 18);
        _modalVbox.AddChild(t);

        var hb = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        hb.AddThemeConstantOverride("separation", 10);
        _modalVbox.AddChild(hb);

        foreach (var s in new[] { Suit.Spade, Suit.Diamond, Suit.Heart, Suit.Club })
        {
            Suit reqSuit = s;
            var b = new Button { Text = MightyRules.GetSuitName(reqSuit) };
            b.Pressed += () =>
            {
                _centerModal.Visible = false;
                ExecuteCardPlay(gen, 0, jokerCard, false, reqSuit);
            };
            hb.AddChild(b);
        }
    }

    private void ShowJokerCallModal(int gen, CardData jcCard)
    {
        _centerModal.Visible = true;
        ClearModalChildren();

        var t = new Label
        {
            Text = $"📢 조커 콜({MightyRules.GetCardShortName(jcCard)}) 카드를 내시겠습니까?",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        t.AddThemeFontSizeOverride("font_size", 18);
        _modalVbox.AddChild(t);

        var hb = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.Center };
        hb.AddThemeConstantOverride("separation", 12);
        _modalVbox.AddChild(hb);

        var callBtn = new Button { Text = "조커 콜 선언하고 내기!" };
        callBtn.Pressed += () =>
        {
            _centerModal.Visible = false;
            ExecuteCardPlay(gen, 0, jcCard, true, jcCard.Suit);
        };
        hb.AddChild(callBtn);

        var normalBtn = new Button { Text = "조커 콜 없이 일반 카드로 내기" };
        normalBtn.Pressed += () =>
        {
            _centerModal.Visible = false;
            ExecuteCardPlay(gen, 0, jcCard, false, jcCard.Suit);
        };
        hb.AddChild(normalBtn);
    }

    private void ExecuteCardPlay(int gen, int playerIdx, CardData card, bool declareJokerCall, Suit jokerReqSuit)
    {
        if (gen != _roundGeneration) return;
        _waitingForHuman = false;

        _hands[playerIdx].RemoveAll(c => c.Id == card.Id);

        if (_trickPlays.Count == 0)
        {
            if (MightyRules.IsJoker(card))
            {
                _leadInfo.LeadSuit = (_trickNumber > 1 && _trickNumber < 10) ? jokerReqSuit : Suit.None;
                _leadInfo.JokerCallActive = false;
                _leadInfo.Note = $"조커 선공 (요청 문양: {MightyRules.GetSuitName(_leadInfo.LeadSuit)})";
            }
            else if (declareJokerCall && MightyRules.IsJokerCall(card, _trumpSuit))
            {
                _leadInfo.LeadSuit = card.Suit;
                _leadInfo.JokerCallActive = true;
                _leadInfo.Note = $"📢 조커 콜 발동! ({MightyRules.GetCardShortName(card)})";
            }
            else
            {
                _leadInfo.LeadSuit = card.Suit;
                _leadInfo.JokerCallActive = false;
                _leadInfo.Note = $"선문양: {MightyRules.GetSuitName(card.Suit)}";
            }
        }

        _trickPlays.Add(new TrickPlay
        {
            PlayerIndex = playerIdx,
            Card = card
        });

        if (_friendSpec.Type == FriendType.Card && card.Id == _friendSpec.CardId)
        {
            if (playerIdx != _declarerIdx)
            {
                _friendPlayerIdx = playerIdx;
                _friendRevealed = true;
                _logLabel.Text = $"♦ {PlayerNames[playerIdx]}님이 프렌드 카드({MightyRules.GetCardShortName(card)})를 내어 여당(프렌드)임이 밝혀졌습니다!";
            }
        }

        RenderTrickSlot(_trickPlays.Count - 1, playerIdx, card);
        _turnPlayer = (_turnPlayer + 1) % 5;
        _ = ProcessTrickTurnAsync(gen);
    }

    private async Task FinishTrickAsync(int gen)
    {
        if (gen != _roundGeneration) return;

        var winPlay = MightyRules.DetermineTrickWinner(_trickPlays, _leadInfo, _trumpSuit, _trickNumber);
        int winnerIdx = winPlay.PlayerIndex;
        var winCard = winPlay.Card;

        if (_trickNumber == 1 && _friendSpec.Type == FriendType.FirstTrick)
        {
            if (winnerIdx != _declarerIdx)
                _friendPlayerIdx = winnerIdx;
            _friendRevealed = true;
            _logLabel.Text = $"♦ 초구 승리자 {PlayerNames[winnerIdx]}님이 프렌드(여당)가 되었습니다!";
        }

        int ptsWon = 0;
        foreach (var p in _trickPlays)
        {
            if (MightyRules.IsPointCard(p.Card))
            {
                _capturedPoints[winnerIdx].Add(p.Card);
                ptsWon++;
            }
        }

        _trickInfoBanner.Text = $"{_trickNumber}라운드 승자: {PlayerNames[winnerIdx]} ({MightyRules.GetCardShortName(winCard)}) — 점수 +{ptsWon}점 획득!";
        RefreshAllUi();

        await DelaySeconds(1.35);
        if (gen != _roundGeneration) return;

        if (_trickNumber >= 10)
        {
            FinishRound();
        }
        else
        {
            _trickNumber++;
            _trickLeader = winnerIdx;
            StartSingleTrick(gen);
        }
    }

    // =========================================================================
    // 라운드 종료 및 정산
    // =========================================================================
    private void FinishRound()
    {
        _phase = Phase.RoundOver;
        _friendRevealed = true;

        int rulingPts = MightyRules.CountPointCards(_capturedPoints[_declarerIdx]);
        if (_friendPlayerIdx != -1 && _friendPlayerIdx != _declarerIdx)
            rulingPts += MightyRules.CountPointCards(_capturedPoints[_friendPlayerIdx]);
        int defPts = 20 - rulingPts;

        bool rulingWon = rulingPts >= _contractScore;
        int deltaBase;
        if (rulingWon)
        {
            deltaBase = (rulingPts - _contractScore + 1) + (_contractScore - 13);
            if (rulingPts == 20) deltaBase *= 2;
        }
        else
        {
            deltaBase = _contractScore - rulingPts;
            if (defPts >= 11) deltaBase *= 2;
        }

        if (_trumpSuit == Suit.None)
            deltaBase *= 2;

        var scoreChanges = new int[5];
        for (int i = 0; i < 5; i++)
        {
            bool isDeclarer = i == _declarerIdx;
            bool isFriend = i == _friendPlayerIdx && _friendPlayerIdx != _declarerIdx;
            if (rulingWon)
            {
                if (isDeclarer) scoreChanges[i] = deltaBase * (_friendPlayerIdx == -1 ? 4 : 2);
                else if (isFriend) scoreChanges[i] = deltaBase;
                else scoreChanges[i] = -deltaBase;
            }
            else
            {
                if (isDeclarer) scoreChanges[i] = -deltaBase * (_friendPlayerIdx == -1 ? 4 : 2);
                else if (isFriend) scoreChanges[i] = -deltaBase;
                else scoreChanges[i] = deltaBase;
            }
            _totalScores[i] += scoreChanges[i];
        }

        RefreshAllUi();
        ShowRoundResultModal(rulingWon, rulingPts, defPts, scoreChanges);
    }

    private void ShowRoundResultModal(bool rulingWon, int rulingPts, int defPts, int[] scoreChanges)
    {
        _centerModal.Visible = true;
        ClearModalChildren();

        var title = new Label
        {
            Text = rulingWon ? "🎉 여당(주공+프렌드) 공약 달성 승리!" : "🛡️ 야당(수비팀) 공약 저지 승리!",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        title.AddThemeFontSizeOverride("font_size", 21);
        title.AddThemeColorOverride("font_color", rulingWon ? new Color(0.98f, 0.84f, 0.28f) : new Color(0.55f, 0.90f, 1.0f));
        _modalVbox.AddChild(title);

        string fName = _friendPlayerIdx != -1 ? PlayerNames[_friendPlayerIdx] : "없음(노프렌드)";
        var summary = new Label
        {
            Text = $"주공: {PlayerNames[_declarerIdx]} | 프렌드: {fName} ({_friendSpec.Label})\n" +
                   $"공약: {MightyRules.GetSuitName(_trumpSuit)} {_contractScore}점  →  여당 획득: {rulingPts}점 / 야당 획득: {defPts}점",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        _modalVbox.AddChild(summary);

        for (int i = 0; i < 5; i++)
        {
            string roleTag = "야당";
            if (i == _declarerIdx) roleTag = "주공★";
            else if (i == _friendPlayerIdx) roleTag = "프렌드♦";
            string diffStr = scoreChanges[i] >= 0 ? $"+{scoreChanges[i]}" : scoreChanges[i].ToString();

            var row = new Label
            {
                Text = $"{PlayerNames[i]} [{roleTag}] : 이번 판 {diffStr}점  (누적 {_totalScores[i]}점)",
                HorizontalAlignment = HorizontalAlignment.Center
            };
            _modalVbox.AddChild(row);
        }

        var nextBtn = new Button { Text = "다음 판 시작하기" };
        nextBtn.Pressed += () =>
        {
            _centerModal.Visible = false;
            StartNewRound();
        };
        _modalVbox.AddChild(nextBtn);
    }

    // =========================================================================
    // 화면 갱신 헬퍼
    // =========================================================================
    private void ClearModalChildren()
    {
        foreach (Node child in _modalVbox.GetChildren())
            child.QueueFree();
    }

    private void ClearTrickSlots()
    {
        foreach (var slot in _trickSlots)
        {
            foreach (Node c in slot.GetChildren())
                c.QueueFree();
        }
    }

    private void RenderTrickSlot(int slotIdx, int playerIdx, CardData card)
    {
        if (slotIdx < 0 || slotIdx >= _trickSlots.Count) return;
        var slot = _trickSlots[slotIdx];
        foreach (Node c in slot.GetChildren())
            c.QueueFree();

        var who = new Label
        {
            Text = $"{slotIdx + 1}. {PlayerNames[playerIdx]}",
            HorizontalAlignment = HorizontalAlignment.Center
        };
        who.AddThemeFontSizeOverride("font_size", 13);
        slot.AddChild(who);

        var cv = new CardView();
        slot.AddChild(cv);
        cv.Setup(card, _trumpSuit, true);
        cv.SetLegal(false);
    }

    private void HighlightActiveSeat(int activeIdx)
    {
        for (int i = 0; i < 5; i++)
        {
            var borderCol = i == activeIdx ? new Color(0.96f, 0.80f, 0.22f) : new Color(0.28f, 0.52f, 0.38f);
            int bw = i == activeIdx ? 3 : 2;
            _playerSeatPanels[i].AddThemeStyleboxOverride(
                "panel",
                MakePanelStyle(new Color(0.07f, 0.16f, 0.12f, 0.92f), borderCol, 10, bw));
        }
    }

    private void RefreshAllUi()
    {
        switch (_phase)
        {
            case Phase.Bidding:
                _topStatusLabel.Text = "[경매 단계]";
                break;
            case Phase.KittyExchange:
                _topStatusLabel.Text = "[바닥패 교환 & 프렌드 선언]";
                break;
            case Phase.Playing:
                _topStatusLabel.Text = $"[{_trickNumber} / 10 라운드]";
                string note = _leadInfo.Note;
                _trickInfoBanner.Text = $"{_trickNumber}라운드 진행 중 {(string.IsNullOrEmpty(note) ? "" : "— " + note)}";
                break;
            case Phase.RoundOver:
                _topStatusLabel.Text = "[라운드 종료]";
                break;
        }

        if (_declarerIdx == -1)
        {
            _contractInfoLabel.Text = "공약: 경매 중 | 주공: 미정 | 프렌드: 미정";
        }
        else
        {
            string fStatus = _friendSpec.Label;
            if (_friendRevealed && _friendPlayerIdx != -1)
                fStatus += $" ({PlayerNames[_friendPlayerIdx]})";
            else if (_phase == Phase.Playing && _friendSpec.Type != FriendType.None)
                fStatus += " (정체 숨김)";

            _contractInfoLabel.Text = $"공약: {MightyRules.GetSuitName(_trumpSuit)} {_contractScore}점 | 주공: {PlayerNames[_declarerIdx]} | 프렌드: {fStatus}";
        }

        int knownRuling = 0;
        int knownDef = 0;
        for (int i = 0; i < 5; i++)
        {
            int pts = MightyRules.CountPointCards(_capturedPoints[i]);
            if (i == _declarerIdx || (_friendRevealed && i == _friendPlayerIdx))
                knownRuling += pts;
            else
                knownDef += pts;
        }
        _teamScoreLabel.Text = $"여당(공개): {knownRuling} / {_contractScore}점 | 기타 획득: {knownDef}점";

        for (int i = 0; i < 5; i++)
        {
            string roleTxt = "경매 중";
            if (_declarerIdx != -1)
            {
                if (i == _declarerIdx) roleTxt = "★ 주공";
                else if (_friendRevealed && i == _friendPlayerIdx) roleTxt = "♦ 프렌드";
                else if (_friendRevealed) roleTxt = "🛡️ 야당";
                else roleTxt = "❓ 미상";
            }
            _playerRoleLabels[i].Text = roleTxt;
            _playerCardCountLabels[i].Text = $"남은 패: {_hands[i].Count}장 | 누적: {_totalScores[i]}점";

            var capNames = _capturedPoints[i].Select(MightyRules.GetCardShortName).ToList();
            _playerCapturedLabels[i].Text = $"획득({capNames.Count}점): {(capNames.Count > 0 ? string.Join(" ", capNames) : "없음")}";
        }

        RenderHumanHand();
    }

    private void RenderHumanHand()
    {
        foreach (Node c in _handContainer.GetChildren())
            c.QueueFree();

        HashSet<string> legalIds = new();
        if (_phase == Phase.Playing && _turnPlayer == 0 && _waitingForHuman)
            legalIds = MightyRules.GetLegalCardIds(_hands[0], _trickPlays, _leadInfo, _trumpSuit, _trickNumber);
        else if (_phase == Phase.KittyExchange && _declarerIdx == 0)
            legalIds = _hands[0].Select(c => c.Id).ToHashSet();

        Suit displayTrump = _declarerIdx != -1 ? _trumpSuit : _selectedBidSuit;
        foreach (var card in _hands[0])
        {
            var cv = new CardView();
            _handContainer.AddChild(cv);
            cv.Setup(card, displayTrump, false);

            if (_phase == Phase.KittyExchange && _declarerIdx == 0)
            {
                cv.SetLegal(true);
                cv.SetDiscardSelected(_discardSelectedIds.Contains(card.Id));
            }
            else if (_phase == Phase.Playing && _turnPlayer == 0 && _waitingForHuman)
            {
                cv.SetLegal(legalIds.Contains(card.Id));
            }
            else
            {
                cv.SetLegal(false);
            }

            cv.CardClicked += OnHumanCardClicked;
        }
    }
}
