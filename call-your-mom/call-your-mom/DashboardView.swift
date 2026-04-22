//
//  DashboardView.swift
//  call-your-mom
//
//  Created by Ben Cerbin on 4/21/26.
//

import SwiftUI
internal import Combine

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var activePage: HomePage = .home
    @State private var pageHistory: [HomePage] = []
    @State private var quickActionsExpanded = false
    @State private var health = HealthPersistence.defaultHealth
    @State private var callsLogged = HealthPersistence.defaultCallsLogged
    @State private var logName: String = ""
    @State private var logMinutes: String = ""
    @State private var healthPulse = false
    @State private var lastHealthUpdatedAt = Date()
    @State private var wasBelowLowHealthThreshold = false
    @State private var callLogs: [CallLogEntry] = [
        CallLogEntry(name: "Mom", minutes: 18, loggedAt: Date()),
        CallLogEntry(name: "Dad", minutes: 9, loggedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    ]
    @State private var selectedSprite: SpriteProfile = .skyBuddy
    @State private var selectedClothing: ClothingOption = .none
    @State private var selectedDanceSpeed: DanceSpeed = .normal
    @State private var streakTier: Int = 1
    @State private var selectedTheme: AppTheme = .meadow
    @State private var streakDays: Int = 0
    @State private var notifications: [InboxItem] = [
        InboxItem(title: "Daily reminder ready", subtitle: "Send a quick check-in before 8 PM.", kind: .reminder),
        InboxItem(title: "3-day streak active", subtitle: "One more call tomorrow keeps it going.", kind: .streak),
        InboxItem(title: "Mom replied", subtitle: "Call me when you get a minute.", kind: .message)
    ]
    private let decayTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let metrics = LayoutMetrics(container: geometry.size, safeArea: geometry.safeAreaInsets)

            ZStack {
                AppSceneBackground(theme: selectedTheme)

                VStack(spacing: metrics.sectionSpacing) {
                    HomeTopBar(
                        metrics: metrics,
                        isBackVisible: activePage != .home,
                        isQuickActionsExpanded: quickActionsExpanded,
                        onTitleTap: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                quickActionsExpanded.toggle()
                            }
                        },
                        onBack: goBack,
                        onInbox: { navigate(to: .inbox) }
                    )
                    .padding(.top, metrics.topPadding)
                    .padding(.horizontal, metrics.horizontalPadding)

                    Group {
                        if activePage == .home {
                            homeView(metrics: metrics)
                        } else {
                            detailPage(metrics: metrics, page: activePage)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ActionDock(
                    activePage: $activePage,
                    metrics: metrics,
                    onLogTap: { activePage = .log },
                    onSelectPage: navigate
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, metrics.dockOuterBottomPadding)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                healthPulse = true
            }
            LocalNotificationManager.shared.requestAuthorization()
            restorePersistedHealth()
            refreshStreakDays()
        }
        .onReceive(decayTimer) { _ in
            guard scenePhase == .active else { return }
            applyElapsedDecay(now: Date())
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                restorePersistedHealth()
            } else if newValue == .background || newValue == .inactive {
                persistHealthState()
                syncLowHealthNotification()
            }
        }
        .onChange(of: health) { _, _ in
            persistHealthState()
            syncLowHealthNotification()
        }
    }

    @ViewBuilder
    private func homeView(metrics: LayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: metrics.sectionSpacing) {
                if quickActionsExpanded {
                    QuickActionsFlyout()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                FloatingHealthBar(health: health, isAnimating: healthPulse)

                IntegratedTamagotchiStage(
                    health: health,
                    sprite: selectedSprite,
                    clothing: selectedClothing,
                    danceSpeed: selectedDanceSpeed
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.contentBottomPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minContentHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func logCall(name: String, minutes: Int) {
        applyElapsedDecay(now: Date())
        callsLogged += 1
        callLogs.insert(CallLogEntry(name: name, minutes: minutes, loggedAt: Date()), at: 0)
        refreshStreakDays()

        let streakBonus = Double(streakTier * 2)
        let healingAmount = max(12, min(Double(minutes), 25)) + streakBonus
        health = min(health + healingAmount, 100)
        notifications.insert(
            InboxItem(
                title: "Logged call with \(name)",
                subtitle: "\(minutes) minute\(minutes == 1 ? "" : "s") logged. Current streak: \(streakDays) day\(streakDays == 1 ? "" : "s").",
                kind: .streak
            ),
            at: 0
        )
        logName = ""
        logMinutes = ""
        lastHealthUpdatedAt = Date()
    }

    private func applyElapsedDecay(now: Date) {
        let updatedHealth = HealthPersistence.decayedHealth(from: health, since: lastHealthUpdatedAt, now: now)
        guard updatedHealth != health || lastHealthUpdatedAt != now else { return }
        health = updatedHealth
        lastHealthUpdatedAt = now
    }

    private func restorePersistedHealth() {
        let persisted = HealthPersistence.load()
        callsLogged = persisted.callsLogged
        health = HealthPersistence.decayedHealth(from: persisted.health, since: persisted.updatedAt, now: Date())
        lastHealthUpdatedAt = Date()
        wasBelowLowHealthThreshold = health <= LocalNotificationManager.lowHealthThreshold
        refreshStreakDays()
    }

    private func persistHealthState() {
        HealthPersistence.save(
            health: health,
            updatedAt: lastHealthUpdatedAt,
            callsLogged: callsLogged
        )
    }

    private func syncLowHealthNotification() {
        if health <= LocalNotificationManager.lowHealthThreshold {
            if !wasBelowLowHealthThreshold {
                LocalNotificationManager.shared.scheduleLowHealthNotification(after: 1)
                wasBelowLowHealthThreshold = true
            }
        } else {
            wasBelowLowHealthThreshold = false
            let timeUntilThreshold = (health - LocalNotificationManager.lowHealthThreshold) / HealthPersistence.decayPerSecond
            LocalNotificationManager.shared.scheduleLowHealthNotification(after: timeUntilThreshold)
        }
    }

    @ViewBuilder
    private func detailPage(metrics: LayoutMetrics, page: HomePage) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: metrics.sectionSpacing) {
                if page == .log {
                    LogPageCard(
                        name: $logName,
                        minutes: $logMinutes,
                        entries: callLogs,
                        onSubmit: submitLogEntry
                    )
                } else {
                    DetailPageCard(
                        page: page,
                        items: notifications,
                        selectedSprite: $selectedSprite,
                        selectedClothing: $selectedClothing,
                        selectedDanceSpeed: $selectedDanceSpeed,
                        streakTier: $streakTier,
                        selectedTheme: $selectedTheme,
                        streakDays: $streakDays,
                        onRotateSprite: rotateSprite
                    )
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.contentBottomPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minContentHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func submitLogEntry() {
        let trimmedName = logName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let minutes = Int(logMinutes), minutes > 0 else {
            return
        }

        logCall(name: trimmedName, minutes: minutes)
    }

    private func rotateSprite() {
        let allSprites = SpriteProfile.allCases
        guard let currentIndex = allSprites.firstIndex(of: selectedSprite) else {
            selectedSprite = allSprites.first ?? .skyBuddy
            return
        }

        let nextIndex = (currentIndex + 1) % allSprites.count
        selectedSprite = allSprites[nextIndex]
    }

    private func refreshStreakDays() {
        streakDays = StreakCalculator.currentStreak(from: callLogs)
    }

    private func navigate(to page: HomePage) {
        guard page != activePage else { return }
        pageHistory.append(activePage)
        activePage = page
    }

    private func goBack() {
        guard activePage != .home else { return }

        if let previousPage = pageHistory.popLast() {
            activePage = previousPage
        } else {
            activePage = .home
        }
    }
}

private struct LayoutMetrics {
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let sectionSpacing: CGFloat
    let titleSize: CGFloat
    let eyebrowSize: CGFloat
    let topButtonSize: CGFloat
    let topIconSize: CGFloat
    let dockButtonSize: CGFloat
    let dockSelectedSize: CGFloat
    let dockLabelSize: CGFloat
    let dockInnerTopPadding: CGFloat
    let dockInnerBottomPadding: CGFloat
    let dockOuterBottomPadding: CGFloat
    let contentBottomPadding: CGFloat
    let cardCornerRadius: CGFloat
    let minContentHeight: CGFloat

    init(container: CGSize, safeArea: EdgeInsets) {
        let compactHeight = container.height < 760
        let tinyHeight = container.height < 690
        let narrowWidth = container.width < 390

        horizontalPadding = narrowWidth ? 16 : 22
        topPadding = safeArea.top + (compactHeight ? 8 : 14)
        sectionSpacing = tinyHeight ? 14 : (compactHeight ? 16 : 22)
        titleSize = tinyHeight ? 30 : (compactHeight ? 34 : 40)
        eyebrowSize = tinyHeight ? 11 : 12
        topButtonSize = compactHeight ? 46 : 54
        topIconSize = compactHeight ? 18 : 21
        dockButtonSize = tinyHeight ? 52 : (compactHeight ? 56 : 64)
        dockSelectedSize = tinyHeight ? 60 : (compactHeight ? 64 : 72)
        dockLabelSize = tinyHeight ? 12 : 14
        dockInnerTopPadding = tinyHeight ? 12 : 16
        dockInnerBottomPadding = tinyHeight ? 10 : 14
        dockOuterBottomPadding = max(safeArea.bottom, tinyHeight ? 8 : 12)
        contentBottomPadding = (tinyHeight ? 136 : 150) + dockOuterBottomPadding
        cardCornerRadius = tinyHeight ? 24 : 30
        minContentHeight = container.height - safeArea.top
    }
}

private struct AppSceneBackground: View {
    let theme: AppTheme

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [theme.primary, theme.secondary, theme.tertiary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SoftClouds()

            HStack {
                FirTree(height: 170)
                Spacer()
                FirTree(height: 132)
            }
            .padding(.horizontal, 4)
            .offset(y: 70)

            HStack {
                FirTree(height: 112)
                    .offset(x: 36, y: 4)
                Spacer()
                FirTree(height: 146)
                    .offset(x: -18, y: -4)
            }
            .padding(.horizontal, 20)
            .offset(y: 92)

            ZStack(alignment: .bottom) {
                SmoothHill(heightFactor: 0.26, peak: 0.18, valley: 0.44)
                    .fill(theme.hillOne)
                    .frame(height: 250)
                    .offset(x: -120, y: 30)

                SmoothHill(heightFactor: 0.24, peak: 0.78, valley: 0.48)
                    .fill(theme.hillTwo)
                    .frame(height: 230)
                    .offset(x: 130, y: 36)

                SmoothHill(heightFactor: 0.36, peak: 0.50, valley: 0.72)
                    .fill(theme.hillThree)
                    .frame(height: 320)
                    .offset(y: 108)
            }
        }
    }
}

private struct HomeTopBar: View {
    let metrics: LayoutMetrics
    let isBackVisible: Bool
    let isQuickActionsExpanded: Bool
    let onTitleTap: () -> Void
    let onBack: () -> Void
    let onInbox: () -> Void

    var body: some View {
        HStack {
            if isBackVisible {
                CircularIconButton(systemName: "arrow.left", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: false, action: onBack)
            } else {
                Color.clear
                    .frame(width: metrics.topButtonSize, height: metrics.topButtonSize)
            }

            Spacer()

            Button(action: onTitleTap) {
                HStack(spacing: 6) {
                    Text("Call Your Mom")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                        .rotationEffect(.degrees(isQuickActionsExpanded ? 180 : 0))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
            }
            .buttonStyle(.plain)

            Spacer()

            CircularIconButton(systemName: "bell.badge.fill", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: true, action: onInbox)
        }
    }
}

private struct FloatingHealthBar: View {
    let health: Double
    let isAnimating: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.40))
                    .frame(height: 14)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.28, blue: 0.34),
                                Color(red: 0.86, green: 0.10, blue: 0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(28, geometry.size.width * (health / 100)), height: 14)
                    .scaleEffect(x: 1, y: isAnimating ? 1.03 : 0.97, anchor: .center)
                    .shadow(color: Color.red.opacity(0.20), radius: isAnimating ? 8 : 4)
                    .animation(.easeInOut(duration: 0.8), value: isAnimating)
                    .animation(.easeInOut(duration: 0.45), value: health)
            }
        }
        .frame(height: 14)
        .padding(.horizontal, 8)
    }
}

private struct QuickActionsFlyout: View {
    var body: some View {
        VStack(spacing: 10) {
            ExpandableActionRow(icon: "phone.fill", title: "Call now", subtitle: "Jump straight into a check-in.")
            ExpandableActionRow(icon: "bell.fill", title: "Set reminder", subtitle: "Pick a time for your next call.")
            ExpandableActionRow(icon: "person.crop.circle.badge.plus", title: "Choose contact", subtitle: "Change who today’s reminder is for.")
        }
    }
}

private struct ExpandableActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.86, green: 0.96, blue: 0.94))
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.62, blue: 0.54))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.09, green: 0.16, blue: 0.26))

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.52))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.44, green: 0.57, blue: 0.62))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.76))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct IntegratedTamagotchiStage: View {
    let health: Double
    let sprite: SpriteProfile
    let clothing: ClothingOption
    let danceSpeed: DanceSpeed
    @State private var dancePhase = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PixelTamagotchi(health: health, sprite: sprite, clothing: clothing)
                .offset(y: dancePhase ? -18 : -6)
                .animation(
                    .easeInOut(duration: danceSpeed.duration).repeatForever(autoreverses: true),
                    value: dancePhase
                )

            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 120, height: 20)
                .blur(radius: 4)
                .offset(y: 28)
        }
        .frame(height: 300)
        .onAppear {
            dancePhase = true
        }
        .onChange(of: danceSpeed) {
            dancePhase = false
            withAnimation(.easeInOut(duration: danceSpeed.duration).repeatForever(autoreverses: true)) {
                dancePhase = true
            }
        }
    }
}

private struct PixelTamagotchi: View {
    let health: Double
    let sprite: SpriteProfile
    let clothing: ClothingOption

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                PixelCharacterGrid(
                    pixels: pixelRows,
                    palette: pixelPalette
                )
                .frame(width: 150, height: 150)
                .drawingGroup()

                Image(systemName: sprite.badgeSymbol)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(sprite.badgeColor)
                    .offset(x: -8, y: 6)
            }

            Text(healthLabel)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))

            Text(sprite.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
        }
    }

    private var shellColor: Color {
        if health > 70 {
            return sprite.highHealthShellColor
        } else if health > 35 {
            return sprite.midHealthShellColor
        } else {
            return sprite.lowHealthShellColor
        }
    }

    private var healthLabel: String {
        if health > 70 {
            return "Feeling loved"
        } else if health > 35 {
            return "Needs a call soon"
        } else {
            return "Running low"
        }
    }

    private var mouthCharacter: Character {
        health > 35 ? "M" : "S"
    }

    private var pixelRows: [String] {
        var rows = [
            "................",
            "......BBBB......",
            "....BBBBBBBB....",
            "...BBBBBBBBBB...",
            "..BBBBBBBBBBBB..",
            "..BBBBBBBBBBBB..",
            "..BBBBBBBBBBBB..",
            "..BBBBEEBBEEBB..",
            "..BBBBBBBBBBBB..",
            "...BBBBMMBBBB...",
            "....BBBBBBBB....",
            "....BBBBBBBB....",
            "....BBBBBBBB....",
            ".....BBBBBB.....",
            "......BBBB......",
            "................"
        ]

        switch sprite {
        case .skyBuddy:
            rows[1] = ".....BBBBBB....."
//            rows[6] = mouthCharacter == "S" ? "..BBBBAABBAAAB.." : "..BBBBAABBAABB.."
        case .peachPal:
            rows[4] = "..BBBBBBBBBBBB.."
            rows[7] = "..BBBBEBBBEBBB.."
//            rows[6] = mouthCharacter == "S" ? "..BBBFFFBBBFFB.." : "..BBBFFBBBBFFB.."
        case .mintBean:
            if clothing == .topHat || clothing == .crown || clothing == .propellerHat {
                rows[1] = ".....BBLLBB....."
                rows[2] = "...BBBLLLLBBB..."
            }
//            rows[6] = mouthCharacter == "S" ? "..BBCCBBBCCCBB.." : "..BBCCBBBBCCBB.."
        }

        if mouthCharacter == "S" {
            rows[9] = "...BBBBSSBBBB..."
        }

        switch clothing {
        case .none:
            break
        case .propellerHat:
            rows[0] = "......GGGG......"
            rows[1] = "....VVVGXGVVV..."
            rows[2] = "......GGGG......"
            rows[3] = ".....BBBBBB....."
        case .topHat:
            rows[0] = ".....UUUUUU....."
            rows[1] = ".....UUUUUU....."
            rows[2] = "....UUURRRUU...."
            rows[3] = "...UUUUUUUUUU..."
        case .crown:
            rows[0] = ".....Y.YY.Y....."
            rows[1] = ".....YYYYYY....."
            rows[2] = "....YYOOOOYY...."
            rows[3] = "....YYYYYYYY...."
        }

        return rows
    }

    private var pixelPalette: [Character: Color] {
        [
            ".": .clear,
            "B": shellColor,
            "E": Color(red: 0.16, green: 0.24, blue: 0.34),
            "M": Color(red: 0.93, green: 0.44, blue: 0.48),
            "S": Color(red: 0.63, green: 0.45, blue: 0.54),
            "L": Color.white.opacity(0.45),
            "A": Color(red: 0.12, green: 0.30, blue: 0.47),
            "C": Color(red: 0.20, green: 0.46, blue: 0.34),
            "F": Color(red: 0.44, green: 0.20, blue: 0.29),
            "G": clothing == .propellerHat ? clothing.color : Color(red: 0.24, green: 0.74, blue: 0.66),
            "V": Color(red: 0.94, green: 0.34, blue: 0.40),
            "X": Color(red: 0.99, green: 0.84, blue: 0.36),
            "U": Color(red: 0.13, green: 0.14, blue: 0.18),
            "R": clothing == .topHat ? clothing.color : Color(red: 0.22, green: 0.48, blue: 0.88),
            "Y": Color(red: 0.98, green: 0.76, blue: 0.29),
            "O": Color(red: 0.95, green: 0.45, blue: 0.38)
        ]
    }
}

private struct PixelCharacterGrid: View {
    let pixels: [String]
    let palette: [Character: Color]

    var body: some View {
        GeometryReader { geometry in
            let columns = max(pixels.first?.count ?? 1, 1)
            let rows = max(pixels.count, 1)
            let pixelSize = min(geometry.size.width / CGFloat(columns), geometry.size.height / CGFloat(rows))
            let artWidth = pixelSize * CGFloat(columns)
            let artHeight = pixelSize * CGFloat(rows)
            let xOrigin = (geometry.size.width - artWidth) / 2
            let yOrigin = (geometry.size.height - artHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(pixels.enumerated()), id: \.offset) { rowIndex, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, char in
                        if char != ".", let color = palette[char] {
                            Rectangle()
                                .fill(color)
                                .frame(width: pixelSize, height: pixelSize)
                                .position(
                                    x: xOrigin + CGFloat(colIndex) * pixelSize + (pixelSize / 2),
                                    y: yOrigin + CGFloat(rowIndex) * pixelSize + (pixelSize / 2)
                                )
                        }
                    }
                }
            }
        }
    }
}

private struct DetailPageCard: View {
    let page: HomePage
    let items: [InboxItem]
    @Binding var selectedSprite: SpriteProfile
    @Binding var selectedClothing: ClothingOption
    @Binding var selectedDanceSpeed: DanceSpeed
    @Binding var streakTier: Int
    @Binding var selectedTheme: AppTheme
    @Binding var streakDays: Int
    let onRotateSprite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            Text(page.description)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.31, green: 0.45, blue: 0.50))

            if page == .inbox {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        InboxRow(item: item)
                    }
                }
            } else if page == .upgrades {
                upgradesSection
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    DetailBullet(text: page.primaryLine)
                    DetailBullet(text: page.secondaryLine)
                    DetailBullet(text: page.tertiaryLine)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.58), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
    }

    private var upgradesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sprite")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            Text("Active sprite: \(selectedSprite.displayName)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

            Button(action: onRotateSprite) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                    Text("Rotate Sprite")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(selectedSprite.highlightColor)
                )
            }
            .buttonStyle(.plain)

            ForEach(SpriteProfile.allCases) { sprite in
                Button(action: { selectedSprite = sprite }) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(sprite.highlightColor)
                            .frame(width: 14, height: 14)

                        Text(sprite.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

                        Spacer()

                        if sprite == selectedSprite {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(sprite.highlightColor)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.70))
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Clothing")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ClothingOption.allCases) { clothing in
                    Button(action: { selectedClothing = clothing }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(clothing.color)
                                .frame(width: 12, height: 12)
                            Text(clothing.displayName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedClothing == clothing ? clothing.color.opacity(0.25) : Color.white.opacity(0.70))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Dance Speed")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            HStack(spacing: 8) {
                ForEach(DanceSpeed.allCases) { speed in
                    Button(action: { selectedDanceSpeed = speed }) {
                        Text(speed.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedDanceSpeed == speed ? .white : Color(red: 0.10, green: 0.17, blue: 0.27))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedDanceSpeed == speed ? selectedSprite.highlightColor : Color.white.opacity(0.72))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Streak")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            Stepper(value: $streakTier, in: 1...3) {
                Text("Streak Boost Tier \(streakTier)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))
            }

            Text("Current streak: \(streakDays) days")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.21, green: 0.33, blue: 0.40))

            Text("Effect: +\(streakTier * 2) health per call, decay drops to \(max(1, 4 - streakTier)).")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.52))

            Text("Themes")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            ForEach(AppTheme.allCases) { theme in
                Button(action: { selectedTheme = theme }) {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Circle().fill(theme.primary).frame(width: 10, height: 10)
                            Circle().fill(theme.secondary).frame(width: 10, height: 10)
                            Circle().fill(theme.tertiary).frame(width: 10, height: 10)
                        }

                        Text(theme.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

                        Spacer()

                        if selectedTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(theme.primary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.70))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LogPageCard: View {
    @Binding var name: String
    @Binding var minutes: String
    let entries: [CallLogEntry]
    let onSubmit: () -> Void

    private var formIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Int(minutes) ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Log a Call")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            Text("Add who you called and how long you talked so the dashboard can track your recent check-ins.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.31, green: 0.45, blue: 0.50))

            VStack(alignment: .leading, spacing: 14) {
                LogInputField(title: "Name", placeholder: "Mom", text: $name)
                LogInputField(title: "Minutes", placeholder: "15", text: $minutes, isNumeric: true)

                Button(action: onSubmit) {
                    HStack {
                        Image(systemName: "phone.badge.plus.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Save Call")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(formIsValid ? Color(red: 0.12, green: 0.76, blue: 0.60) : Color(red: 0.67, green: 0.78, blue: 0.77))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!formIsValid)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Calls")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

                ForEach(entries) { entry in
                    CallLogRow(entry: entry)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.58), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
    }
}

private struct LogInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isNumeric = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

            TextField(placeholder, text: $text)
                .keyboardType(isNumeric ? .numberPad : .default)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
        }
    }
}

private struct CallLogRow: View {
    let entry: CallLogEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.86, green: 0.96, blue: 0.94))
                    .frame(width: 42, height: 42)

                Image(systemName: "phone.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.62, blue: 0.54))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

                Text("\(entry.minutes) minute\(entry.minutes == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.39, green: 0.49, blue: 0.54))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct DetailBullet: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.16, green: 0.68, blue: 0.61))
                .frame(width: 10, height: 10)

            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.kind.color)
                .frame(width: 12, height: 12)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.10, green: 0.17, blue: 0.27))

                Text(item.subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.39, green: 0.49, blue: 0.54))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct ActionDock: View {
    @Binding var activePage: HomePage
    let metrics: LayoutMetrics
    let onLogTap: () -> Void
    let onSelectPage: (HomePage) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(HomePage.dockCases, id: \.self) { page in
                DockButton(
                    page: page,
                    isSelected: activePage == page,
                    metrics: metrics,
                    onTap: {
                        if page == .log {
                            onLogTap()
                        } else {
                            onSelectPage(page)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, metrics.dockInnerTopPadding)
        .padding(.bottom, metrics.dockInnerBottomPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.60), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)
    }
}

private struct DockButton: View {
    let page: HomePage
    let isSelected: Bool
    let metrics: LayoutMetrics
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? page.highlightColor : .white)
                        .frame(
                            width: isSelected ? metrics.dockSelectedSize : metrics.dockButtonSize,
                            height: isSelected ? metrics.dockSelectedSize : metrics.dockButtonSize
                        )

                    Image(systemName: page.symbol)
                        .font(.system(size: isSelected ? 22 : 19, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Color(red: 0.11, green: 0.18, blue: 0.29))
                }

                Text(page.label)
                    .font(.system(size: metrics.dockLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color(red: 0.09, green: 0.16, blue: 0.26) : Color(red: 0.34, green: 0.44, blue: 0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CircularIconButton: View {
    let systemName: String
    let diameter: CGFloat
    let iconSize: CGFloat
    let showDot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(red: 0.11, green: 0.64, blue: 0.57))
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .center) {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .topTrailing) {
                    if showDot {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.43, blue: 0.48))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SoftClouds: View {
    var body: some View {
        ZStack {
            Cloud()
                .frame(width: 132, height: 48)
                .offset(x: -18, y: -320)

            Cloud()
                .frame(width: 112, height: 42)
                .offset(x: 126, y: -248)

            Cloud()
                .frame(width: 94, height: 34)
                .offset(x: -140, y: -188)
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }
}

private struct Cloud: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.28, width: rect.width * 0.34, height: rect.height * 0.44))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.08, width: rect.width * 0.34, height: rect.height * 0.54))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.24, width: rect.width * 0.34, height: rect.height * 0.44))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.34, width: rect.width * 0.56, height: rect.height * 0.34), cornerSize: CGSize(width: rect.height * 0.18, height: rect.height * 0.18))
        return path
    }
}

private struct FirTree: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: -height * 0.12) {
            Triangle()
                .fill(Color(red: 0.02, green: 0.63, blue: 0.53))
                .frame(width: height * 0.4, height: height * 0.34)
            Triangle()
                .fill(Color(red: 0.05, green: 0.72, blue: 0.61))
                .frame(width: height * 0.54, height: height * 0.42)
            Triangle()
                .fill(Color(red: 0.08, green: 0.53, blue: 0.49))
                .frame(width: height * 0.7, height: height * 0.48)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.14, green: 0.41, blue: 0.57))
                .frame(width: height * 0.08, height: height * 0.26)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SmoothHill: Shape {
    let heightFactor: CGFloat
    let peak: CGFloat
    let valley: CGFloat

    func path(in rect: CGRect) -> Path {
        let baseY = rect.height
        let peakY = rect.height * (1 - heightFactor)
        let valleyY = rect.height * (1 - heightFactor * 0.48)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: baseY))
        path.addCurve(
            to: CGPoint(x: rect.width * peak, y: peakY),
            control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.72),
            control2: CGPoint(x: rect.width * (peak - 0.18), y: peakY)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * valley, y: valleyY),
            control1: CGPoint(x: rect.width * (peak + 0.10), y: peakY),
            control2: CGPoint(x: rect.width * (valley - 0.10), y: valleyY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.64),
            control1: CGPoint(x: rect.width * (valley + 0.16), y: rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.66)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: baseY))
        path.closeSubpath()
        return path
    }
}

private struct InboxItem: Identifiable {
    enum Kind {
        case reminder
        case streak
        case message

        var color: Color {
            switch self {
            case .reminder:
                return Color(red: 0.49, green: 0.84, blue: 0.97)
            case .streak:
                return Color(red: 0.49, green: 0.93, blue: 0.72)
            case .message:
                return Color(red: 1.0, green: 0.72, blue: 0.45)
            }
        }
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let kind: Kind
}

private struct CallLogEntry: Identifiable {
    let id = UUID()
    let name: String
    let minutes: Int
    let loggedAt: Date
}

private enum StreakCalculator {
    static func currentStreak(from logs: [CallLogEntry], calendar: Calendar = .current) -> Int {
        let uniqueDays = Set(logs.map { calendar.startOfDay(for: $0.loggedAt) })
        let today = calendar.startOfDay(for: Date())

        guard uniqueDays.contains(today) else { return 0 }

        var streak = 0
        var cursor = today

        while uniqueDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }
}

private enum ClothingOption: String, CaseIterable, Identifiable {
    case none
    case propellerHat
    case topHat
    case crown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .propellerHat:
            return "Propeller Hat"
        case .topHat:
            return "Top Hat"
        case .crown:
            return "Crown"
        }
    }

    var color: Color {
        switch self {
        case .none:
            return Color(red: 0.75, green: 0.78, blue: 0.84)
        case .propellerHat:
            return Color(red: 0.24, green: 0.74, blue: 0.66)
        case .topHat:
            return Color(red: 0.22, green: 0.48, blue: 0.88)
        case .crown:
            return Color(red: 0.98, green: 0.76, blue: 0.29)
        }
    }
}

private enum DanceSpeed: String, CaseIterable, Identifiable {
    case chill
    case normal
    case turbo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chill:
            return "Chill"
        case .normal:
            return "Normal"
        case .turbo:
            return "Turbo"
        }
    }

    var duration: Double {
        switch self {
        case .chill:
            return 0.95
        case .normal:
            return 0.55
        case .turbo:
            return 0.28
        }
    }
}

private enum AppTheme: String, CaseIterable, Identifiable {
    case meadow
    case sunset
    case moonlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meadow:
            return "Meadow"
        case .sunset:
            return "Sunset"
        case .moonlight:
            return "Moonlight"
        }
    }

    var primary: Color {
        switch self {
        case .meadow:
            return Color(red: 0.82, green: 0.92, blue: 1.0)
        case .sunset:
            return Color(red: 0.99, green: 0.79, blue: 0.70)
        case .moonlight:
            return Color(red: 0.60, green: 0.72, blue: 0.92)
        }
    }

    var secondary: Color {
        switch self {
        case .meadow:
            return Color(red: 0.78, green: 0.91, blue: 0.99)
        case .sunset:
            return Color(red: 0.98, green: 0.70, blue: 0.67)
        case .moonlight:
            return Color(red: 0.48, green: 0.61, blue: 0.83)
        }
    }

    var tertiary: Color {
        switch self {
        case .meadow:
            return Color(red: 0.67, green: 0.89, blue: 0.89)
        case .sunset:
            return Color(red: 0.95, green: 0.58, blue: 0.62)
        case .moonlight:
            return Color(red: 0.33, green: 0.47, blue: 0.72)
        }
    }

    var hillOne: Color {
        switch self {
        case .meadow:
            return Color(red: 0.55, green: 0.77, blue: 0.97)
        case .sunset:
            return Color(red: 0.96, green: 0.60, blue: 0.53)
        case .moonlight:
            return Color(red: 0.39, green: 0.57, blue: 0.84)
        }
    }

    var hillTwo: Color {
        switch self {
        case .meadow:
            return Color(red: 0.62, green: 0.82, blue: 0.96)
        case .sunset:
            return Color(red: 0.92, green: 0.52, blue: 0.48)
        case .moonlight:
            return Color(red: 0.31, green: 0.49, blue: 0.76)
        }
    }

    var hillThree: Color {
        switch self {
        case .meadow:
            return Color(red: 0.24, green: 0.79, blue: 0.70)
        case .sunset:
            return Color(red: 0.86, green: 0.40, blue: 0.40)
        case .moonlight:
            return Color(red: 0.24, green: 0.40, blue: 0.61)
        }
    }
}

private enum SpriteProfile: String, CaseIterable, Identifiable {
    case skyBuddy
    case peachPal
    case mintBean

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skyBuddy:
            return "Sky Buddy"
        case .peachPal:
            return "Peach Pal"
        case .mintBean:
            return "Mint Bean"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .skyBuddy:
            return "cloud.fill"
        case .peachPal:
            return "sparkles"
        case .mintBean:
            return "leaf.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .skyBuddy:
            return Color(red: 0.73, green: 0.92, blue: 1.0)
        case .peachPal:
            return Color(red: 1.0, green: 0.90, blue: 0.58)
        case .mintBean:
            return Color(red: 0.72, green: 1.0, blue: 0.85)
        }
    }

    var highlightColor: Color {
        switch self {
        case .skyBuddy:
            return Color(red: 0.33, green: 0.65, blue: 0.98)
        case .peachPal:
            return Color(red: 0.98, green: 0.63, blue: 0.36)
        case .mintBean:
            return Color(red: 0.12, green: 0.76, blue: 0.60)
        }
    }

    var highHealthShellColor: Color {
        switch self {
        case .skyBuddy:
            return Color(red: 0.45, green: 0.73, blue: 0.98)
        case .peachPal:
            return Color(red: 0.98, green: 0.65, blue: 0.54)
        case .mintBean:
            return Color(red: 0.39, green: 0.82, blue: 0.68)
        }
    }

    var midHealthShellColor: Color {
        switch self {
        case .skyBuddy:
            return Color(red: 0.61, green: 0.70, blue: 0.92)
        case .peachPal:
            return Color(red: 0.93, green: 0.70, blue: 0.63)
        case .mintBean:
            return Color(red: 0.56, green: 0.75, blue: 0.66)
        }
    }

    var lowHealthShellColor: Color {
        switch self {
        case .skyBuddy:
            return Color(red: 0.73, green: 0.62, blue: 0.84)
        case .peachPal:
            return Color(red: 0.81, green: 0.58, blue: 0.72)
        case .mintBean:
            return Color(red: 0.52, green: 0.63, blue: 0.64)
        }
    }
}

private enum HomePage: CaseIterable {
    case home
    case upgrades
    case settings
    case log
    case inbox

    static var dockCases: [HomePage] {
        [.home, .upgrades, .settings, .log]
    }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .upgrades:
            return "Upgrades"
        case .settings:
            return "Settings"
        case .log:
            return "Log"
        case .inbox:
            return "Inbox"
        }
    }

    var description: String {
        switch self {
        case .home:
            return ""
        case .upgrades:
            return "Customize your sprite with clothing, dance speed, streak boosts, and themes."
        case .settings:
            return "Preferences for reminders, contacts, and appearance."
        case .log:
            return "A running history of calls, streaks, and recent check-ins."
        case .inbox:
            return "Your notification center for reminders, updates, and replies."
        }
    }

    var primaryLine: String {
        switch self {
        case .home:
            return ""
        case .upgrades:
            return "Swap between cute pixel companions."
        case .settings:
            return "Notification preferences belong here."
        case .log:
            return "Recent activity timeline goes here."
        case .inbox:
            return ""
        }
    }

    var secondaryLine: String {
        switch self {
        case .home:
            return ""
        case .upgrades:
            return "Tune style and speed to match your vibe."
        case .settings:
            return "Contact defaults and quiet hours can fit here."
        case .log:
            return "Streak summaries and monthly stats fit naturally here."
        case .inbox:
            return ""
        }
    }

    var tertiaryLine: String {
        switch self {
        case .home:
            return ""
        case .upgrades:
            return "Boost streak health bonuses while customizing your world."
        case .settings:
            return "Keeping it off home leaves more room for the sprite."
        case .log:
            return "This keeps the landing page uncluttered."
        case .inbox:
            return ""
        }
    }

    var label: String {
        switch self {
        case .home:
            return "Home"
        case .upgrades:
            return "Upgrades"
        case .settings:
            return "Settings"
        case .log:
            return "Log"
        case .inbox:
            return "Inbox"
        }
    }

    var symbol: String {
        switch self {
        case .home:
            return "house.fill"
        case .upgrades:
            return "bag.fill"
        case .settings:
            return "gearshape.fill"
        case .log:
            return "clock.arrow.circlepath"
        case .inbox:
            return "tray.fill"
        }
    }

    var highlightColor: Color {
        switch self {
        case .home:
            return Color(red: 0.33, green: 0.65, blue: 0.98)
        case .upgrades:
            return Color(red: 0.98, green: 0.63, blue: 0.36)
        case .settings:
            return Color(red: 0.44, green: 0.58, blue: 0.94)
        case .log:
            return Color(red: 0.12, green: 0.76, blue: 0.60)
        case .inbox:
            return Color(red: 0.97, green: 0.58, blue: 0.42)
        }
    }
}
