//
//  DashboardView.swift
//  call-your-mom
//
//  Created by Ben Cerbin, Adrian Clement, and Dylan O'Connor on 4/21/26.
//

import SwiftUI
import Contacts
import ContactsUI
import AVFoundation
import CallKit
internal import Combine

enum ButtonClickSound {
    private static let hapticGenerator: UIImpactFeedbackGenerator = {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        return generator
    }()

    static func play() {
        // Click sounds intentionally disabled; keep haptics only.
    }

    static func perform(_ action: () -> Void) {
        hapticGenerator.impactOccurred(intensity: 0.7)
        hapticGenerator.prepare()
        action()
    }

    static func action(_ action: @escaping () -> Void) -> () -> Void {
        {
            perform(action)
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }
}

private enum AppSoundEffect: String, CaseIterable {
    case levelUp
    case flappyFlap
}

private enum SoundEffectPlayer {
    private static let fileExtensions = ["wav", "mp3", "m4a", "caf", "aiff"]
    private static let defaultsKey = "soundEffects.fileMap"
    private static let bundledSFXSubdirectory = "SFX"
    private static var players: [String: AVAudioPlayer] = [:]
    private static var fallbackURLs: [String: URL] = [:]

    // Default sound file names (without extension).
    // Replace these files in the app bundle, or override via setFilename(_:for:).
    private static let defaultFileMap: [AppSoundEffect: String] = [
        .levelUp: "sfx_level_up",
        .flappyFlap: "sfx_flappy_flap"
    ]

    static func play(_ effect: AppSoundEffect) {
        if effect == .flappyFlap {
            return
        }
        guard let filename = filename(for: effect) else { return }
        guard let player = player(forFilename: filename) else { return }
        player.currentTime = 0
        player.play()
    }

    static func setFilename(_ filename: String, for effect: AppSoundEffect) {
        var map = persistedFileMap()
        map[effect.rawValue] = filename
        UserDefaults.standard.set(map, forKey: defaultsKey)
        players[filename] = nil
    }

    private static func filename(for effect: AppSoundEffect) -> String? {
        let overrides = persistedFileMap()
        if let override = overrides[effect.rawValue], !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return defaultFileMap[effect]
    }

    private static func persistedFileMap() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    private static func player(forFilename filename: String) -> AVAudioPlayer? {
        if let cached = players[filename] {
            return cached
        }

        let url = resolveBundleURL(filename: filename) ?? fallbackURL(for: filename)
        guard let url else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[filename] = player
        return player
    }

    private static func resolveBundleURL(filename: String) -> URL? {
        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

        for ext in fileExtensions {
            if let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: bundledSFXSubdirectory) {
                return url
            }
            if let url = Bundle.main.url(forResource: baseName, withExtension: ext) {
                return url
            }
        }

        let providedExtension = URL(fileURLWithPath: filename).pathExtension
        if !providedExtension.isEmpty {
            if let url = Bundle.main.url(forResource: baseName, withExtension: providedExtension, subdirectory: bundledSFXSubdirectory) {
                return url
            }
            if let url = Bundle.main.url(forResource: baseName, withExtension: providedExtension) {
                return url
            }
        }

        return nil
    }

    private static func fallbackURL(for filename: String) -> URL? {
        if let existing = fallbackURLs[filename] {
            return existing
        }

        let waveform: Data
        let levelUpName = defaultFileMap[.levelUp] ?? "sfx_level_up"
        let flapName = defaultFileMap[.flappyFlap] ?? "sfx_flappy_flap"
        switch filename {
        case levelUpName:
            waveform = makeLevelUpData()
        case flapName:
            waveform = makeFlapData()
        default:
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename).wav")
        try? waveform.write(to: tempURL, options: .atomic)
        fallbackURLs[filename] = tempURL
        return tempURL
    }

    private static func makeFlapData() -> Data {
        makeWAVData(
            duration: 0.06,
            sampleRate: 44_100
        ) { time in
            let env = exp(-55 * time)
            let tone = sin(2 * Double.pi * 520 * time)
            let edge = sin(2 * Double.pi * 980 * time) * 0.28
            return (tone + edge) * env * 0.45
        }
    }

    private static func makeLevelUpData() -> Data {
        makeWAVData(
            duration: 0.28,
            sampleRate: 44_100
        ) { time in
            let env = exp(-6.2 * time)
            let glide = 420 + (time * 560)
            let lead = sin(2 * Double.pi * glide * time)
            let harmony = sin(2 * Double.pi * (glide * 1.5) * time) * 0.25
            return (lead + harmony) * env * 0.42
        }
    }

    private static func makeWAVData(duration: Double, sampleRate: Int, sample: (Double) -> Double) -> Data {
        let channelCount = 1
        let bitsPerSample = 16
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcmData = Data()

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let clamped = max(-1, min(1, sample(time)))
            var intSample = Int16(clamped * Double(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &intSample) {
                pcmData.append(contentsOf: $0)
            }
        }

        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(36 + pcmData.count))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }
}

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var callActivityObserver = CallActivityObserver()

    @State private var activePage: HomePage = .home
    @State private var pageHistory: [HomePage] = []
    @State private var quickActionsExpanded = false
    @State private var health = HealthPersistence.defaultHealth
    @State private var currentSpriteHealthIsActivated = false
    @State private var hasRestoredCurrentSpriteHealth = false
    @State private var isHibernating = false
    @State private var callsLogged = HealthPersistence.defaultCallsLogged
    @State private var contacts = SettingsPersistence.defaultSettings.contacts
    @State private var preferredContactID = SettingsPersistence.defaultSettings.preferredContactID
    @State private var selectedLogContactID = SettingsPersistence.defaultSettings.preferredContactID
    @State private var spriteContactAssignments = SettingsPersistence.defaultSettings.spriteContactAssignments
    @State private var logMinutes: String = ""
    @State private var defaultCallMinutes = SettingsPersistence.defaultSettings.defaultCallMinutes
    @State private var notificationPreferences = SettingsPersistence.defaultSettings.notificationPreferences
    @State private var healthPulse = false
    @State private var lastHealthUpdatedAt = Date()
    @State private var wasBelowLowHealthThreshold = false
    @State private var callLogs: [CallLogEntry] = []
    @State private var availableSprites: [TamagotchiSpriteProfile] = TamagotchiSpriteCatalog.load()
    @State private var selectedSprite: TamagotchiSpriteProfile = TamagotchiSpriteCatalog.preferredInitialSprite(from: TamagotchiSpriteCatalog.load())
    @State private var selectedClothing: ClothingOption = .none
    @State private var selectedDanceSpeed: DanceSpeed = .normal
    @State private var currencyBalances = EconomyPersistence.loadBalances()
    @State private var selectedTheme: AppTheme = .meadow
    @State private var streakDays: Int = 0
    @State private var isContactPickerPresented = false
    @State private var pendingCallSession: PendingCallSession?
    @State private var postCallPrompt: PendingCallSession?
    @State private var callFailureMessage: String?
    @State private var isReminderPickerPresented = false
    @State private var reminderDraft = CallReminderDraft()
    @State private var isDefaultContactPickerPresented = false
    @State private var selectedDefaultContactDraftID: UUID?
    @State private var isSpriteContactAssignmentPresented = false
    @State private var pendingSpriteAssignmentSpriteID: String?
    @State private var selectedSpriteAssignmentContactID: UUID?
    @State private var isDefaultContactPromptPresented = false
    @State private var isWalkthroughPresented = false
    @State private var walkthroughIndex = 0
    @State private var isGameMode = false
    @State private var isLaunchingGame = false
    @State private var gameEntryProgress: CGFloat = 0
    @State private var activeHomePanelIndex = 1
    @State private var homeDragTranslation: CGFloat = 0
    @State private var isHomePanelSwipeInProgress = false
    @State private var lastHomePanelSwipeEndedAt = Date.distantPast
    @State private var isGardenDraggingPet = false
    @State private var spriteLevels: [String: SpriteLevel] = [:]
    @State private var currentSpriteLevel: SpriteLevel = SpriteLevel(spriteID: "default")
    @State private var showLevelUpNotification = false
    @State private var lastLevelUpValue = 1
    @State private var levelUpNotificationSequence = 0
    @State private var isKeyboardVisible = false
    @State private var isShowingLaunchSplash = true
    @State private var hasCompletedInitialLoad = false
    private let decayTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let minimumCallPromptDelay: TimeInterval = 20
    private let stalePendingCallInterval: TimeInterval = 30 * 60
    private let homePanelSwipeTapSuppressionInterval: TimeInterval = 0.25

    private func loadSpriteLevels() {
        spriteLevels = LevelPersistence.load()
        updateCurrentSpriteLevel()
    }

    private func updateCurrentSpriteLevel() {
        currentSpriteLevel = spriteLevels[selectedSprite.id] ?? SpriteLevel(spriteID: selectedSprite.id)
    }

    private func resetCurrentSpriteLevel() {
        if spriteLevels.isEmpty {
            spriteLevels = LevelPersistence.load()
        }
        currentSpriteLevel = SpriteLevel(spriteID: selectedSprite.id)
        saveCurrentSpriteLevel()
        lastLevelUpValue = 1
        showLevelUpNotification = false
    }

    private func saveCurrentSpriteLevel() {
        spriteLevels[currentSpriteLevel.spriteID] = currentSpriteLevel
        LevelPersistence.save(spriteLevels)
    }

    private func awardExperienceForFeeding(_ option: FeedingOption) {
        let didLevelUp = currentSpriteLevel.addExperience(option.experienceGain)
        saveCurrentSpriteLevel()

        if didLevelUp {
            showLevelUpToast(level: currentSpriteLevel.level)
        }
    }

    private func showLevelUpToast(level: Int) {
        lastLevelUpValue = level
        levelUpNotificationSequence += 1
        let notificationSequence = levelUpNotificationSequence
        SoundEffectPlayer.play(.levelUp)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showLevelUpNotification = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard notificationSequence == levelUpNotificationSequence else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showLevelUpNotification = false
            }
        }
    }

    private var streakTier: Int {
        StreakCalculator.tier(for: streakDays)
    }

    var body: some View {
        dashboardAlerts
    }

    private var dashboardLifecycle: some View {
        dashboardRoot
            .onAppear(perform: handleAppear)
            .onReceive(decayTimer) { _ in
                guard scenePhase == .active else { return }
                applyElapsedDecay(now: Date())
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isKeyboardVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isKeyboardVisible = false
                }
            }
    }

    private var dashboardChangeHandlers: some View {
        dashboardLifecycle
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: health) { _, _ in
                persistHealthState()
                enterHibernationIfNeeded()
                syncLowHealthNotification()
            }
            .onChange(of: callLogs) { _, _ in
                AppStatePersistence.saveCallLogs(callLogs)
            }
            .onChange(of: currencyBalances) { _, newValue in
                EconomyPersistence.saveBalances(newValue)
            }
            .onChange(of: contacts) { _, _ in
                handleContactsChange()
            }
            .onChange(of: preferredContactID) { _, _ in
                handlePreferredContactChange()
            }
            .onChange(of: spriteContactAssignments) { _, _ in
                handleSpriteContactAssignmentsChange()
            }
            .onChange(of: notificationPreferences) { _, _ in
                persistSettings()
                syncNotificationSchedules()
            }
            .onChange(of: activePage) { _, newValue in
                presentDefaultContactPromptIfNeeded(for: newValue)
            }
            .onChange(of: callActivityObserver.latestEvent) { _, event in
                handleCallActivity(event)
            }
    }

    private var dashboardSheets: some View {
        dashboardChangeHandlers
            .sheet(isPresented: $isContactPickerPresented) {
                SystemContactPicker { contact in
                    importSystemContact(contact)
                }
            }
            .sheet(isPresented: $isReminderPickerPresented) {
                ReminderEditorSheet(
                    contacts: contacts,
                    draft: $reminderDraft,
                    onSave: applyReminderDraft
                )
            }
            .sheet(isPresented: $isDefaultContactPickerPresented) {
                DefaultContactPickerSheet(
                    contacts: contacts,
                    selectedContactID: $selectedDefaultContactDraftID,
                    onSave: applyDefaultContactDraft
                )
            }
            .sheet(isPresented: $isSpriteContactAssignmentPresented) {
                SpriteContactAssignmentSheet(
                    spriteName: pendingSpriteAssignmentSpriteName,
                    contacts: contacts,
                    selectedContactID: $selectedSpriteAssignmentContactID,
                    onSave: applySpriteContactAssignmentDraft
                )
            }
    }

    private var dashboardAlerts: some View {
        dashboardSheets
            .alert(
            "Log your call?",
            isPresented: postCallPromptBinding,
            presenting: postCallPrompt
        ) { session in
            Button("Save \(loggableMinutes(for: session)) min") {
                ButtonClickSound.perform {
                    savePendingCall(session)
                }
            }

            Button("Review") {
                ButtonClickSound.perform {
                    reviewPendingCall(session)
                }
            }

            Button("Later", role: .cancel) {
                ButtonClickSound.perform {
                    deferPendingCallPrompt()
                }
            }
        } message: { session in
            Text("Add your call with \(session.contactName) to earn coins for food.")
        }
        .alert(
            "Can't Start Call",
            isPresented: callFailureBinding
        ) {
            Button("OK", role: .cancel) {
                ButtonClickSound.perform {
                    callFailureMessage = nil
                }
            }
        } message: {
            Text(callFailureMessage ?? "")
        }
        .alert("Add a default contact", isPresented: $isDefaultContactPromptPresented) {
            Button("Import Contacts") {
                ButtonClickSound.perform(importDefaultContactFromPrompt)
            }

            Button("Add Manually", role: .cancel) {
                ButtonClickSound.perform {}
            }
        } message: {
            Text("Choose someone to check in with so call logging and reminders can start from a real person.")
        }
    }

    private var dashboardRoot: some View {
        GeometryReader { geometry in
            dashboardContent(for: geometry)
        }
    }

    private func dashboardContent(for geometry: GeometryProxy) -> some View {
        let metrics = LayoutMetrics(container: geometry.size, safeArea: geometry.safeAreaInsets)
        return dashboardScene(
            containerSize: geometry.size,
            metrics: metrics,
            showingGame: isShowingGame
        )
    }

    private var postCallPromptBinding: Binding<Bool> {
        Binding(
            get: { postCallPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    deferPendingCallPrompt()
                }
            }
        )
    }

    private var callFailureBinding: Binding<Bool> {
        Binding(
            get: { callFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    callFailureMessage = nil
                }
            }
        )
    }

    private func handleScenePhaseChange(_ oldValue: ScenePhase, _ newValue: ScenePhase) {
        if newValue == .active {
            reloadSpriteCatalog()
            restoreSettings()
            ensureSelectedSpriteCanBeUsed()
            restorePersistedHealth()
            restorePendingCallTracking()
            presentPostCallPromptIfReady()
        } else if newValue == .background {
            markPendingCallDidLeaveApp()
            persistHealthState()
            persistAppState()
            persistSettings()
            persistPendingCallTracking()
            syncLowHealthNotification()
        } else if newValue == .inactive {
            persistHealthState()
            persistAppState()
            persistSettings()
            persistPendingCallTracking()
            syncLowHealthNotification()
        }
    }

    private func handleContactsChange() {
        sanitizeContactsAfterMutation()
        persistSettings()
        syncNotificationSchedules()
    }

    private func handlePreferredContactChange() {
        if selectedLogContactID == nil || !contacts.contains(where: { $0.id == selectedLogContactID }) {
            selectedLogContactID = preferredContactID
        }
        persistSettings()
        syncNotificationSchedules()
    }

    private func handleSpriteContactAssignmentsChange() {
        sanitizeSpriteContactAssignments()
        ensureSelectedSpriteCanBeUsed()
        if let currentAssignedContactID {
            selectedLogContactID = currentAssignedContactID
        }
        persistSettings()
    }

    private func importDefaultContactFromPrompt() {
        DispatchQueue.main.async {
            isContactPickerPresented = true
        }
    }

    private var pendingSpriteAssignmentSpriteName: String {
        guard
            let spriteID = pendingSpriteAssignmentSpriteID,
            let sprite = availableSprites.first(where: { $0.id == spriteID })
        else {
            return "this sprite"
        }
        return sprite.displayName
    }

    private func promptAssignContactForLockedSprite(_ sprite: TamagotchiSpriteProfile) {
        guard !contacts.isEmpty else {
            isContactPickerPresented = true
            return
        }

        pendingSpriteAssignmentSpriteID = sprite.id
        selectedSpriteAssignmentContactID = spriteContactAssignments[sprite.id] ?? preferredContactID ?? contacts.first?.id
        isSpriteContactAssignmentPresented = true
    }

    private func handleAppear() {
        guard !hasCompletedInitialLoad else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            healthPulse = true
        }
        reloadSpriteCatalog()
        restoreAppState()
        migrateLegacyCurrencyIfNeeded()
        loadSpriteLevels()
        LocalNotificationManager.shared.requestAuthorization()
        restoreSettings()
        ensureSelectedSpriteCanBeUsed()
        restorePersistedHealth()
        activateDefaultSpriteHealthIfNeeded()
        restorePendingCallTracking()
        refreshStreakDays()
        syncNotificationSchedules()
        presentPostCallPromptIfReady()
        startWalkthroughIfNeeded()
        hasCompletedInitialLoad = true
        withAnimation(.easeOut(duration: 0.14)) {
            isShowingLaunchSplash = false
        }
    }

    private func handleKeyboardDismissDrag(_ value: DragGesture.Value) {
        guard isKeyboardVisible else { return }

        let horizontalTravel = abs(value.translation.width)
        let verticalTravel = abs(value.translation.height)

        if verticalTravel > horizontalTravel {
            dismissKeyboard()
        }
    }

    private var isShowingGame: Bool {
        activePage == .home && (isGameMode || isLaunchingGame)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func dashboardScene(containerSize: CGSize, metrics: LayoutMetrics, showingGame: Bool) -> some View {
        ZStack {
            AppSkyBackground(theme: selectedTheme)

            AppSceneBackground(theme: selectedTheme)
                .offset(y: -metrics.backgroundSceneLift)

            gameScene(showingGame: showingGame)

            activeContentStack(metrics: metrics, showingGame: showingGame)

            launchingGameOverlay(containerSize: containerSize, metrics: metrics)

            walkthroughOverlay(metrics: metrics, showingGame: showingGame)

            levelUpToast(metrics: metrics, showingGame: showingGame)

            launchSplashOverlay
        }
        .overlay(alignment: .bottom) {
            actionDockOverlay(metrics: metrics, showingGame: showingGame)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded(handleKeyboardDismissDrag)
        )
    }

    @ViewBuilder
    private var launchSplashOverlay: some View {
        if isShowingLaunchSplash {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                Image("LaunchSplashSlime")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 180, height: 180)
            }
            .transition(.opacity)
            .zIndex(100)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func levelUpToast(metrics: LayoutMetrics, showingGame: Bool) -> some View {
        if showLevelUpNotification && !showingGame {
            VStack {
                LevelUpToast(level: lastLevelUpValue)
                    .padding(.top, metrics.topPadding + metrics.topButtonSize + 12)
                    .padding(.horizontal, metrics.horizontalPadding)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(20)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func gameScene(showingGame: Bool) -> some View {
        if showingGame {
            FlappyTamagotchiGameView(
                theme: selectedTheme,
                health: health,
                sprite: selectedSprite,
                clothing: selectedClothing,
                birdVisible: !isLaunchingGame,
                onEarnCurrency: earnCurrency,
                onExit: exitGameMode
            )
            .allowsHitTesting(isGameMode)
            .opacity(isLaunchingGame ? gameEntryProgress : 1)
            .scaleEffect(isLaunchingGame ? 0.96 + (gameEntryProgress * 0.04) : 1)
            .zIndex(0)
        }
    }

    private func activeContentStack(metrics: LayoutMetrics, showingGame: Bool) -> some View {
        VStack(spacing: metrics.sectionSpacing) {
            HomeTopBar(
                metrics: metrics,
                isBackVisible: activePage != .home,
                isQuickActionsExpanded: quickActionsExpanded,
                currencyBalance: currentCurrencyBalance,
                currencyTint: selectedSprite.currencyTint,
                onTitleTap: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        quickActionsExpanded.toggle()
                    }
                },
                onBack: goBack,
                onWalkthrough: restartWalkthrough
            )
            .padding(.top, metrics.topPadding)
            .padding(.horizontal, metrics.horizontalPadding)
            .opacity(showingGame ? 0 : 1)
            .offset(y: showingGame ? -80 : 0)
            .allowsHitTesting(!showingGame)

            mainPageContent(metrics: metrics, showingGame: showingGame)
                .offset(y: showingGame ? 120 : 0)
                .opacity(showingGame ? 0 : 1)
                .allowsHitTesting(!showingGame)
        }
    }

    @ViewBuilder
    private func launchingGameOverlay(containerSize: CGSize, metrics: LayoutMetrics) -> some View {
        if activePage == .home && isLaunchingGame {
            LaunchingGameSpriteOverlay(
                containerSize: containerSize,
                metrics: metrics,
                progress: gameEntryProgress,
                health: health,
                sprite: selectedSprite,
                clothing: selectedClothing
            )
            .allowsHitTesting(false)
            .zIndex(2)
        }
    }

    @ViewBuilder
    private func walkthroughOverlay(metrics: LayoutMetrics, showingGame: Bool) -> some View {
        if isWalkthroughPresented && !showingGame {
            WalkthroughOverlay(
                metrics: metrics,
                step: WalkthroughStep.allCases[walkthroughIndex],
                currentIndex: walkthroughIndex,
                totalCount: WalkthroughStep.allCases.count,
                onNext: advanceWalkthrough,
                onSkip: { finishWalkthrough() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(4)
        }
    }

    @ViewBuilder
    private func actionDockOverlay(metrics: LayoutMetrics, showingGame: Bool) -> some View {
        if !showingGame && !isKeyboardVisible {
            ActionDock(
                activePage: $activePage,
                metrics: metrics,
                isTutorialActive: isWalkthroughPresented,
                tutorialTarget: isWalkthroughPresented ? WalkthroughStep.allCases[walkthroughIndex].dockTarget : nil,
                onLogTap: { navigate(to: .log) },
                onSelectPage: handleDockSelection
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .transaction { transaction in
                if isWalkthroughPresented {
                    transaction.animation = nil
                }
            }
            .allowsHitTesting(!isWalkthroughPresented)
        }
    }

    @ViewBuilder
    private func mainPageContent(metrics: LayoutMetrics, showingGame: Bool) -> some View {
        if activePage == .home {
            homeView(metrics: metrics, isShowingGame: showingGame, isLaunchingGame: isLaunchingGame)
        } else {
            detailPage(metrics: metrics, page: activePage)
        }
    }

    @ViewBuilder
    private func homeView(metrics: LayoutMetrics, isShowingGame: Bool, isLaunchingGame: Bool) -> some View {
        GeometryReader { geometry in
            let panelWidth = geometry.size.width
            let safePanelWidth = max(panelWidth, 1)
            let baseOffset = CGFloat(activeHomePanelIndex) * panelWidth
            let currentOffset = min(max(baseOffset - homeDragTranslation, 0), panelWidth * 2)

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    SpriteSelectionGridView(
                        sprites: availableSprites,
                        selectedSprite: selectedSprite,
                        selectedClothing: selectedClothing,
                        selectedDanceSpeed: selectedDanceSpeed,
                        assignedSpriteIDs: assignedSpriteIDs,
                        onSelectSprite: selectSprite,
                        onLockedSpriteTap: promptAssignContactForLockedSprite,
                        spriteLevels: spriteLevels
                    )
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.contentBottomPadding)
                    .frame(width: panelWidth)
                    .frame(minHeight: metrics.minContentHeight)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: metrics.sectionSpacing) {
                            if quickActionsExpanded {
                                QuickActionsFlyout(
                                    onCallNow: handleCallNowQuickAction,
                                    onSetReminder: handleSetReminderQuickAction,
                                    onChooseContact: handleChooseContactQuickAction
                                )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            FloatingHealthBar(
                                health: visibleHealth,
                                isAnimating: healthPulse,
                                isTutorialHighlighted: isWalkthroughPresented && WalkthroughStep.allCases[walkthroughIndex].focus == .healthBar
                            )

                            IntegratedTamagotchiStage(
                                health: health,
                                sprite: selectedSprite,
                                clothing: selectedClothing,
                                danceSpeed: selectedDanceSpeed,
                                currentSpriteLevel: currentSpriteLevel,
                                isGameMode: isShowingGame,
                                hidesSprite: isLaunchingGame,
                                isHibernating: isHibernating,
                                isContactAssigned: selectedSpriteCanBeUsed,
                                currencyBalance: currentCurrencyBalance,
                                currencyTint: selectedSprite.currencyTint,
                                streakTier: streakTier,
                                onBuyFood: buyFood,
                                onLogCall: handleDashboardLogCall
                            )

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.bottom, metrics.contentBottomPadding)
                        .frame(maxWidth: .infinity, minHeight: metrics.minContentHeight)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .frame(width: panelWidth)
                    .frame(minHeight: metrics.minContentHeight)

                    PixelGardenPlaygroundView(
                        sprites: availableSprites.filter(spriteCanBeUsed),
                        selectedClothing: selectedClothing,
                        isHibernating: isHibernating,
                        onLaunchGame: enterGameMode,
                        onDragStateChanged: { isDragging in
                            isGardenDraggingPet = isDragging
                        }
                    )
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.contentBottomPadding)
                    .frame(width: panelWidth)
                    .frame(minHeight: metrics.minContentHeight)
                }
                .offset(x: -currentOffset)

            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isShowingGame else { return }
                        guard !isGardenDraggingPet else { return }
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        if abs(value.translation.width) > 10 {
                            isHomePanelSwipeInProgress = true
                        }
                        homeDragTranslation = value.translation.width
                    }
                    .onEnded { value in
                        guard !isShowingGame else { return }
                        guard !isGardenDraggingPet else {
                            homeDragTranslation = 0
                            isHomePanelSwipeInProgress = false
                            return
                        }
                        if abs(value.translation.width) > 10 {
                            lastHomePanelSwipeEndedAt = Date()
                        }
                        isHomePanelSwipeInProgress = false
                        guard abs(value.translation.width) >= abs(value.translation.height) else {
                            withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.12)) {
                                homeDragTranslation = 0
                            }
                            return
                        }
                        let velocityDelta = value.predictedEndTranslation.width - value.translation.width
                        let projectedDragOffset = baseOffset - value.translation.width - (velocityDelta * 0.2)
                        let maximumPanelOffset = panelWidth * 2
                        let projectedOffset = min(max(projectedDragOffset, 0), maximumPanelOffset)
                        let resolvedPanel = Int((projectedOffset / safePanelWidth).rounded())
                        let clampedPanel = min(max(resolvedPanel, 0), 2)

                        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.12)) {
                            activeHomePanelIndex = clampedPanel
                            homeDragTranslation = 0
                        }
                    }
            )
        }
    }

    private var preferredContact: AppContact? {
        guard let preferredContactID else { return contacts.first }
        return contacts.first(where: { $0.id == preferredContactID }) ?? contacts.first
    }

    private var currentAssignedContactID: UUID? {
        spriteContactAssignments[selectedSprite.id]
    }

    private var currentAssignedContact: AppContact? {
        guard let currentAssignedContactID else { return nil }
        return contacts.first(where: { $0.id == currentAssignedContactID })
    }

    private var assignedSpriteIDs: Set<String> {
        let contactIDs = Set(contacts.map(\.id))
        return Set(spriteContactAssignments.compactMap { spriteID, contactID in
            contactIDs.contains(contactID) ? spriteID : nil
        })
    }

    private var selectedSpriteCanBeUsed: Bool {
        spriteCanBeUsed(selectedSprite)
    }

    private var visibleHealth: Double {
        isHibernating ? 0 : health
    }

    private var currentCurrencyBalance: Int {
        max(currencyBalances[selectedSprite.id] ?? 0, 0)
    }

    private func selectSprite(_ sprite: TamagotchiSpriteProfile) {
        guard spriteCanBeUsed(sprite) else {
            navigate(to: .settings)
            return
        }
        applySelectedSprite(sprite, activateHealth: true)
    }

    private func spriteCanBeUsed(_ sprite: TamagotchiSpriteProfile) -> Bool {
        guard let contactID = spriteContactAssignments[sprite.id] else { return false }
        return contacts.contains(where: { $0.id == contactID })
    }

    private func firstUsableSprite() -> TamagotchiSpriteProfile? {
        availableSprites.first(where: spriteCanBeUsed)
    }

    private func ensureSelectedSpriteCanBeUsed() {
        guard !selectedSpriteCanBeUsed else { return }
        guard let replacement = firstUsableSprite(), replacement.id != selectedSprite.id else { return }
        applySelectedSprite(replacement, activateHealth: false)
    }

    private func applySelectedSprite(_ sprite: TamagotchiSpriteProfile, activateHealth: Bool) {
        if selectedSprite.id != sprite.id, hasRestoredCurrentSpriteHealth {
            persistHealthState()
        }

        if selectedSprite.id != sprite.id {
            selectedSprite = sprite
        }

        AppStatePersistence.saveSelectedSpriteID(sprite.id)
        updateCurrentSpriteLevel()
        restorePersistedHealth(for: sprite.id)
        selectedLogContactID = spriteContactAssignments[sprite.id] ?? preferredContactID ?? contacts.first?.id

        if activateHealth {
            activateCurrentSpriteHealthIfNeeded()
        }
    }

    private func activateCurrentSpriteHealthIfNeeded() {
        guard !currentSpriteHealthIsActivated else { return }
        currentSpriteHealthIsActivated = true
        lastHealthUpdatedAt = Date()
        persistHealthState()
    }

    private func activateDefaultSpriteHealthIfNeeded() {
        let defaultSprite = TamagotchiSpriteCatalog.preferredInitialSprite(from: availableSprites)
        guard selectedSprite.id == defaultSprite.id else { return }
        guard selectedSpriteCanBeUsed else { return }
        activateCurrentSpriteHealthIfNeeded()
    }

    private func handleDashboardLogCall() {
        guard !isSuppressingHomePanelTap else { return }
        guard selectedSpriteCanBeUsed else {
            navigate(to: .settings)
            return
        }
        selectedLogContactID = currentAssignedContactID ?? preferredContactID ?? contacts.first?.id
        navigate(to: .log)
    }

    private func enterHibernationIfNeeded() {
        guard currentSpriteHealthIsActivated else { return }
        guard health <= 0 else { return }
        guard !isHibernating else { return }

        if isGameMode || isLaunchingGame {
            exitGameMode()
        }
        resetCurrentSpriteLevel()
        isHibernating = true
        persistHealthState()
    }

    private func wakeFromHibernationIfNeeded() {
        guard isHibernating, health > 0 else { return }
        isHibernating = false
        persistHealthState()
    }

    private var isSuppressingHomePanelTap: Bool {
        isHomePanelSwipeInProgress ||
        Date().timeIntervalSince(lastHomePanelSwipeEndedAt) < homePanelSwipeTapSuppressionInterval
    }

    private func logCall(contactID: UUID?, name: String, minutes: Int) {
        callsLogged += 1
        HealthPersistence.saveCallsLogged(callsLogged)
        callLogs.insert(CallLogEntry(contactID: contactID, name: name, minutes: minutes, loggedAt: Date()), at: 0)
        refreshStreakDays()

        if let contactID, let spriteID = assignedSpriteID(for: contactID) {
            earnCurrency(callCurrencyReward(for: minutes), for: spriteID)
        }
        selectedLogContactID = currentAssignedContactID ?? preferredContactID
        logMinutes = ""
        clearPendingCallTracking()
    }

    private func callCurrencyReward(for minutes: Int) -> Int {
        min(max(6 + minutes / 2, 8), 40)
    }

    private func earnCurrency(_ amount: Int) {
        guard selectedSpriteCanBeUsed else { return }
        earnCurrency(amount, for: selectedSprite.id)
    }

    private func earnCurrency(_ amount: Int, for spriteID: String) {
        guard amount > 0 else { return }
        let currentBalance = max(currencyBalances[spriteID] ?? 0, 0)
        currencyBalances[spriteID] = currentBalance + amount
    }

    private func buyFood(_ option: FeedingOption) {
        guard selectedSpriteCanBeUsed else {
            navigate(to: .settings)
            return
        }
        let cost = option.cost(streakTier: streakTier)
        guard currentCurrencyBalance >= cost else { return }

        currencyBalances[selectedSprite.id] = currentCurrencyBalance - cost
        activateCurrentSpriteHealthIfNeeded()
        applyElapsedDecay(now: Date())
        health = min(health + option.healthRestored, HealthPersistence.defaultHealth)
        lastHealthUpdatedAt = Date()
        wakeFromHibernationIfNeeded()
        awardExperienceForFeeding(option)
    }

    private func assignedSpriteID(for contactID: UUID) -> String? {
        if spriteContactAssignments[selectedSprite.id] == contactID {
            return selectedSprite.id
        }

        if let matchingSprite = availableSprites.first(where: { spriteContactAssignments[$0.id] == contactID }) {
            return matchingSprite.id
        }

        return spriteContactAssignments
            .filter { $0.value == contactID }
            .map(\.key)
            .sorted()
            .first
    }

    private func applyElapsedDecay(now: Date) {
        guard currentSpriteHealthIsActivated else { return }
        let updatedHealth = HealthPersistence.decayedHealth(from: health, since: lastHealthUpdatedAt, now: now)
        guard updatedHealth != health || lastHealthUpdatedAt != now else { return }
        health = updatedHealth
        lastHealthUpdatedAt = now
        enterHibernationIfNeeded()
    }

    private func restorePersistedHealth() {
        callsLogged = HealthPersistence.loadCallsLogged()
        restorePersistedHealth(for: selectedSprite.id)
        refreshStreakDays()
    }

    private func restorePersistedHealth(for spriteID: String) {
        let now = Date()
        let persisted = HealthPersistence.loadSpriteState(for: spriteID, now: now)
        currentSpriteHealthIsActivated = persisted.isActivated
        isHibernating = persisted.isHibernating
        health = persisted.isActivated
            ? HealthPersistence.decayedHealth(from: persisted.health, since: persisted.updatedAt, now: now)
            : persisted.health
        lastHealthUpdatedAt = persisted.isActivated ? now : persisted.updatedAt
        hasRestoredCurrentSpriteHealth = true
        wasBelowLowHealthThreshold = health <= LocalNotificationManager.lowHealthThreshold
        enterHibernationIfNeeded()
    }

    private func persistHealthState() {
        HealthPersistence.saveSpriteState(
            SpriteHealthState(
                spriteID: selectedSprite.id,
                health: health,
                updatedAt: lastHealthUpdatedAt,
                isActivated: currentSpriteHealthIsActivated,
                isHibernating: isHibernating
            )
        )
    }

    private func syncLowHealthNotification() {
        guard notificationPreferences.lowHealthAlertsEnabled else {
            wasBelowLowHealthThreshold = false
            LocalNotificationManager.shared.clearLowHealthNotification()
            return
        }

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
                        contacts: contacts,
                        selectedContactID: $selectedLogContactID,
                        minutes: $logMinutes,
                        entries: callLogs,
                        onSubmit: submitLogEntry,
                        onSelectRecent: selectRecentLogEntry,
                        onImportContact: { isContactPickerPresented = true },
                        onCallContact: callContact,
                        onOpenSettings: { navigate(to: .settings) }
                    )
                } else if page == .settings {
                    SettingsPageCard(
                        contacts: contacts,
                        preferredContactID: $preferredContactID,
                        spriteContactAssignments: $spriteContactAssignments,
                        sprites: availableSprites,
                        notificationPreferences: $notificationPreferences,
                        onImportContact: { isContactPickerPresented = true },
                        onDeleteContact: deleteContact,
                        onAddReminder: beginAddingReminder,
                        onDeleteReminder: deleteReminder
                    )
                } else {
                    DetailPageCard(
                        page: page,
                        selectedClothing: $selectedClothing,
                        selectedDanceSpeed: $selectedDanceSpeed,
                        streakTier: streakTier,
                        selectedTheme: $selectedTheme,
                        streakDays: $streakDays
                    )
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.bottom, metrics.contentBottomPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minContentHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func submitLogEntry() {
        guard
            let selectedLogContactID,
            let contact = contacts.first(where: { $0.id == selectedLogContactID }),
            let minutes = Int(logMinutes),
            minutes > 0
        else {
            return
        }

        logCall(contactID: contact.id, name: contact.name, minutes: minutes)
    }

    private func selectRecentLogEntry(_ entry: CallLogEntry) {
        if let contactID = entry.contactID, contacts.contains(where: { $0.id == contactID }) {
            selectedLogContactID = contactID
        } else if let matchingContact = contacts.first(where: { contact in
            contact.name.compare(entry.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            selectedLogContactID = matchingContact.id
        }

        logMinutes = String(entry.minutes)
    }

    private func reloadSpriteCatalog() {
        let loadedSprites = TamagotchiSpriteCatalog.load()
        guard !loadedSprites.isEmpty else { return }
        availableSprites = loadedSprites

        if let selectedSpriteID = AppStatePersistence.loadSelectedSpriteID(),
           let persistedSprite = loadedSprites.first(where: { $0.id == selectedSpriteID }) {
            applySelectedSprite(persistedSprite, activateHealth: false)
        } else if let existing = loadedSprites.first(where: { $0.id == selectedSprite.id }) {
            applySelectedSprite(existing, activateHealth: false)
        } else {
            applySelectedSprite(TamagotchiSpriteCatalog.preferredInitialSprite(from: loadedSprites), activateHealth: false)
        }
    }

    private func restoreAppState() {
        callLogs = AppStatePersistence.loadCallLogs()
        restoreSelectedSprite()
    }

    private func migrateLegacyCurrencyIfNeeded() {
        let migratedBalances = EconomyPersistence.migratedBalancesIfNeeded(
            existingBalances: currencyBalances,
            defaultSpriteID: selectedSprite.id
        )

        if migratedBalances != currencyBalances {
            currencyBalances = migratedBalances
        }
    }

    private func persistAppState() {
        AppStatePersistence.saveCallLogs(callLogs)
        AppStatePersistence.saveSelectedSpriteID(selectedSprite.id)
    }

    private func restoreSelectedSprite() {
        guard let selectedSpriteID = AppStatePersistence.loadSelectedSpriteID() else { return }
        guard let persistedSprite = availableSprites.first(where: { $0.id == selectedSpriteID }) else { return }
        applySelectedSprite(persistedSprite, activateHealth: false)
    }

    private func refreshStreakDays() {
        streakDays = StreakCalculator.currentStreak(from: callLogs)
    }

    private func restoreSettings() {
        let settings = SettingsPersistence.load()
        contacts = settings.contacts
        preferredContactID = settings.preferredContactID
        spriteContactAssignments = settings.spriteContactAssignments
        defaultCallMinutes = settings.defaultCallMinutes
        notificationPreferences = settings.notificationPreferences
        selectedLogContactID = spriteContactAssignments[selectedSprite.id] ?? settings.preferredContactID ?? settings.contacts.first?.id

        logMinutes = logMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func presentDefaultContactPromptIfNeeded(for page: HomePage) {
        guard page == .settings else { return }
        guard contacts.isEmpty, preferredContactID == nil else { return }
        guard !SettingsPersistence.hasPromptedForDefaultContact else { return }
        guard !isDefaultContactPromptPresented else { return }

        SettingsPersistence.markPromptedForDefaultContact()
        isDefaultContactPromptPresented = true
    }

    private func persistSettings() {
        SettingsPersistence.save(
            AppSettings(
                contacts: contacts,
                preferredContactID: preferredContactID,
                spriteContactAssignments: spriteContactAssignments,
                defaultCallMinutes: defaultCallMinutes,
                notificationPreferences: notificationPreferences
            )
        )
    }

    private func importSystemContact(_ contact: CNContact) {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? [contact.givenName, contact.familyName].joined(separator: " ")
        let phoneNumber = contact.phoneNumbers.first?.value.stringValue
        upsertContact(name: name, phoneNumber: phoneNumber)
    }

    private func upsertContact(name: String, phoneNumber: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let alreadyExists = contacts.contains { existing in
            existing.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !alreadyExists else {
            if let phoneNumber,
               let index = contacts.firstIndex(where: { existing in
                   existing.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
               }) {
                contacts[index].phoneNumber = phoneNumber
                selectedLogContactID = contacts[index].id
            }
            return
        }

        let newContact = AppContact(name: trimmedName, phoneNumber: phoneNumber)
        contacts.append(newContact)
        preferredContactID = preferredContactID ?? newContact.id
        selectedLogContactID = selectedLogContactID ?? newContact.id
    }

    private func callContact(_ contact: AppContact) {
        guard
            let phoneNumber = contact.phoneNumber,
            !phoneNumber.digitsOnly.isEmpty,
            let url = URL(string: "tel://\(phoneNumber.digitsOnly)")
        else {
            callFailureMessage = "Add a valid phone number for \(contact.name) before trying to call."
            return
        }

        pendingCallSession = PendingCallSession(
            contactID: contact.id,
            contactName: contact.name,
            startedAt: Date(),
            fallbackMinutes: 0
        )
        persistPendingCallTracking()
        selectedLogContactID = contact.id
        logMinutes = ""
        openURL(url) { accepted in
            guard !accepted else { return }
            clearPendingCallTracking()
            callFailureMessage = "This device or simulator can't place phone calls from the app. Try again on an iPhone with calling available."
        }

        discardUnconfirmedPendingCallAfterDelay(sessionID: pendingCallSession?.id)
    }

    private func handleCallNowQuickAction() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            quickActionsExpanded = false
        }

        guard let preferredContact else {
            navigate(to: .settings)
            return
        }

        selectedLogContactID = preferredContact.id
        logMinutes = ""

        guard let phoneNumber = preferredContact.phoneNumber, !phoneNumber.digitsOnly.isEmpty else {
            callFailureMessage = "Your default contact needs a phone number before Call now can start a call."
            navigate(to: .settings)
            return
        }

        callContact(preferredContact)
    }

    private func handleCallActivity(_ event: CallActivityEvent?) {
        guard let event, var session = pendingCallSession else { return }

        switch event.kind {
        case .outgoing:
            guard !session.didObserveOutgoingCall else { return }
            session.didObserveOutgoingCall = true
            session.callStartedAt = event.occurredAt
            pendingCallSession = session
            persistPendingCallTracking()
            LocalNotificationManager.shared.schedulePostCallLogReminder(
                contactName: session.contactName,
                after: 300
            )
        case .connected:
            session.didObserveOutgoingCall = true
            session.callStartedAt = event.occurredAt
            pendingCallSession = session
            persistPendingCallTracking()
        case .ended:
            guard session.didObserveOutgoingCall else {
                clearPendingCallTracking()
                return
            }
            session.callEndedAt = event.occurredAt
            session = session.withFrozenPromptMinutes(loggableMinutes(for: session))
            pendingCallSession = session
            persistPendingCallTracking()
            if scenePhase == .active {
                presentPostCallPromptIfReady()
            }
        }
    }

    private func handleSetReminderQuickAction() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            quickActionsExpanded = false
        }

        beginAddingReminder()
    }

    private func applyReminderDraft() {
        guard let reminder = reminderDraft.makeReminder() else { return }
        notificationPreferences.callReminders.append(reminder)
        isReminderPickerPresented = false
    }

    private func beginAddingReminder() {
        guard !contacts.isEmpty else {
            navigate(to: .settings)
            return
        }

        reminderDraft = CallReminderDraft(contactID: preferredContactID ?? contacts.first?.id)
        isReminderPickerPresented = true
    }

    private func deleteReminder(_ reminder: CallReminder) {
        notificationPreferences.callReminders.removeAll { $0.id == reminder.id }
    }

    private func handleChooseContactQuickAction() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            quickActionsExpanded = false
        }

        guard !contacts.isEmpty else {
            navigate(to: .settings)
            return
        }

        selectedDefaultContactDraftID = preferredContactID ?? contacts.first?.id
        isDefaultContactPickerPresented = true
    }

    private func applyDefaultContactDraft() {
        preferredContactID = selectedDefaultContactDraftID ?? contacts.first?.id
        selectedLogContactID = preferredContactID
        isDefaultContactPickerPresented = false
    }

    private func applySpriteContactAssignmentDraft() {
        guard
            let spriteID = pendingSpriteAssignmentSpriteID,
            let contactID = selectedSpriteAssignmentContactID
        else {
            isSpriteContactAssignmentPresented = false
            return
        }

        spriteContactAssignments[spriteID] = contactID
        if let sprite = availableSprites.first(where: { $0.id == spriteID }) {
            selectSprite(sprite)
        }

        isSpriteContactAssignmentPresented = false
        pendingSpriteAssignmentSpriteID = nil
    }

    private func presentPostCallPromptIfReady() {
        guard let session = pendingCallSession else { return }

        if session.isStale(maxAge: stalePendingCallInterval) {
            clearPendingCallTracking()
            return
        }

        guard session.didLeaveApp else {
            discardUnconfirmedPendingCallIfNeeded()
            return
        }

        guard session.didObserveOutgoingCall else {
            discardUnconfirmedPendingCallIfNeeded()
            return
        }

        guard session.callEndedAt != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard scenePhase == .active else { return }
                presentPostCallPromptIfReady()
            }
            return
        }

        let secondsSinceCallStarted = Date().timeIntervalSince(session.startedAt)
        guard secondsSinceCallStarted >= minimumCallPromptDelay else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (minimumCallPromptDelay - secondsSinceCallStarted)) {
                guard scenePhase == .active else { return }
                presentPostCallPromptIfReady()
            }
            return
        }

        guard !isGameMode, !isLaunchingGame else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard scenePhase == .active else { return }
                presentPostCallPromptIfReady()
            }
            return
        }

        let promptSession = session.withFrozenPromptMinutes(loggableMinutes(for: session))
        pendingCallSession = promptSession
        persistPendingCallTracking()
        selectedLogContactID = session.contactID
        logMinutes = String(loggableMinutes(for: promptSession))
        postCallPrompt = promptSession
    }

    private func savePendingCall(_ session: PendingCallSession) {
        logCall(contactID: session.contactID, name: session.contactName, minutes: loggableMinutes(for: session))
    }

    private func reviewPendingCall(_ session: PendingCallSession) {
        selectedLogContactID = session.contactID
        logMinutes = String(loggableMinutes(for: session))
        postCallPrompt = nil
        navigate(to: .log)
    }

    private func loggableMinutes(for session: PendingCallSession) -> Int {
        if let promptMinutes = session.promptMinutes {
            return max(1, promptMinutes)
        }

        return estimatedMinutes(for: session)
    }

    private func estimatedMinutes(for session: PendingCallSession) -> Int {
        let endDate = session.callEndedAt ?? Date()
        let elapsedMinutes = Int(ceil(endDate.timeIntervalSince(session.callStartedAt ?? session.startedAt) / 60))
        return max(1, elapsedMinutes == 0 ? session.fallbackMinutes : elapsedMinutes)
    }

    private func deferPendingCallPrompt() {
        postCallPrompt = nil
        persistPendingCallTracking()
    }

    private func markPendingCallDidLeaveApp() {
        guard var session = pendingCallSession, !session.didLeaveApp else { return }
        session.didLeaveApp = true
        pendingCallSession = session
        persistPendingCallTracking()
    }

    private func discardUnconfirmedPendingCallAfterDelay(sessionID: UUID?) {
        guard let sessionID else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + minimumCallPromptDelay) {
            guard scenePhase == .active else { return }
            guard pendingCallSession?.id == sessionID else { return }
            discardUnconfirmedPendingCallIfNeeded()
        }
    }

    private func discardUnconfirmedPendingCallIfNeeded() {
        guard let session = pendingCallSession else { return }
        guard !session.didObserveOutgoingCall else { return }
        guard Date().timeIntervalSince(session.startedAt) >= minimumCallPromptDelay else { return }
        clearPendingCallTracking()
    }

    private func clearPendingCallTracking() {
        pendingCallSession = nil
        postCallPrompt = nil
        PendingCallPersistence.clear()
        LocalNotificationManager.shared.clearPostCallLogReminder()
    }

    private func restorePendingCallTracking() {
        guard pendingCallSession == nil else { return }
        guard let restoredSession = PendingCallPersistence.load() else { return }

        if restoredSession.isStale(maxAge: stalePendingCallInterval) {
            PendingCallPersistence.clear()
        } else {
            pendingCallSession = restoredSession
        }
    }

    private func persistPendingCallTracking() {
        guard let pendingCallSession else {
            PendingCallPersistence.clear()
            return
        }

        PendingCallPersistence.save(pendingCallSession)
    }

    private func deleteContact(_ contact: AppContact) {
        contacts.removeAll { $0.id == contact.id }
    }

    private func sanitizeContactsAfterMutation() {
        if contacts.isEmpty {
            preferredContactID = nil
            selectedLogContactID = nil
            return
        }

        if !contacts.contains(where: { $0.id == preferredContactID }) {
            preferredContactID = contacts.first?.id
        }

        if !contacts.contains(where: { $0.id == selectedLogContactID }) {
            selectedLogContactID = preferredContactID ?? contacts.first?.id
        }

        let contactIDs = Set(contacts.map(\.id))
        let sanitizedReminders = notificationPreferences.callReminders.filter { contactIDs.contains($0.contactID) }
        if sanitizedReminders != notificationPreferences.callReminders {
            notificationPreferences.callReminders = sanitizedReminders
        }

        sanitizeSpriteContactAssignments()
    }

    private func sanitizeSpriteContactAssignments() {
        let contactIDs = Set(contacts.map(\.id))
        let sanitizedAssignments = spriteContactAssignments.filter { contactIDs.contains($0.value) }
        if sanitizedAssignments != spriteContactAssignments {
            spriteContactAssignments = sanitizedAssignments
        }
    }

    private func syncNotificationSchedules() {
        LocalNotificationManager.shared.scheduleCallReminders(
            notificationPreferences.callReminders,
            contacts: contacts
        )

        syncLowHealthNotification()
    }

    private func weeklySummary(calendar: Calendar = .current) -> (callCount: Int, totalMinutes: Int, subtitle: String) {
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()) else {
            return (0, 0, "No calls logged this week yet.")
        }

        let recentLogs = callLogs.filter { $0.loggedAt >= weekAgo }
        let totalMinutes = recentLogs.reduce(0) { $0 + $1.minutes }
        let names = Array(Set(recentLogs.map(\.name))).sorted()
        let subtitle: String

        if recentLogs.isEmpty {
            subtitle = "No calls logged this week yet."
        } else {
            let joinedNames = names.prefix(3).joined(separator: ", ")
            subtitle = "Recent contacts: \(joinedNames)."
        }

        return (recentLogs.count, totalMinutes, subtitle)
    }

    private func navigate(to page: HomePage) {
        if isGameMode {
            exitGameMode()
        }
        guard page != activePage else { return }
        pageHistory.append(activePage)
        activePage = page
    }

    private func handleDockSelection(_ page: HomePage) {
        if page == .home {
            resetHomeScreen()
        } else {
            navigate(to: page)
        }
    }

    private func resetHomeScreen() {
        if isGameMode || isLaunchingGame {
            exitGameMode()
        }

        pageHistory.removeAll()
        quickActionsExpanded = false
        isHomePanelSwipeInProgress = false
        homeDragTranslation = 0

        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.12)) {
            activePage = .home
            activeHomePanelIndex = 1
        }
    }

    private func startWalkthroughIfNeeded() {
        guard !WalkthroughPersistence.hasCompleted else { return }
        guard !isWalkthroughPresented else { return }

        walkthroughIndex = 0
        showWalkthroughStep(at: walkthroughIndex)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isWalkthroughPresented = true
        }
    }

    private func restartWalkthrough() {
        guard !isWalkthroughPresented else { return }

        walkthroughIndex = 0
        showWalkthroughStep(at: walkthroughIndex)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isWalkthroughPresented = true
        }
    }

    private func advanceWalkthrough() {
        let nextIndex = walkthroughIndex + 1
        guard nextIndex < WalkthroughStep.allCases.count else {
            finishWalkthrough(shouldRevealQuickActions: !WalkthroughPersistence.hasCompleted)
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            walkthroughIndex = nextIndex
            showWalkthroughStep(at: nextIndex)
        }
    }

    private func finishWalkthrough(shouldRevealQuickActions: Bool = false) {
        WalkthroughPersistence.markCompleted()
        withAnimation(.easeInOut(duration: 0.2)) {
            isWalkthroughPresented = false
        }

        guard shouldRevealQuickActions else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard !isWalkthroughPresented, activePage == .home, !isGameMode, !isLaunchingGame else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                quickActionsExpanded = true
            }
        }
    }

    private func showWalkthroughStep(at index: Int) {
        guard WalkthroughStep.allCases.indices.contains(index) else { return }
        pageHistory.removeAll()
        activePage = .home
        activeHomePanelIndex = 1
    }

    private func goBack() {
        if isGameMode {
            exitGameMode()
            return
        }
        guard activePage != .home else { return }

        if let previousPage = pageHistory.popLast() {
            activePage = previousPage
        } else {
            activePage = .home
        }
    }

    private func enterGameMode() {
        guard activePage == .home, !isGameMode, !isLaunchingGame else { return }
        guard selectedSpriteCanBeUsed else {
            callFailureMessage = "Assign this Tamagotchi to a contact in Settings before playing."
            navigate(to: .settings)
            return
        }
        guard !isHibernating else {
            callFailureMessage = "Your Tamagotchi is hibernating. Feed it from the shop to wake it up before playing."
            return
        }
        quickActionsExpanded = false
        gameEntryProgress = 0

        withAnimation(.spring(response: 0.46, dampingFraction: 0.90)) {
            isGameMode = true
            isLaunchingGame = false
            gameEntryProgress = 1
        }
    }

    private func exitGameMode() {
        guard isGameMode || isLaunchingGame else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
            isGameMode = false
            isLaunchingGame = false
            gameEntryProgress = 0
        }
    }
}

private struct SystemContactPicker: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey
        ]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void

        init(onSelect: @escaping (CNContact) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
    }
}

private struct PendingCallSession: Codable, Identifiable {
    let id: UUID
    let contactID: UUID
    let contactName: String
    let startedAt: Date
    let fallbackMinutes: Int
    var didLeaveApp: Bool
    var didObserveOutgoingCall: Bool
    var callStartedAt: Date?
    var callEndedAt: Date?
    var promptMinutes: Int?

    init(
        id: UUID = UUID(),
        contactID: UUID,
        contactName: String,
        startedAt: Date,
        fallbackMinutes: Int,
        didLeaveApp: Bool = false,
        didObserveOutgoingCall: Bool = false,
        callStartedAt: Date? = nil,
        callEndedAt: Date? = nil,
        promptMinutes: Int? = nil
    ) {
        self.id = id
        self.contactID = contactID
        self.contactName = contactName
        self.startedAt = startedAt
        self.fallbackMinutes = fallbackMinutes
        self.didLeaveApp = didLeaveApp
        self.didObserveOutgoingCall = didObserveOutgoingCall
        self.callStartedAt = callStartedAt
        self.callEndedAt = callEndedAt
        self.promptMinutes = promptMinutes
    }

    func isStale(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) > maxAge
    }

    func withFrozenPromptMinutes(_ minutes: Int) -> PendingCallSession {
        var session = self
        session.promptMinutes = promptMinutes ?? max(1, minutes)
        return session
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contactID
        case contactName
        case startedAt
        case fallbackMinutes
        case didLeaveApp
        case didObserveOutgoingCall
        case callStartedAt
        case callEndedAt
        case promptMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        contactID = try container.decode(UUID.self, forKey: .contactID)
        contactName = try container.decode(String.self, forKey: .contactName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        fallbackMinutes = try container.decode(Int.self, forKey: .fallbackMinutes)
        didLeaveApp = try container.decodeIfPresent(Bool.self, forKey: .didLeaveApp) ?? false
        didObserveOutgoingCall = try container.decodeIfPresent(Bool.self, forKey: .didObserveOutgoingCall) ?? false
        callStartedAt = try container.decodeIfPresent(Date.self, forKey: .callStartedAt)
        callEndedAt = try container.decodeIfPresent(Date.self, forKey: .callEndedAt)
        promptMinutes = try container.decodeIfPresent(Int.self, forKey: .promptMinutes)
    }
}

private struct CallReminderDraft {
    var contactID: UUID?
    var frequency: CallReminderFrequency = .daily
    var time: Date = Date()
    var weekday: Int = Calendar.current.component(.weekday, from: Date())

    func makeReminder(calendar: Calendar = .current) -> CallReminder? {
        guard let contactID else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return CallReminder(
            contactID: contactID,
            frequency: frequency,
            hour: components.hour ?? 20,
            minute: components.minute ?? 0,
            weekday: weekday,
            isEnabled: true
        )
    }
}

private struct CallActivityEvent: Equatable {
    enum Kind: Equatable {
        case outgoing
        case connected
        case ended
    }

    let id = UUID()
    let kind: Kind
    let occurredAt: Date
}

private final class CallActivityObserver: NSObject, ObservableObject, CXCallObserverDelegate {
    @Published private(set) var latestEvent: CallActivityEvent?

    private let observer = CXCallObserver()
    private var observedOutgoingCallIDs: Set<UUID> = []

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard call.isOutgoing else { return }

        let now = Date()
        if call.hasEnded {
            observedOutgoingCallIDs.remove(call.uuid)
            latestEvent = CallActivityEvent(kind: .ended, occurredAt: now)
        } else if call.hasConnected {
            observedOutgoingCallIDs.insert(call.uuid)
            latestEvent = CallActivityEvent(kind: .connected, occurredAt: now)
        } else if !observedOutgoingCallIDs.contains(call.uuid) {
            observedOutgoingCallIDs.insert(call.uuid)
            latestEvent = CallActivityEvent(kind: .outgoing, occurredAt: now)
        }
    }
}

private enum PendingCallPersistence {
    private static let storageKey = "pendingCall.session"

    static func load() -> PendingCallSession? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let session = try? JSONDecoder().decode(PendingCallSession.self, from: data)
        else {
            return nil
        }

        return session
    }

    static func save(_ session: PendingCallSession) {
        guard let encoded = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

private enum WalkthroughPersistence {
    private static let storageKey = "walkthrough.hasCompleted"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: storageKey)
    }
}

private enum SpriteIDMigration {
    private static let legacyToCanonical = [
        "t1": "slime",
        "t2": "cecil"
    ]

    static func canonical(_ id: String) -> String {
        legacyToCanonical[id] ?? id
    }

    static func migratedValues<Value>(_ values: [String: Value]) -> [String: Value] {
        var migrated = values
        for (legacyID, canonicalID) in legacyToCanonical {
            if let legacyValue = values[legacyID], values[canonicalID] == nil {
                migrated[canonicalID] = legacyValue
            }
            migrated.removeValue(forKey: legacyID)
        }
        return migrated
    }

    static func migratedLevels(_ levels: [String: SpriteLevel]) -> [String: SpriteLevel] {
        var migrated: [String: SpriteLevel] = [:]
        for (id, level) in levels {
            let canonicalID = canonical(id)
            let normalizedLevel = SpriteLevel(
                spriteID: canonicalID,
                level: level.level,
                experienceInLevel: level.experienceInLevel
            )

            if migrated[canonicalID] == nil || canonicalID == id {
                migrated[canonicalID] = normalizedLevel
            }
        }
        return migrated
    }
}

private enum AppStatePersistence {
    private static let callLogsKey = "appState.callLogs"
    private static let selectedSpriteIDKey = "appState.selectedSpriteID"

    static func loadCallLogs() -> [CallLogEntry] {
        guard
            let data = UserDefaults.standard.data(forKey: callLogsKey),
            let logs = try? JSONDecoder().decode([CallLogEntry].self, from: data)
        else {
            return []
        }

        return logs.sorted { $0.loggedAt > $1.loggedAt }
    }

    static func saveCallLogs(_ logs: [CallLogEntry]) {
        guard let encoded = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(encoded, forKey: callLogsKey)
    }

    static func loadSelectedSpriteID() -> String? {
        guard let spriteID = UserDefaults.standard.string(forKey: selectedSpriteIDKey) else { return nil }
        let canonicalSpriteID = SpriteIDMigration.canonical(spriteID)
        if canonicalSpriteID != spriteID {
            saveSelectedSpriteID(canonicalSpriteID)
        }
        return canonicalSpriteID
    }

    static func saveSelectedSpriteID(_ id: String) {
        UserDefaults.standard.set(SpriteIDMigration.canonical(id), forKey: selectedSpriteIDKey)
        UserDefaults.standard.synchronize()
    }
}

private enum EconomyPersistence {
    private static let legacyBalanceKey = "economy.currencyBalance"
    private static let balancesKey = "economy.currencyBalancesBySprite"

    static func loadBalances() -> [String: Int] {
        guard
            let data = UserDefaults.standard.data(forKey: balancesKey),
            let balances = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }

        let sanitizedBalances = balances.mapValues { max($0, 0) }
        let migratedBalances = SpriteIDMigration.migratedValues(sanitizedBalances)
        if migratedBalances != sanitizedBalances {
            saveBalances(migratedBalances)
        }
        return migratedBalances
    }

    static func saveBalances(_ balances: [String: Int]) {
        let sanitizedBalances = SpriteIDMigration.migratedValues(balances).mapValues { max($0, 0) }
        guard let encoded = try? JSONEncoder().encode(sanitizedBalances) else { return }
        UserDefaults.standard.set(encoded, forKey: balancesKey)
    }

    static func migratedBalancesIfNeeded(existingBalances: [String: Int], defaultSpriteID: String) -> [String: Int] {
        guard existingBalances.isEmpty else { return existingBalances }
        let legacyBalance = max(UserDefaults.standard.object(forKey: legacyBalanceKey) as? Int ?? 0, 0)
        guard legacyBalance > 0 else { return existingBalances }

        UserDefaults.standard.removeObject(forKey: legacyBalanceKey)
        return [SpriteIDMigration.canonical(defaultSpriteID): legacyBalance]
    }
}

private enum WalkthroughStep: CaseIterable, Identifiable {
    case welcome
    case health
    case logCall
    case contacts
    case upgrades
    case garden

    var id: Self { self }

    var dockTarget: HomePage? {
        switch self {
        case .welcome, .health, .garden:
            return nil
        case .logCall:
            return .log
        case .contacts:
            return .settings
        case .upgrades:
            return .upgrades
        }
    }

    var symbol: String {
        switch self {
        case .welcome:
            return "heart.fill"
        case .health:
            return "waveform.path.ecg"
        case .logCall:
            return "phone.badge.plus.fill"
        case .contacts:
            return "person.crop.circle.badge.plus"
        case .upgrades:
            return "sparkles"
        case .garden:
            return "arrow.left.and.right"
        }
    }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Call Your Mom"
        case .health:
            return "Keep Health High"
        case .logCall:
            return "Log Calls Conveniently"
        case .contacts:
            return "Add Your People"
        case .upgrades:
            return "Customize and Streak"
        case .garden:
            return "Swipe Through Your Garden"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Each Tamagotchi must be assigned to a contact before you can select or use it. Calls with that person earn coins for their paired Tamagotchi."
        case .health:
            return "This health bar belongs to the selected Tamagotchi. Calls earn coins, and food from the shop restores health and gives level progress."
        case .logCall:
            return "Use the Log tab to save calls and earn coins. Spend coins on food to heal and level up your Tamagotchi."
        case .contacts:
            return "Settings lets you import contacts, choose defaults, and assign each Tamagotchi to the person it should represent. Locked Tamagotchis unlock as soon as they have an assigned contact."
        case .upgrades:
            return "Upgrades change style and show your streak tier. Streaks rise only when calls are logged on consecutive days."
        case .garden:
            return "On Home, swipe right to select your current sprite or swipe left to view all of your sprites hanging out in the garden."
        }
    }

    var dimOpacity: Double {
        focus == .healthBar ? 0.12 : 0.34
    }

    var focus: WalkthroughFocus {
        switch self {
        case .welcome, .garden:
            return .center
        case .health:
            return .healthBar
        case .logCall, .contacts, .upgrades:
            return .dock
        }
    }
}

private enum WalkthroughFocus {
    case center
    case healthBar
    case dock
}

private struct WalkthroughOverlay: View {
    let metrics: LayoutMetrics
    let step: WalkthroughStep
    let currentIndex: Int
    let totalCount: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    private let tutorialCardYOffset: CGFloat = 22

    private var dockPointerBottomPadding: CGFloat {
        72 + metrics.dockOuterBottomPadding + metrics.dockInnerBottomPadding + metrics.dockSelectedSize
    }

    private var isLastStep: Bool {
        currentIndex == totalCount - 1
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(step.dimOpacity)
                    .ignoresSafeArea()

                switch step.focus {
                case .center:
                    card
                        .padding(.horizontal, 22)
                        .position(
                            x: geometry.size.width / 2,
                            y: (geometry.size.height / 2) + tutorialCardYOffset
                        )

                case .healthBar:
                    VStack(spacing: 10) {
                        Spacer()
                            .frame(height: metrics.topPadding + metrics.topButtonSize + metrics.sectionSpacing + 20)

                        healthPointer
                            .padding(.horizontal, 22)

                        card
                            .padding(.horizontal, 22)

                        Spacer()
                    }
                    .offset(y: tutorialCardYOffset)

                case .dock:
                    VStack(spacing: 8) {
                        Spacer()

                        card
                            .padding(.horizontal, 22)

                        dockPointer
                            .padding(.horizontal, 22)
                            .padding(.bottom, dockPointerBottomPadding)
                    }
                    .offset(y: tutorialCardYOffset)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var healthPointer: some View {
        GeometryReader { geometry in
            Triangle()
                .fill(DetailCardPalette.cardFill)
                .frame(width: 26, height: 18)
                .shadow(color: Color.black.opacity(0.16), radius: 6, y: 4)
                .position(x: geometry.size.width / 2, y: 9)
        }
        .frame(height: 18)
    }

    private var dockPointer: some View {
        GeometryReader { geometry in
            let targetCenter = pointerCenterX(in: geometry.size.width)

            Triangle()
                .fill(DetailCardPalette.cardFill)
                .frame(width: 26, height: 18)
                .rotationEffect(.degrees(180))
                .shadow(color: Color.black.opacity(0.16), radius: 6, y: 4)
                .position(x: targetCenter, y: 9)
        }
        .frame(height: 18)
    }

    private func pointerCenterX(in width: CGFloat) -> CGFloat {
        guard
            let dockTarget = step.dockTarget,
            let targetIndex = HomePage.dockCases.firstIndex(of: dockTarget)
        else {
            return width / 2
        }

        let segmentWidth = width / CGFloat(HomePage.dockCases.count)
        return segmentWidth * (CGFloat(targetIndex) + 0.5)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: step.symbol)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(Color(red: 0.11, green: 0.64, blue: 0.57))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Step \(currentIndex + 1) of \(totalCount)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(DetailCardPalette.mutedText)

                    Text(step.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(DetailCardPalette.primaryText)
                }
            }

            Text(step.message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DetailCardPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(0..<totalCount, id: \.self) { index in
                    Capsule()
                        .fill(index == currentIndex ? Color(red: 0.11, green: 0.64, blue: 0.57) : Color(red: 0.74, green: 0.80, blue: 0.82))
                        .frame(width: index == currentIndex ? 24 : 8, height: 8)
                }
            }

            HStack(spacing: 12) {
                Button(action: ButtonClickSound.action(onSkip)) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(DetailCardPalette.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                Button(action: ButtonClickSound.action(onNext)) {
                    Text(isLastStep ? "Start" : "Next")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(red: 0.12, green: 0.76, blue: 0.60))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(DetailCardPalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(DetailCardPalette.cardStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 24, y: 14)
    }
}

private extension String {
    var digitsOnly: String {
        filter(\.isNumber)
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
    let backgroundSceneLift: CGFloat
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
        backgroundSceneLift = tinyHeight ? 136 : 150
        cardCornerRadius = tinyHeight ? 24 : 30
        minContentHeight = container.height - safeArea.top
    }
}

private struct AppSkyBackground: View {
    let theme: AppTheme

    var body: some View {
        LinearGradient(
            colors: [theme.primary, theme.secondary, theme.tertiary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .scaleEffect(x: 1.04, y: 1.16, anchor: .top)
        .offset(y: -120)
        .ignoresSafeArea()
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
    let currencyBalance: Int
    let currencyTint: Color
    let onTitleTap: () -> Void
    let onBack: () -> Void
    let onWalkthrough: () -> Void

    var body: some View {
        HStack {
            if isBackVisible {
                CircularIconButton(systemName: "arrow.left", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: false, action: onBack)
            } else {
                CircularIconButton(systemName: "info.circle.fill", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: false, action: onWalkthrough)
            }

            Spacer()

            Button(action: ButtonClickSound.action(onTitleTap)) {
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

            TopCurrencyIndicator(balance: currencyBalance, tint: currencyTint)
                .frame(minWidth: metrics.topButtonSize, minHeight: metrics.topButtonSize)
        }
    }
}

private struct TopCurrencyIndicator: View {
    let balance: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(tint)

            Text("\(balance)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.46), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
        .accessibilityLabel("\(balance) coins")
    }
}

private struct LevelUpToast: View {
    let level: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color(red: 1.00, green: 0.80, blue: 0.26))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(red: 0.13, green: 0.20, blue: 0.34))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Level Up!")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

                Text("Your Tamagotchi reached LV \(level).")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.28, green: 0.36, blue: 0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
        )
    }
}

private struct FloatingHealthBar: View {
    let health: Double
    let isAnimating: Bool
    var isTutorialHighlighted = false

    private var clampedHealth: Double {
        min(max(health, 0), 100)
    }

    private var healthGradient: [Color] {
        switch clampedHealth {
        case 70...:
            return [
                Color(red: 0.32, green: 0.88, blue: 0.58),
                Color(red: 0.08, green: 0.66, blue: 0.48)
            ]
        case 40..<70:
            return [
                Color(red: 1.00, green: 0.82, blue: 0.28),
                Color(red: 0.92, green: 0.56, blue: 0.14)
            ]
        case 20..<40:
            return [
                Color(red: 1.00, green: 0.56, blue: 0.28),
                Color(red: 0.93, green: 0.30, blue: 0.18)
            ]
        default:
            return [
                Color(red: 0.98, green: 0.28, blue: 0.34),
                Color(red: 0.86, green: 0.10, blue: 0.18)
            ]
        }
    }

    private var glowColor: Color {
        healthGradient.last ?? Color.red
    }

    private func fillWidth(in totalWidth: CGFloat) -> CGFloat {
        guard clampedHealth > 0 else { return 0 }
        return max(28, totalWidth * (clampedHealth / 100))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.40))
                    .frame(height: 14)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: healthGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: fillWidth(in: geometry.size.width),
                        height: 14
                    )
                    .overlay {
                        if isTutorialHighlighted {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                                .blendMode(.plusLighter)
                        }
                    }
                    .scaleEffect(x: 1, y: isAnimating ? 1.03 : 0.97, anchor: .center)
                    .shadow(
                        color: isTutorialHighlighted ? glowColor.opacity(0.24) : .clear,
                        radius: isTutorialHighlighted ? (isAnimating ? 8 : 4) : 0
                    )
                    .animation(.easeInOut(duration: 0.8), value: isAnimating)
                    .animation(.easeInOut(duration: 0.45), value: health)
            }
            .frame(width: geometry.size.width, height: 14)
            .background {
                if isTutorialHighlighted {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(
                            width: geometry.size.width + 12,
                            height: 30
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.92), lineWidth: 3)
                        )
                        .shadow(color: Color.white.opacity(0.45), radius: 10)
                }
            }
            .frame(width: geometry.size.width, height: 30, alignment: .center)
        }
        .frame(height: isTutorialHighlighted ? 30 : 14)
        .padding(.horizontal, 2)
        .animation(.easeInOut(duration: 0.2), value: isTutorialHighlighted)
    }
}

private struct QuickActionsFlyout: View {
    let onCallNow: () -> Void
    let onSetReminder: () -> Void
    let onChooseContact: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ExpandableActionRow(
                icon: "phone.fill",
                title: "Call now",
                subtitle: "Jump straight into a check-in.",
                action: onCallNow
            )
            ExpandableActionRow(
                icon: "bell.fill",
                title: "Set reminder",
                subtitle: "Pick a time for your next call.",
                action: onSetReminder
            )
            ExpandableActionRow(
                icon: "person.crop.circle.badge.plus",
                title: "Choose contact",
                subtitle: "Change who today's reminder is for.",
                action: onChooseContact
            )
        }
    }
}

private struct ReminderEditorSheet: View {
    let contacts: [AppContact]
    @Binding var draft: CallReminderDraft
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose who to call, how often to be reminded, and what time the reminder should arrive.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.secondaryText)

                Picker("Contact", selection: $draft.contactID) {
                    ForEach(contacts) { contact in
                        Text(contact.name).tag(contact.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .tint(DetailCardPalette.bodyText)

                Picker("Repeat", selection: $draft.frequency) {
                    ForEach(CallReminderFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)

                if draft.frequency == .weekly {
                    Picker("Day", selection: $draft.weekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DetailCardPalette.bodyText)
                }

                DatePicker(
                    "Reminder time",
                    selection: $draft.time,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ButtonClickSound.perform {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ButtonClickSound.perform {
                            onSave()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(draft.contactID == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[min(max(weekday, 1), 7) - 1]
    }
}

private struct DefaultContactPickerSheet: View {
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose who the app should treat as your default contact.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.secondaryText)

                Picker("Default contact", selection: $selectedContactID) {
                    ForEach(contacts) { contact in
                        Text(contact.name).tag(contact.id as UUID?)
                    }
                }
                .pickerStyle(.wheel)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Choose Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ButtonClickSound.perform {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ButtonClickSound.perform {
                            onSave()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct SpriteContactAssignmentSheet: View {
    let spriteName: String
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Assign a contact to unlock \(spriteName).")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.secondaryText)

                Picker("Assign contact", selection: $selectedContactID) {
                    ForEach(contacts) { contact in
                        Text(contact.name).tag(contact.id as UUID?)
                    }
                }
                .pickerStyle(.wheel)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Assign Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ButtonClickSound.perform {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ButtonClickSound.perform {
                            onSave()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(selectedContactID == nil)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct ExpandableActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    init(icon: String, title: String, subtitle: String, action: @escaping () -> Void = {}) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: ButtonClickSound.action(action)) {
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
    let sprite: TamagotchiSpriteProfile
    let clothing: ClothingOption
    let danceSpeed: DanceSpeed
    let currentSpriteLevel: SpriteLevel
    let isGameMode: Bool
    let hidesSprite: Bool
    let isHibernating: Bool
    let isContactAssigned: Bool
    let currencyBalance: Int
    let currencyTint: Color
    let streakTier: Int
    let onBuyFood: (FeedingOption) -> Void
    let onLogCall: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if !hidesSprite {
                PixelTamagotchi(
                    health: health,
                    sprite: sprite,
                    clothing: clothing,
                    danceSpeed: danceSpeed,
                    level: currentSpriteLevel,
                    showLevel: true,
                    labelOffsetY: -10,
                    isSleeping: isHibernating
                )
                .offset(y: -4)
            }

            EmptyView()

            if !isGameMode {
                VStack {
                    Spacer(minLength: 0)

                    HStack {
                        Spacer(minLength: 0)

                        FoodFeedRail(
                            currencyBalance: currencyBalance,
                            currencyTint: currencyTint,
                            streakTier: streakTier,
                            onBuyFood: onBuyFood
                        )
                        .padding(.trailing, 2)
                    }

                    Spacer(minLength: 0)
                }
                .offset(y: 34)

                VStack {
                    Spacer()

                    Button(action: ButtonClickSound.action(onLogCall)) {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.badge.plus.fill")
                                .font(.system(size: 16, weight: .black))
                            Text("Log Call")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.90))
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 7)
                    }
                    .buttonStyle(.plain)
                }
                .offset(y: 74)

                if !isContactAssigned {
                    VStack {
                        Spacer()

                        Text("Assign a contact in Settings")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.58))
                    }
                    .offset(y: 124)
                    .allowsHitTesting(false)
                } else if isHibernating {
                    VStack {
                        Spacer()

                        Text("Hibernating until you feed it")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.58))
                    }
                    .offset(y: 124)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 356)
    }

}

private struct FoodFeedRail: View {
    let currencyBalance: Int
    let currencyTint: Color
    let streakTier: Int
    let onBuyFood: (FeedingOption) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(FeedingOption.allCases) { option in
                let cost = option.cost(streakTier: streakTier)
                Button(action: ButtonClickSound.action { onBuyFood(option) }) {
                    HStack(spacing: 7) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(option.tint)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(option.tint.opacity(0.16))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.displayName)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

                            HStack(spacing: 3) {
                                Image(systemName: "circle.hexagongrid.fill")
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(currencyTint)
                                Text("\(cost)")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(currencyTint)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.88))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(currencyTint.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(currencyBalance < cost)
                .opacity(currencyBalance < cost ? 0.48 : 1)
                .accessibilityLabel("\(option.displayName), \(cost) coins")
            }
        }
        .frame(width: 104, alignment: .trailing)
    }
}

private struct SpriteSelectionGridView: View {
    let sprites: [TamagotchiSpriteProfile]
    let selectedSprite: TamagotchiSpriteProfile
    let selectedClothing: ClothingOption
    let selectedDanceSpeed: DanceSpeed
    let assignedSpriteIDs: Set<String>
    let onSelectSprite: (TamagotchiSpriteProfile) -> Void
    let onLockedSpriteTap: (TamagotchiSpriteProfile) -> Void
    let spriteLevels: [String: SpriteLevel]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Tamagotchi")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.09, green: 0.16, blue: 0.26))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sprites) { sprite in
                        let isAssigned = assignedSpriteIDs.contains(sprite.id)
                        Button(
                            action: ButtonClickSound.action {
                                if isAssigned {
                                    onSelectSprite(sprite)
                                } else {
                                    onLockedSpriteTap(sprite)
                                }
                            }
                        ) {
                            VStack(spacing: 8) {
                                ZStack {
                                    PixelTamagotchi(
                                        health: HealthPersistence.defaultHealth,
                                        sprite: sprite,
                                        clothing: selectedClothing,
                                        artSize: 96,
                                        showsLabels: false,
                                        showsBadge: false,
                                        danceSpeed: selectedDanceSpeed,
                                        level: spriteLevels[sprite.id],
                                        showLevel: false,
                                        showsLevelProgress: false
                                    )
                                    .opacity(isAssigned ? 1 : 0.34)

                                    if !isAssigned {
                                        Circle()
                                            .fill(Color.black.opacity(0.72))
                                            .frame(width: 38, height: 38)
                                            .overlay {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 16, weight: .black))
                                                    .foregroundStyle(.white)
                                            }
                                    }
                                }

                                Text(sprite.displayName)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.09, green: 0.16, blue: 0.26))
                                    .lineLimit(1)

                                if !isAssigned {
                                    Text("Assign contact")
                                        .font(.system(size: 11, weight: .black, design: .rounded))
                                        .foregroundStyle(Color(red: 0.88, green: 0.26, blue: 0.32))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(sprite == selectedSprite ? sprite.highlightColor : Color.black.opacity(0.08), lineWidth: sprite == selectedSprite ? 3 : 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct PixelGardenPlaygroundView: View {
    let sprites: [TamagotchiSpriteProfile]
    let selectedClothing: ClothingOption
    let isHibernating: Bool
    let onLaunchGame: () -> Void
    let onDragStateChanged: (Bool) -> Void

    @State private var pets: [GardenPet] = []
    @State private var lastTick = Date()
    @State private var activeDragPetID: UUID?
    @State private var activeDragScreenOffset: CGSize = .zero
    private let tickTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let worldBounds = CGSize(width: 10.0, height: 8.0)
    private let petArtSize: CGFloat = 70

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let iso = isoMetrics(for: size)

            ZStack(alignment: .topLeading) {
                // Drop your own scene art in Assets as "GardenIsometricBackdrop" to replace this fallback.
                if UIImage(named: "GardenIsometricBackdrop") != nil {
                    Image("GardenIsometricBackdrop")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    IsometricGardenFallbackBackground(iso: iso)
                }

                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: ButtonClickSound.action(onLaunchGame)) {
                            HStack(spacing: 7) {
                                Image(systemName: isHibernating ? "moon.zzz.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .black))
                                Text(isHibernating ? "Asleep" : "Play")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(isHibernating ? Color(red: 0.43, green: 0.38, blue: 0.58) : Color(red: 0.08, green: 0.15, blue: 0.24))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.84)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ForEach(pets) { pet in
                    let screenPoint: CGPoint = {
                        if pet.isAirborne {
                            return pet.airborneScreenPosition
                        }
                        let grounded = project(world: pet.worldPosition, iso: iso)
                        return CGPoint(x: grounded.x, y: grounded.y - 30)
                    }()
                    PixelTamagotchi(
                        health: 100,
                        sprite: pet.sprite,
                        clothing: selectedClothing,
                        artSize: petArtSize,
                        showsLabels: false,
                        showsBadge: false,
                        facingDirection: pet.facingDirection
                    )
                    .rotationEffect(.degrees(Double(max(-12, min(12, pet.velocity.width * 12)))))
                    .position(x: screenPoint.x, y: screenPoint.y)
                    .zIndex(Double(pet.worldPosition.y) + (pet.isHeld ? 100 : 0) + (pet.isAirborne ? 150 : 0))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeDragPetID = pet.id
                                guard let activeIndex = pets.firstIndex(where: { $0.id == pet.id }) else { return }
                                let displayedCenter: CGPoint = {
                                    if pets[activeIndex].isAirborne {
                                        return pets[activeIndex].airborneScreenPosition
                                    }
                                    let projected = project(world: pets[activeIndex].worldPosition, iso: iso)
                                    return CGPoint(x: projected.x, y: projected.y - 30)
                                }()
                                if !pets[activeIndex].isHeld {
                                    activeDragScreenOffset = CGSize(
                                        width: displayedCenter.x - value.location.x,
                                        height: displayedCenter.y - value.location.y
                                    )
                                }
                                pets[activeIndex].isHeld = true
                                pets[activeIndex].isAirborne = true
                                onDragStateChanged(true)
                                let anchoredDisplayPoint = CGPoint(
                                    x: value.location.x + activeDragScreenOffset.width,
                                    y: value.location.y + activeDragScreenOffset.height
                                )
                                pets[activeIndex].airborneScreenPosition = anchoredDisplayPoint
                                pets[activeIndex].airborneVelocity = .zero
                                if abs(value.translation.width) > 0.5 {
                                    pets[activeIndex].facingDirection = value.translation.width < 0 ? -1 : 1
                                }
                            }
                            .onEnded { value in
                                guard activeDragPetID == pet.id else { return }
                                activeDragPetID = nil
                                guard let activeIndex = pets.firstIndex(where: { $0.id == pet.id }) else { return }
                                pets[activeIndex].isHeld = false
                                let anchoredStart = CGPoint(
                                    x: value.location.x + activeDragScreenOffset.width,
                                    y: value.location.y + activeDragScreenOffset.height + 30
                                )
                                let anchoredEnd = CGPoint(
                                    x: value.predictedEndLocation.x + activeDragScreenOffset.width,
                                    y: value.predictedEndLocation.y + activeDragScreenOffset.height + 30
                                )
                                let startWorld = unproject(screen: anchoredStart, iso: iso)
                                let endWorld = unproject(screen: anchoredEnd, iso: iso)
                                pets[activeIndex].velocity = CGSize(
                                    width: max(-4.0, min(4.0, (endWorld.x - startWorld.x) * 9.0)),
                                    height: max(-4.0, min(4.0, (endWorld.y - startWorld.y) * 9.0))
                                )
                                pets[activeIndex].isAirborne = true
                                pets[activeIndex].airborneVelocity = CGSize(
                                    width: max(-950, min(950, value.predictedEndLocation.x - value.location.x)) * 3.2,
                                    height: max(-1300, min(1300, value.predictedEndLocation.y - value.location.y)) * 3.2
                                )
                                if abs(pets[activeIndex].airborneVelocity.width) > 24 {
                                    pets[activeIndex].facingDirection = pets[activeIndex].airborneVelocity.width < 0 ? -1 : 1
                                }
                                pets[activeIndex].airborneScreenPosition = CGPoint(
                                    x: value.location.x + activeDragScreenOffset.width,
                                    y: value.location.y + activeDragScreenOffset.height
                                )
                                pets[activeIndex].wanderTimer = Double.random(in: 1.2...2.4)
                                activeDragScreenOffset = .zero
                                onDragStateChanged(false)
                            }
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onAppear {
                refreshPetsIfNeeded()
                lastTick = Date()
            }
            .onChange(of: sprites.map(\.id)) { _, _ in
                refreshPetsIfNeeded()
            }
            .onReceive(tickTimer) { now in
                let dt = min(max(now.timeIntervalSince(lastTick), 0), 1.0 / 20.0)
                lastTick = now
                guard !pets.isEmpty else { return }

                for index in pets.indices {
                    if let activeDragPetID, pets[index].id == activeDragPetID { continue }
                    if pets[index].isHeld { continue }

                    if pets[index].isAirborne {
                        let gravity: CGFloat = 1650
                        let airDamping: CGFloat = 0.996
                        let maxLiftAbovePlane: CGFloat = 460
                        pets[index].airborneVelocity.height += gravity * CGFloat(dt)
                        pets[index].airborneScreenPosition.x += pets[index].airborneVelocity.width * CGFloat(dt)
                        pets[index].airborneScreenPosition.y += pets[index].airborneVelocity.height * CGFloat(dt)
                        pets[index].airborneVelocity.width *= airDamping
                        pets[index].airborneVelocity.height *= airDamping
                        if abs(pets[index].airborneVelocity.width) > 12 {
                            pets[index].facingDirection = pets[index].airborneVelocity.width < 0 ? -1 : 1
                        }

                        let projectedGround = project(world: pets[index].worldPosition, iso: iso)
                        let minAirY = projectedGround.y - 30 - maxLiftAbovePlane
                        if pets[index].airborneScreenPosition.y < minAirY {
                            pets[index].airborneScreenPosition.y = minAirY
                            if pets[index].airborneVelocity.height < 0 {
                                pets[index].airborneVelocity.height *= -0.35
                            }
                        }

                        let airWorld = unproject(
                            screen: CGPoint(
                                x: pets[index].airborneScreenPosition.x,
                                y: pets[index].airborneScreenPosition.y + 30
                            ),
                            iso: iso
                        )
                        let planeInset: CGFloat = 0.45
                        let landingInset: CGFloat = 1.05
                        let inPlaneBounds =
                            airWorld.x >= planeInset &&
                            airWorld.x <= (worldBounds.width - planeInset) &&
                            airWorld.y >= planeInset &&
                            airWorld.y <= (worldBounds.height - planeInset)
                        let worldInPlane =
                            airWorld.x >= landingInset &&
                            airWorld.x <= (worldBounds.width - landingInset) &&
                            airWorld.y >= landingInset &&
                            airWorld.y <= (worldBounds.height - landingInset)

                        if inPlaneBounds {
                            pets[index].offPlaneDuration = 0
                        } else {
                            pets[index].offPlaneDuration += dt
                        }

                        if pets[index].offPlaneDuration > 1.6 {
                            let returnTarget = CGPoint(
                                x: CGFloat.random(in: landingInset...(worldBounds.width - landingInset)),
                                y: CGFloat.random(in: landingInset...(worldBounds.height - landingInset))
                            )
                            pets[index].worldPosition = returnTarget
                            let returnGround = project(world: returnTarget, iso: iso)
                            pets[index].airborneScreenPosition = CGPoint(
                                x: returnGround.x,
                                y: returnGround.y - (size.height + 520)
                            )
                            pets[index].airborneVelocity = CGSize(width: 0, height: 110)
                            pets[index].offPlaneDuration = 0
                        }

                        if worldInPlane && pets[index].airborneVelocity.height > 0 {
                            pets[index].isAirborne = false
                            let landedPoint = CGPoint(
                                x: min(max(airWorld.x, landingInset), worldBounds.width - landingInset),
                                y: min(max(airWorld.y, landingInset), worldBounds.height - landingInset)
                            )
                            pets[index].worldPosition = landedPoint
                            pets[index].velocity.width += max(-2.6, min(2.6, pets[index].airborneVelocity.width / 300))
                            pets[index].velocity.height += max(-2.6, min(2.6, pets[index].airborneVelocity.height / 300))
                            pets[index].airborneVelocity = .zero
                            pets[index].offPlaneDuration = 0
                        }
                        continue
                    }

                    pets[index].wanderTimer -= dt
                    if pets[index].wanderTimer <= 0 {
                        pets[index].wanderTimer = Double.random(in: 0.35...1.95)
                        pets[index].wanderHeading = CGSize(
                            width: CGFloat.random(in: -1...1),
                            height: CGFloat.random(in: -1...1)
                        )
                        if Double.random(in: 0...1) < 0.16 {
                            pets[index].velocity.width += CGFloat.random(in: -0.95...0.95)
                            pets[index].velocity.height += CGFloat.random(in: -0.95...0.95)
                        }
                    }

                    let headingJitter = CGSize(
                        width: CGFloat.random(in: -0.5...0.5),
                        height: CGFloat.random(in: -0.5...0.5)
                    )
                    let wanderAcceleration: CGFloat = 1.2
                    pets[index].velocity.width += (pets[index].wanderHeading.width + headingJitter.width * 0.35) * wanderAcceleration * CGFloat(dt)
                    pets[index].velocity.height += (pets[index].wanderHeading.height + headingJitter.height * 0.35) * wanderAcceleration * CGFloat(dt)

                    let maxSpeed: CGFloat = 3.1
                    pets[index].velocity.width = max(-maxSpeed, min(maxSpeed, pets[index].velocity.width))
                    pets[index].velocity.height = max(-maxSpeed, min(maxSpeed, pets[index].velocity.height))

                    pets[index].worldPosition.x += pets[index].velocity.width * CGFloat(dt)
                    pets[index].worldPosition.y += pets[index].velocity.height * CGFloat(dt)

                    let damping: CGFloat = Double.random(in: 0...1) < 0.08 ? 0.965 : 0.982
                    pets[index].velocity.width *= damping
                    pets[index].velocity.height *= damping
                    if abs(pets[index].velocity.width) > 0.08 {
                        pets[index].facingDirection = pets[index].velocity.width < 0 ? -1 : 1
                    }

                    let minX: CGFloat = 0.45
                    let maxX: CGFloat = worldBounds.width - 0.45
                    let minY: CGFloat = 0.45
                    let maxY: CGFloat = worldBounds.height - 0.45
                    let bounce: CGFloat = 0.72

                    if pets[index].worldPosition.x < minX {
                        pets[index].worldPosition.x = minX
                        pets[index].velocity.width = abs(pets[index].velocity.width) * bounce
                    } else if pets[index].worldPosition.x > maxX {
                        pets[index].worldPosition.x = maxX
                        pets[index].velocity.width = -abs(pets[index].velocity.width) * bounce
                    }

                    if pets[index].worldPosition.y < minY {
                        pets[index].worldPosition.y = minY
                        pets[index].velocity.height = abs(pets[index].velocity.height) * bounce
                    } else if pets[index].worldPosition.y > maxY {
                        pets[index].worldPosition.y = maxY
                        pets[index].velocity.height = -abs(pets[index].velocity.height) * bounce
                    }

                }
            }
            .onDisappear {
                onDragStateChanged(false)
            }
        }
    }

    private func refreshPetsIfNeeded() {
        guard pets.map(\.sprite.id) != sprites.map(\.id) else { return }
        pets = sprites.enumerated().map { index, sprite in
            return GardenPet(
                sprite: sprite,
                worldPosition: CGPoint(
                    x: CGFloat.random(in: 0.8...(worldBounds.width - 0.8)),
                    y: CGFloat.random(in: 0.8...(worldBounds.height - 0.8))
                ),
                velocity: CGSize(
                    width: CGFloat.random(in: -0.45...0.45),
                    height: CGFloat.random(in: -0.45...0.45)
                )
            )
        }
    }

    private func isoMetrics(for size: CGSize) -> IsometricMetrics {
        let tileWidth = min(size.width * 0.11, 52)
        let tileHeight = tileWidth * 0.54
        let origin = CGPoint(x: size.width * 0.50, y: size.height * 0.46)
        return IsometricMetrics(origin: origin, tileWidth: tileWidth, tileHeight: tileHeight, worldSize: worldBounds)
    }

    private func project(world: CGPoint, iso: IsometricMetrics) -> CGPoint {
        let centeredX = world.x - (iso.worldSize.width / 2)
        let centeredY = world.y - (iso.worldSize.height / 2)
        return CGPoint(
            x: iso.origin.x + (centeredX - centeredY) * (iso.tileWidth / 2),
            y: iso.origin.y + (centeredX + centeredY) * (iso.tileHeight / 2)
        )
    }

    private func unproject(screen: CGPoint, iso: IsometricMetrics) -> CGPoint {
        let dx = screen.x - iso.origin.x
        let dy = screen.y - iso.origin.y
        let a = dx / (iso.tileWidth / 2)
        let b = dy / (iso.tileHeight / 2)
        let centeredX = (a + b) / 2
        let centeredY = (b - a) / 2
        return CGPoint(
            x: centeredX + (iso.worldSize.width / 2),
            y: centeredY + (iso.worldSize.height / 2)
        )
    }

    private func clampedWorldPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0.45), worldBounds.width - 0.45),
            y: min(max(point.y, 0.45), worldBounds.height - 0.45)
        )
    }
}

private struct GardenPet: Identifiable {
    let id = UUID()
    let sprite: TamagotchiSpriteProfile
    var worldPosition: CGPoint
    var velocity: CGSize
    var isHeld = false
    var isAirborne = false
    var airborneScreenPosition: CGPoint = .zero
    var airborneVelocity: CGSize = .zero
    var offPlaneDuration: TimeInterval = 0
    var facingDirection: CGFloat = 1
    var wanderHeading: CGSize = .zero
    var wanderTimer: TimeInterval = Double.random(in: 0.5...1.6)
}

private struct IsometricMetrics {
    let origin: CGPoint
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let worldSize: CGSize
}

private struct IsometricGardenFallbackBackground: View {
    let iso: IsometricMetrics

    var body: some View {
        ZStack {
            let columns = Int(iso.worldSize.width)
            let rows = Int(iso.worldSize.height)
            let depth = max(22, iso.tileHeight * 1.6)

            let topLeft = project(world: CGPoint(x: 0, y: 0), iso: iso)
            let topRight = project(world: CGPoint(x: iso.worldSize.width, y: 0), iso: iso)
            let bottomRight = project(world: CGPoint(x: iso.worldSize.width, y: iso.worldSize.height), iso: iso)
            let bottomLeft = project(world: CGPoint(x: 0, y: iso.worldSize.height), iso: iso)

            // Right side wall.
            Path { path in
                path.move(to: topRight)
                path.addLine(to: bottomRight)
                path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y + depth))
                path.addLine(to: CGPoint(x: topRight.x, y: topRight.y + depth))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.52, green: 0.35, blue: 0.20).opacity(0.95),
                        Color(red: 0.39, green: 0.25, blue: 0.14).opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Front side wall.
            Path { path in
                path.move(to: bottomLeft)
                path.addLine(to: bottomRight)
                path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y + depth))
                path.addLine(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y + depth))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.58, green: 0.39, blue: 0.23).opacity(0.95),
                        Color(red: 0.43, green: 0.29, blue: 0.17).opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Vertical seams on side walls to suggest stacked tile depth.
            Path { path in
                for x in 0...columns {
                    let p = project(world: CGPoint(x: CGFloat(x), y: iso.worldSize.height), iso: iso)
                    path.move(to: p)
                    path.addLine(to: CGPoint(x: p.x, y: p.y + depth))
                }
                for y in 0...rows {
                    let p = project(world: CGPoint(x: iso.worldSize.width, y: CGFloat(y)), iso: iso)
                    path.move(to: p)
                    path.addLine(to: CGPoint(x: p.x, y: p.y + depth))
                }
            }
            .stroke(Color.black.opacity(0.12), lineWidth: 1)

            ForEach(0..<columns, id: \.self) { x in
                ForEach(0..<rows, id: \.self) { y in
                    let top = project(world: CGPoint(x: CGFloat(x), y: CGFloat(y)), iso: iso)
                    let right = project(world: CGPoint(x: CGFloat(x + 1), y: CGFloat(y)), iso: iso)
                    let bottom = project(world: CGPoint(x: CGFloat(x + 1), y: CGFloat(y + 1)), iso: iso)
                    let left = project(world: CGPoint(x: CGFloat(x), y: CGFloat(y + 1)), iso: iso)
                    let axisBandA = (x % 3) == 0
                    let axisBandB = (y % 3) == 0

                    Path { path in
                        path.move(to: top)
                        path.addLine(to: right)
                        path.addLine(to: bottom)
                        path.addLine(to: left)
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                (axisBandA ? Color(red: 0.72, green: 0.90, blue: 0.62) : Color(red: 0.64, green: 0.84, blue: 0.56)).opacity(0.92),
                                (axisBandB ? Color(red: 0.53, green: 0.78, blue: 0.47) : Color(red: 0.47, green: 0.72, blue: 0.44)).opacity(0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }

            Path { path in
                for x in 0...columns {
                    let start = project(world: CGPoint(x: CGFloat(x), y: 0), iso: iso)
                    let end = project(world: CGPoint(x: CGFloat(x), y: iso.worldSize.height), iso: iso)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                for y in 0...rows {
                    let start = project(world: CGPoint(x: 0, y: CGFloat(y)), iso: iso)
                    let end = project(world: CGPoint(x: iso.worldSize.width, y: CGFloat(y)), iso: iso)
                    path.move(to: start)
                    path.addLine(to: end)
                }
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    private func project(world: CGPoint, iso: IsometricMetrics) -> CGPoint {
        let centeredX = world.x - (iso.worldSize.width / 2)
        let centeredY = world.y - (iso.worldSize.height / 2)
        return CGPoint(
            x: iso.origin.x + (centeredX - centeredY) * (iso.tileWidth / 2),
            y: iso.origin.y + (centeredX + centeredY) * (iso.tileHeight / 2)
        )
    }
}

private struct PixelTamagotchi: View {
    let health: Double
    let sprite: TamagotchiSpriteProfile
    let clothing: ClothingOption
    var artSize: CGFloat = 200
    var showsLabels: Bool = true
    var showsBadge: Bool = true
    var danceSpeed: DanceSpeed = .normal
    var level: SpriteLevel? = nil
    var showLevel: Bool = false
    var showsLevelProgress: Bool = true
    var labelOffsetY: CGFloat = 0
    var isSleeping: Bool = false
    var facingDirection: CGFloat = 1

    var body: some View {
        VStack(spacing: showsLabels ? 10 : 0) {
        
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    if let atlas = sprite.atlas {
                        TimelineView(.animation(minimumInterval: frameInterval(for: atlas), paused: isSleeping)) { context in
                            if let atlasSpriteImage = atlasSpriteImage(at: context.date, atlas: atlas) {
                                atlasSpriteImage
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: artSize, height: artSize)
                            } else {
                                fallbackPixelSprite
                            }
                        }
                    } else {
                        fallbackPixelSprite
                    }

                    if isSleeping {
                        Text("Zzz")
                            .font(.system(size: max(16, artSize * 0.12), weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.38, blue: 0.58))
                            .padding(.horizontal, max(8, artSize * 0.05))
                            .padding(.vertical, max(4, artSize * 0.03))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                            )
                            .offset(x: artSize * 0.08, y: artSize * 0.02)
                    }
                }
                .scaleEffect(x: facingDirection, y: 1, anchor: .center)
                .opacity(isSleeping ? 0.58 : 1)
                .saturation(isSleeping ? 0.30 : 1)
                .rotationEffect(.degrees(isSleeping ? -8 : 0))

                if showLevel, let level = level {
                    PixelLevelBadge(
                        level: level.level,
                        experienceProgress: level.progressToNextLevel(),
                        showsProgress: showsLevelProgress
                    )
                    .offset(x: -8, y: 6)
                }
            }

            if showsLabels {

                Text(sprite.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .offset(y: labelOffsetY)
            }
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


    private var mouthCharacter: Character {
        health > 35 ? "M" : "S"
    }

    private var fallbackPixelSprite: some View {
        PixelCharacterGrid(
            pixels: pixelRows,
            palette: pixelPalette
        )
        .frame(width: artSize, height: artSize)
        .drawingGroup()
    }

    private func frameInterval(for atlas: TamagotchiAtlas) -> TimeInterval {
        let baseInterval = atlas.idleAnimation.frameInterval
        // User-selected speed is the baseline; low health slows the animation down.
        return baseInterval / effectiveAnimationSpeedMultiplier
    }

    private func atlasSpriteImage(at date: Date, atlas: TamagotchiAtlas) -> Image? {
        guard
            let atlasFrameImage = TamagotchiAtlasRenderer.frameImage(
                for: atlas,
                frameIndex: atlasFrameIndex(at: date, atlas: atlas)
            )
        else {
            return nil
        }

        return Image(uiImage: atlasFrameImage)
    }

    private func atlasFrameIndex(at date: Date, atlas: TamagotchiAtlas) -> Int {
        let adjustedInterval = atlas.idleAnimation.frameInterval / effectiveAnimationSpeedMultiplier
        return Int(date.timeIntervalSinceReferenceDate / adjustedInterval)
    }

    private var effectiveAnimationSpeedMultiplier: Double {
        danceSpeed.animationSpeedMultiplier * healthAnimationMultiplier
    }

    private var healthAnimationMultiplier: Double {
        switch health {
        case 70...:
            return 1.0
        case 40..<70:
            return 0.78
        case 20..<40:
            return 0.52
        case 1..<20:
            return 0.32
        default:
            return 0.20
        }
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

        if clothing == .topHat || clothing == .crown || clothing == .propellerHat {
            rows[1] = ".....BBLLBB....."
            rows[2] = "...BBBLLLLBBB..."
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

private struct FlappyTamagotchiGameView: View {
    let theme: AppTheme
    let health: Double
    let sprite: TamagotchiSpriteProfile
    let clothing: ClothingOption
    let birdVisible: Bool
    let onEarnCurrency: (Int) -> Void
    let onExit: () -> Void

    @State private var birdY: CGFloat = 0
    @State private var birdVelocity: CGFloat = 0
    @State private var pipes: [FlappyPipe] = []
    @State private var score = 0
    @State private var highScore = 0
    @State private var hasStarted = false
    @State private var isGameOver = false
    @State private var lastTick = Date()

    private let gameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            let sceneFrame = FlappyGameLayout.sceneFrame(in: containerSize)
            let sceneSize = sceneFrame.size
            let displayedBirdY = birdY == 0 ? FlappyGameLayout.birdSpawnY(for: sceneSize) : birdY

            ZStack(alignment: .top) {
                ForEach(pipes) { pipe in
                    FlappyPipeView(pipe: pipe, size: sceneSize, tint: theme.pipeColor)
                }

                if birdVisible {
                    PixelTamagotchi(
                        health: health,
                        sprite: sprite,
                        clothing: clothing,
                        artSize: FlappyGameLayout.birdArtSize(for: sceneSize),
                        showsLabels: false,
                        showsBadge: false
                    )
                    .rotationEffect(.degrees(Double(max(-26, min(28, birdVelocity * 0.05)))))
                    .position(
                        x: FlappyGameLayout.birdX(for: sceneSize),
                        y: displayedBirdY
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 8)
                }

                VStack(spacing: 18) {
                    HStack(alignment: .center) {
                        ScorePill(score: score, highScore: highScore)
                        Spacer()
                        Button(action: ButtonClickSound.action(onExit)) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.82))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if !hasStarted {
                        GamePromptCard(
                            title: "Flappy Mode",
                            subtitle: "Tap anywhere to flap."
                        )
                    } else if isGameOver {
                        GamePromptCard(
                            title: "Try Again",
                            subtitle: "Best for \(sprite.displayName): \(highScore)"
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

            }
            .frame(width: sceneFrame.width, height: sceneFrame.height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .position(x: sceneFrame.midX, y: sceneFrame.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap(in: sceneSize)
            }
            .onAppear {
                loadHighScore()
                resetGame(in: sceneSize)
            }
            .onChange(of: sprite.id) { _, _ in
                loadHighScore()
                resetGame(in: sceneSize)
            }
            .onReceive(gameTimer) { now in
                update(now: now, in: sceneSize)
            }
        }
        .ignoresSafeArea()
    }

    private func handleTap(in size: CGSize) {
        if isGameOver {
            resetGame(in: size)
        }

        if !hasStarted {
            hasStarted = true
            lastTick = Date()
        }

        SoundEffectPlayer.play(.flappyFlap)
        birdVelocity = -285
    }

    private func update(now: Date, in size: CGSize) {
        guard hasStarted, !isGameOver else {
            lastTick = now
            return
        }

        let deltaTime = min(max(now.timeIntervalSince(lastTick), 0), 1.0 / 20.0)
        lastTick = now

        birdVelocity += CGFloat(710 * deltaTime)
        birdY += birdVelocity * CGFloat(deltaTime)

        let pipeSpeed = max(148, size.width * 0.34)
        let pipeWidth = max(72, size.width * 0.16)
        let birdX = size.width * 0.30
        let birdSize = max(72, min(96, size.width * 0.18))

        for index in pipes.indices {
            pipes[index].x -= pipeSpeed * CGFloat(deltaTime)
            if !pipes[index].didScore, pipes[index].x + pipeWidth / 2 < birdX {
                pipes[index].didScore = true
                score += 1
                if score % 10 == 0 {
                    onEarnCurrency(1)
                }
                saveHighScoreIfNeeded()
            }
        }

        pipes.removeAll { $0.x < -pipeWidth }

        let spacingBase = max(220, size.width * 0.50)
        while pipes.count < 3 {
            let nextX = (pipes.last?.x ?? (size.width + 120)) + randomPipeSpacing(base: spacingBase)
            pipes.append(randomPipe(at: nextX))
        }

        if birdY < birdSize * 0.4 || birdY > size.height - birdSize * 0.32 {
            isGameOver = true
            return
        }

        let birdRect = CGRect(
            x: birdX - birdSize * 0.32,
            y: birdY - birdSize * 0.28,
            width: birdSize * 0.64,
            height: birdSize * 0.56
        )

        for pipe in pipes {
            let gapHeight = pipe.gapHeight(for: size.height)
            let gapCenterY = size.height * CGFloat(pipe.gapCenterRatio)
            let upperRect = CGRect(x: pipe.x - pipeWidth / 2, y: 0, width: pipeWidth, height: gapCenterY - gapHeight / 2)
            let lowerRect = CGRect(
                x: pipe.x - pipeWidth / 2,
                y: gapCenterY + gapHeight / 2,
                width: pipeWidth,
                height: size.height - (gapCenterY + gapHeight / 2)
            )

            if birdRect.intersects(upperRect) || birdRect.intersects(lowerRect) {
                isGameOver = true
                return
            }
        }
    }

    private func resetGame(in size: CGSize) {
        let spacingBase = max(220, size.width * 0.50)
        birdY = FlappyGameLayout.birdSpawnY(for: size)
        birdVelocity = 0
        score = 0
        hasStarted = false
        isGameOver = false
        lastTick = Date()
        let firstX = size.width + 120
        let secondX = firstX + randomPipeSpacing(base: spacingBase)
        let thirdX = secondX + randomPipeSpacing(base: spacingBase)
        pipes = [
            randomPipe(at: firstX),
            randomPipe(at: secondX),
            randomPipe(at: thirdX)
        ]
    }

    private func randomPipe(at x: CGFloat) -> FlappyPipe {
        FlappyPipe(
            x: x,
            gapCenterRatio: Double.random(in: 0.24...0.76),
            gapHeightRatio: Double.random(in: 0.21...0.28)
        )
    }

    private func randomPipeSpacing(base: CGFloat) -> CGFloat {
        base + CGFloat.random(in: 18...92)
    }

    private func loadHighScore() {
        highScore = FlappyHighScorePersistence.highScore(for: sprite.id)
    }

    private func saveHighScoreIfNeeded() {
        guard score > highScore else { return }
        highScore = score
        FlappyHighScorePersistence.save(score: score, for: sprite.id)
    }
}

private struct LaunchingGameSpriteOverlay: View {
    let containerSize: CGSize
    let metrics: LayoutMetrics
    let progress: CGFloat
    let health: Double
    let sprite: TamagotchiSpriteProfile
    let clothing: ClothingOption

    var body: some View {
        let startX = containerSize.width * 0.5
        let startY = metrics.topPadding + metrics.topButtonSize + metrics.sectionSpacing + 176
        let sceneFrame = FlappyGameLayout.sceneFrame(in: containerSize)
        let endX = sceneFrame.minX + FlappyGameLayout.birdX(for: sceneFrame.size)
        let endY = sceneFrame.minY + FlappyGameLayout.birdSpawnY(for: sceneFrame.size)
        let startSize: CGFloat = 150
        let endSize = FlappyGameLayout.birdArtSize(for: sceneFrame.size)

        PixelTamagotchi(
            health: health,
            sprite: sprite,
            clothing: clothing,
            artSize: startSize + ((endSize - startSize) * progress),
            showsLabels: false,
            showsBadge: false
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 8)
        .position(
            x: startX + ((endX - startX) * progress),
            y: startY + ((endY - startY) * progress)
        )
    }
}

private enum FlappyGameLayout {
    static let sceneHorizontalPadding: CGFloat = 14
    static let sceneTopPadding: CGFloat = 22
    static let sceneBottomPadding: CGFloat = 24

    static func birdArtSize(for size: CGSize) -> CGFloat {
        max(84, min(112, size.width * 0.22))
    }

    static func birdX(for size: CGSize) -> CGFloat {
        size.width * 0.30
    }

    static func initialBirdY(for size: CGSize) -> CGFloat {
        size.height * 0.43
    }

    static func birdSpawnY(for size: CGSize) -> CGFloat {
        initialBirdY(for: size) - 10
    }

    static func sceneFrame(in container: CGSize) -> CGRect {
        CGRect(
            x: sceneHorizontalPadding,
            y: sceneTopPadding,
            width: max(0, container.width - (sceneHorizontalPadding * 2)),
            height: max(0, container.height - sceneTopPadding - sceneBottomPadding)
        )
    }
}

private enum FlappyHighScorePersistence {
    private static let storageKey = "flappy.highScoresBySprite"

    static func highScore(for spriteID: String) -> Int {
        max(loadScores()[SpriteIDMigration.canonical(spriteID)] ?? 0, 0)
    }

    static func save(score: Int, for spriteID: String) {
        var scores = loadScores()
        let canonicalSpriteID = SpriteIDMigration.canonical(spriteID)
        scores[canonicalSpriteID] = max(score, highScore(for: canonicalSpriteID))

        guard let encoded = try? JSONEncoder().encode(scores) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    private static func loadScores() -> [String: Int] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let scores = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }

        let sanitizedScores = scores.mapValues { max($0, 0) }
        let migratedScores = SpriteIDMigration.migratedValues(sanitizedScores)
        if migratedScores != sanitizedScores {
            guard let encoded = try? JSONEncoder().encode(migratedScores) else { return migratedScores }
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
        return migratedScores
    }
}

private struct GamePromptCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))

            Text(subtitle)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.34, green: 0.44, blue: 0.50))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
    }
}

private struct ScorePill: View {
    let score: Int
    let highScore: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 13, weight: .black))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(score)")
                    .font(.system(size: 16, weight: .black, design: .rounded))

                Text("Best \(highScore)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.33, green: 0.43, blue: 0.51))
            }
        }
        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
    }
}

private struct FlappyPipeView: View {
    let pipe: FlappyPipe
    let size: CGSize
    let tint: Color

    var body: some View {
        let pipeWidth = max(72, size.width * 0.16)
        let gapHeight = pipe.gapHeight(for: size.height)
        let gapCenterY = size.height * CGFloat(pipe.gapCenterRatio)
        let upperHeight = max(40, gapCenterY - gapHeight / 2)
        let lowerY = gapCenterY + gapHeight / 2
        let lowerHeight = max(40, size.height - lowerY)

        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: pipeWidth, height: upperHeight)

            Spacer(minLength: gapHeight)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: pipeWidth, height: lowerHeight)
        }
        .frame(height: size.height, alignment: .top)
        .position(x: pipe.x, y: size.height / 2)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 8)
    }
}

private struct FlappyPipe: Identifiable {
    let id = UUID()
    var x: CGFloat
    var gapCenterRatio: Double
    var gapHeightRatio: Double
    var didScore = false

    func gapHeight(for screenHeight: CGFloat) -> CGFloat {
        max(168, screenHeight * gapHeightRatio)
    }
}

private enum DetailCardPalette {
    static let primaryText = Color(red: 0.08, green: 0.15, blue: 0.24)
    static let secondaryText = Color(red: 0.31, green: 0.45, blue: 0.50)
    static let bodyText = Color(red: 0.10, green: 0.17, blue: 0.27)
    static let mutedText = Color(red: 0.39, green: 0.49, blue: 0.54)
    static let cardFill = Color.white.opacity(0.94)
    static let cardStroke = Color.white.opacity(0.82)
    static let surfaceFill = Color.white.opacity(0.92)
    static let surfaceStrongFill = Color.white.opacity(0.97)
}

private struct DetailPageCard: View {
    let page: HomePage
    @Binding var selectedClothing: ClothingOption
    @Binding var selectedDanceSpeed: DanceSpeed
    let streakTier: Int
    @Binding var selectedTheme: AppTheme
    @Binding var streakDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            if page == .upgrades {
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
                .fill(DetailCardPalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(DetailCardPalette.cardStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
        .environment(\.colorScheme, .light)
    }

    private var upgradesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dance Speed")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            HStack(spacing: 8) {
                ForEach(DanceSpeed.allCases) { speed in
                    Button(action: ButtonClickSound.action { selectedDanceSpeed = speed }) {
                        Text(speed.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedDanceSpeed == speed ? .white : Color(red: 0.10, green: 0.17, blue: 0.27))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedDanceSpeed == speed ? Color(red: 0.16, green: 0.63, blue: 0.53) : DetailCardPalette.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Streak")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Streak Boost Tier \(streakTier)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(DetailCardPalette.bodyText)

                    Spacer(minLength: 8)

                    Text(StreakCalculator.label(for: streakDays))
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.62, blue: 0.54))
                }

                ProgressView(value: Double(streakTier), total: 3)
                    .tint(Color(red: 0.12, green: 0.76, blue: 0.60))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DetailCardPalette.surfaceFill)
            )

            Text("Current streak: \(streakDays) days")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.21, green: 0.33, blue: 0.40))

            Text("Themes")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            ForEach(AppTheme.allCases) { theme in
                Button(action: ButtonClickSound.action { selectedTheme = theme }) {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Circle().fill(theme.primary).frame(width: 10, height: 10)
                            Circle().fill(theme.secondary).frame(width: 10, height: 10)
                            Circle().fill(theme.tertiary).frame(width: 10, height: 10)
                        }

                        Text(theme.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DetailCardPalette.bodyText)

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
                            .fill(DetailCardPalette.surfaceFill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CurrencyPill: View {
    let balance: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color(red: 0.94, green: 0.62, blue: 0.18))

            Text("\(balance)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.bodyText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(DetailCardPalette.surfaceStrongFill)
        )
    }
}

private struct LogPageCard: View {
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?
    @Binding var minutes: String
    let entries: [CallLogEntry]
    let onSubmit: () -> Void
    let onSelectRecent: (CallLogEntry) -> Void
    let onImportContact: () -> Void
    let onCallContact: (AppContact) -> Void
    let onOpenSettings: () -> Void

    private var formIsValid: Bool {
        selectedContactID != nil && (Int(minutes) ?? 0) > 0
    }

    private var selectedContact: AppContact? {
        guard let selectedContactID else { return nil }
        return contacts.first(where: { $0.id == selectedContactID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Log a Call")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            if contacts.isEmpty {
                EmptyLogStateCard(onImportContact: onImportContact, onOpenSettings: onOpenSettings)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ContactPickerField(contacts: contacts, selectedContactID: $selectedContactID)

                    HStack(spacing: 10) {
                        Button(action: ButtonClickSound.action(onImportContact)) {
                            Label("Import Contact", systemImage: "person.crop.circle.badge.plus")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(DetailCardPalette.bodyText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(DetailCardPalette.surfaceFill)
                                )
                        }
                        .buttonStyle(.plain)

                        if let selectedContact, selectedContact.phoneNumber != nil {
                            Button(action: ButtonClickSound.action { onCallContact(selectedContact) }) {
                                Label("Call", systemImage: "phone.fill")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(red: 0.12, green: 0.76, blue: 0.60))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: ButtonClickSound.action(onSubmit)) {
                        HStack {
                            Image(systemName: "phone.badge.plus.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Log Call")
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

                    LogInputField(
                        title: "Minutes",
                        placeholder: "Ex. 15",
                        text: $minutes,
                        isNumeric: true
                    )

                    RecentLogShortcuts(entries: entries, onSelect: onSelectRecent)
                }
            }

            if !contacts.isEmpty {
                RecentCallsList(entries: entries)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(DetailCardPalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(DetailCardPalette.cardStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
        .environment(\.colorScheme, .light)
    }
}

private struct RecentCallsList: View {
    let entries: [CallLogEntry]
    @State private var page = 0

    private let pageSize = 5

    private var pageCount: Int {
        max(1, Int(ceil(Double(entries.count) / Double(pageSize))))
    }

    private var clampedPage: Int {
        min(max(page, 0), pageCount - 1)
    }

    private var visibleEntries: [CallLogEntry] {
        let startIndex = clampedPage * pageSize
        let endIndex = min(startIndex + pageSize, entries.count)
        guard startIndex < endIndex else { return [] }
        return Array(entries[startIndex..<endIndex])
    }

    private var rangeText: String {
        guard !entries.isEmpty else { return "No calls logged yet" }
        let start = clampedPage * pageSize + 1
        let end = min(start + visibleEntries.count - 1, entries.count)
        return "Showing \(start)-\(end) of \(entries.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Most Recent")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(DetailCardPalette.primaryText)

                Spacer(minLength: 8)

                Text(rangeText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.mutedText)
            }

            if visibleEntries.isEmpty {
                SettingsHint(text: "Logged calls will appear here.")
            } else {
                ForEach(visibleEntries) { entry in
                    CallLogRow(entry: entry)
                }
            }

            if entries.count > pageSize {
                HStack(spacing: 10) {
                    Button(action: ButtonClickSound.action(showPreviousPage)) {
                        Label("Previous", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DetailCardPalette.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(clampedPage == 0)
                    .opacity(clampedPage == 0 ? 0.45 : 1)

                    Button(action: ButtonClickSound.action(showNextPage)) {
                        Label("Next", systemImage: "chevron.right")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DetailCardPalette.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(clampedPage >= pageCount - 1)
                    .opacity(clampedPage >= pageCount - 1 ? 0.45 : 1)
                }
                .foregroundStyle(DetailCardPalette.bodyText)
            }
        }
        .onChange(of: entries.count) { _, _ in
            page = min(page, pageCount - 1)
        }
    }

    private func showPreviousPage() {
        page = max(clampedPage - 1, 0)
    }

    private func showNextPage() {
        page = min(clampedPage + 1, pageCount - 1)
    }
}

private struct EmptyLogStateCard: View {
    let onImportContact: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add contacts before logging calls.")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DetailCardPalette.bodyText)

            Text("Your log only tracks people from your contact list so the check-ins stay intentional.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DetailCardPalette.mutedText)

            HStack(spacing: 10) {
                Button(action: ButtonClickSound.action(onImportContact)) {
                    Label("Import", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.12, green: 0.76, blue: 0.60))
                        )
                }
                .buttonStyle(.plain)

                Button(action: ButtonClickSound.action(onOpenSettings)) {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(red: 0.44, green: 0.58, blue: 0.94))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
        )
    }
}

private struct RecentLogShortcuts: View {
    let entries: [CallLogEntry]
    let onSelect: (CallLogEntry) -> Void

    private var suggestions: [CallLogEntry] {
        Array(entries.prefix(4))
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use Recent")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(DetailCardPalette.primaryText)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(suggestions) { entry in
                        Button(action: ButtonClickSound.action { onSelect(entry) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(DetailCardPalette.bodyText)
                                    .lineLimit(1)

                                Text("\(entry.minutes) min")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DetailCardPalette.mutedText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DetailCardPalette.surfaceFill)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ContactPickerField: View {
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contact")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DetailCardPalette.bodyText)

            Picker("Contact", selection: $selectedContactID) {
                ForEach(contacts) { contact in
                    Text(contact.name).tag(contact.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .foregroundStyle(DetailCardPalette.bodyText)
            .tint(DetailCardPalette.bodyText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DetailCardPalette.surfaceStrongFill)
            )
        }
    }
}

private struct SettingsPageCard: View {
    let contacts: [AppContact]
    @Binding var preferredContactID: UUID?
    @Binding var spriteContactAssignments: [String: UUID]
    let sprites: [TamagotchiSpriteProfile]
    @Binding var notificationPreferences: NotificationPreferences
    let onImportContact: () -> Void
    let onDeleteContact: (AppContact) -> Void
    let onAddReminder: () -> Void
    let onDeleteReminder: (CallReminder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle(title: "Contacts")

                Button(action: ButtonClickSound.action(onImportContact)) {
                    Label("Import from iPhone Contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(DetailCardPalette.bodyText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DetailCardPalette.surfaceFill)
                        )
                }
                .buttonStyle(.plain)

                if contacts.isEmpty {
                    SettingsHint(text: "Import at least one contact to enable the call log.")
                } else {
                    ForEach(contacts) { contact in
                        ContactSettingsRow(
                            contact: contact,
                            isPreferred: preferredContactID == contact.id,
                            onSetPreferred: { preferredContactID = contact.id },
                            onDelete: { onDeleteContact(contact) }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle(title: "Tamagotchi Contacts")

                if contacts.isEmpty {
                    SettingsHint(text: "Add contacts before assigning them to Tamagotchis.")
                } else {
                    ForEach(sprites) { sprite in
                        ContactAssignmentRow(
                            sprite: sprite,
                            contacts: contacts,
                            selectedContactID: Binding(
                                get: { spriteContactAssignments[sprite.id] },
                                set: { newValue in
                                    if let newValue {
                                        spriteContactAssignments[sprite.id] = newValue
                                    } else {
                                        spriteContactAssignments.removeValue(forKey: sprite.id)
                                    }
                                }
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle(title: "Logging")

                if !contacts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default contact")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(DetailCardPalette.bodyText)

                        Picker("Default contact", selection: $preferredContactID) {
                            ForEach(contacts) { contact in
                                Text(contact.name).tag(contact.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(DetailCardPalette.bodyText)
                        .tint(DetailCardPalette.bodyText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DetailCardPalette.surfaceStrongFill)
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle(title: "Notifications")

                if contacts.isEmpty {
                    SettingsHint(text: "Add contacts before creating call reminders.")
                } else {
                    ForEach(notificationPreferences.callReminders) { reminder in
                        CallReminderRow(
                            reminder: reminder,
                            contact: contacts.first(where: { $0.id == reminder.contactID }),
                            onToggle: { isEnabled in
                                if let index = notificationPreferences.callReminders.firstIndex(where: { $0.id == reminder.id }) {
                                    notificationPreferences.callReminders[index].isEnabled = isEnabled
                                }
                            },
                            onDelete: { onDeleteReminder(reminder) }
                        )
                    }

                    Button(action: ButtonClickSound.action(onAddReminder)) {
                        Label("Add Reminder", systemImage: "bell.badge.plus")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(DetailCardPalette.bodyText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(DetailCardPalette.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                }

                SettingsToggleRow(
                    title: "Low health alerts",
                    subtitle: "Controls system alerts when health gets low.",
                    isOn: $notificationPreferences.lowHealthAlertsEnabled
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(DetailCardPalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(DetailCardPalette.cardStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
        .environment(\.colorScheme, .light)
    }
}

private struct SettingsSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(DetailCardPalette.primaryText)
    }
}

private struct SettingsHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DetailCardPalette.mutedText)
            .padding(.vertical, 6)
    }
}

private struct ContactSettingsRow: View {
    let contact: AppContact
    let isPreferred: Bool
    let onSetPreferred: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: ButtonClickSound.action(onSetPreferred)) {
                HStack(spacing: 10) {
                    Image(systemName: isPreferred ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isPreferred ? Color(red: 0.98, green: 0.76, blue: 0.29) : Color(red: 0.56, green: 0.64, blue: 0.72))

                    Text(contact.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DetailCardPalette.bodyText)

                    Spacer(minLength: 0)

                    if isPreferred {
                        Text("Default")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.98, green: 0.63, blue: 0.36))
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: ButtonClickSound.action(onDelete)) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.88, green: 0.37, blue: 0.42))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(DetailCardPalette.surfaceFill)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
        )
    }
}

private struct ContactAssignmentRow: View {
    let sprite: TamagotchiSpriteProfile
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?

    var body: some View {
        HStack(spacing: 12) {
            PixelTamagotchi(
                health: HealthPersistence.defaultHealth,
                sprite: sprite,
                clothing: .none,
                artSize: 42,
                showsLabels: false,
                danceSpeed: .normal
            )
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(sprite.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.bodyText)

                Picker("Assigned contact", selection: $selectedContactID) {
                    Text("Unassigned").tag(nil as UUID?)
                    ForEach(contacts) { contact in
                        Text(contact.name).tag(contact.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .tint(DetailCardPalette.bodyText)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
        )
    }
}

private struct CallReminderRow: View {
    let reminder: CallReminder
    let contact: AppContact?
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color(red: 0.95, green: 0.62, blue: 0.20))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(red: 0.95, green: 0.62, blue: 0.20).opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(contact?.name ?? "Unknown contact")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.bodyText)

                Text("\(reminder.frequency.label) at \(timeText)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.mutedText)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { reminder.isEnabled },
                set: onToggle
            ))
            .labelsHidden()
            .tint(Color(red: 0.12, green: 0.76, blue: 0.60))

            Button(role: .destructive, action: ButtonClickSound.action(onDelete)) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color(red: 0.88, green: 0.24, blue: 0.28))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
        )
    }

    private var timeText: String {
        var components = DateComponents()
        components.weekday = reminder.weekday
        components.hour = reminder.hour
        components.minute = reminder.minute
        let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = reminder.frequency == .weekly ? "EEE h:mm a" : "h:mm a"
        return formatter.string(from: date)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.bodyText)
            }
            .tint(Color(red: 0.12, green: 0.76, blue: 0.60))

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DetailCardPalette.mutedText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
        )
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
                .foregroundStyle(DetailCardPalette.bodyText)

            TextField(placeholder, text: $text)
                .keyboardType(isNumeric ? .numberPad : .default)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DetailCardPalette.bodyText)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DetailCardPalette.surfaceStrongFill)
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
                    .foregroundStyle(DetailCardPalette.bodyText)

                HStack(spacing: 6) {
                    Text("\(entry.minutes) minute\(entry.minutes == 1 ? "" : "s")")

                    Circle()
                        .fill(DetailCardPalette.mutedText.opacity(0.55))
                        .frame(width: 4, height: 4)

                    Text(entry.loggedAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DetailCardPalette.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DetailCardPalette.surfaceFill)
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
                .foregroundStyle(DetailCardPalette.bodyText)
        }
    }
}

private struct ActionDock: View {
    @Binding var activePage: HomePage
    let metrics: LayoutMetrics
    let isTutorialActive: Bool
    let tutorialTarget: HomePage?
    let onLogTap: () -> Void
    let onSelectPage: (HomePage) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(HomePage.dockCases, id: \.self) { page in
                DockButton(
                    page: page,
                    isSelected: activePage == page,
                    isTutorialHighlighted: tutorialTarget == page,
                    isTutorialDimmed: isTutorialActive && tutorialTarget != page,
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
                .fill(Color.white.opacity(isTutorialActive ? 0.58 : 0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(isTutorialActive ? 0.34 : 0.60), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(isTutorialActive ? 0.06 : 0.10), radius: 18, y: 10)
    }
}

private struct DockButton: View {
    let page: HomePage
    let isSelected: Bool
    let isTutorialHighlighted: Bool
    let isTutorialDimmed: Bool
    let metrics: LayoutMetrics
    let onTap: () -> Void

    var body: some View {
        Button(action: ButtonClickSound.action(onTap)) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(dockCircleFill)
                        .frame(
                            width: isSelected ? metrics.dockSelectedSize : metrics.dockButtonSize,
                            height: isSelected ? metrics.dockSelectedSize : metrics.dockButtonSize
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isTutorialHighlighted ? 0.96 : 0), lineWidth: 4)
                                .scaleEffect(1.12)
                        )
                        .shadow(color: Color.white.opacity(isTutorialHighlighted ? 0.45 : 0), radius: 16)

                    Image(systemName: page.symbol)
                        .font(.system(size: isSelected ? 22 : 19, weight: .bold))
                        .foregroundStyle(symbolColor)
                }

                Text(page.label)
                    .font(.system(size: metrics.dockLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(isTutorialDimmed ? 0.34 : 1)
        }
        .buttonStyle(.plain)
    }

    private var dockCircleFill: Color {
        if isTutorialDimmed {
            return Color(red: 0.78, green: 0.82, blue: 0.85).opacity(0.50)
        }

        return isSelected ? page.highlightColor : .white
    }

    private var symbolColor: Color {
        if isTutorialDimmed {
            return Color(red: 0.44, green: 0.49, blue: 0.53)
        }

        return isSelected ? .white : Color(red: 0.11, green: 0.18, blue: 0.29)
    }

    private var labelColor: Color {
        if isTutorialDimmed {
            return Color(red: 0.48, green: 0.53, blue: 0.56)
        }

        return isSelected ? Color(red: 0.09, green: 0.16, blue: 0.26) : Color(red: 0.34, green: 0.44, blue: 0.50)
    }
}

private struct CircularIconButton: View {
    let systemName: String
    let diameter: CGFloat
    let iconSize: CGFloat
    let showDot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: ButtonClickSound.action(action)) {
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

private struct CallLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let contactID: UUID?
    let name: String
    let minutes: Int
    let loggedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case contactID
        case name
        case minutes
        case loggedAt
    }

    init(id: UUID = UUID(), contactID: UUID? = nil, name: String, minutes: Int, loggedAt: Date) {
        self.id = id
        self.contactID = contactID
        self.name = name
        self.minutes = minutes
        self.loggedAt = loggedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        contactID = try container.decodeIfPresent(UUID.self, forKey: .contactID)
        name = try container.decode(String.self, forKey: .name)
        minutes = try container.decode(Int.self, forKey: .minutes)
        loggedAt = try container.decode(Date.self, forKey: .loggedAt)
    }
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

    static func tier(for streakDays: Int) -> Int {
        switch streakDays {
        case 7...:
            return 3
        case 3...:
            return 2
        default:
            return 1
        }
    }

    static func foodDiscountPercent(for tier: Int) -> Int {
        switch tier {
        case 3...:
            return 20
        case 2:
            return 10
        default:
            return 0
        }
    }

    static func label(for streakDays: Int) -> String {
        switch streakDays {
        case 7...:
            return "Max"
        case 3...:
            return "\(7 - streakDays) day\(7 - streakDays == 1 ? "" : "s") to Tier 3"
        default:
            return "\(max(0, 3 - streakDays)) day\(max(0, 3 - streakDays) == 1 ? "" : "s") to Tier 2"
        }
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

private enum FeedingOption: String, CaseIterable, Identifiable {
    case once
    case fiveTimes

    var id: String { rawValue }
    private var unitCost: Int { 10 }
    private var unitHealthRestored: Double { 18 }
    private var unitExperienceGain: Int { 24 }

    var feedCount: Int {
        switch self {
        case .once:
            return 1
        case .fiveTimes:
            return 5
        }
    }

    var displayName: String {
        switch self {
        case .once:
            return "Feed x1"
        case .fiveTimes:
            return "Feed x5"
        }
    }

    var baseCost: Int {
        unitCost * feedCount
    }

    func cost(streakTier: Int) -> Int {
        let discountPercent = StreakCalculator.foodDiscountPercent(for: streakTier)
        let discountedCost = Double(baseCost) * (1 - Double(discountPercent) / 100)
        return max(1, Int(discountedCost.rounded(.up)))
    }

    var healthRestored: Double {
        unitHealthRestored * Double(feedCount)
    }

    var experienceGain: Int {
        unitExperienceGain * feedCount
    }

    var symbol: String {
        switch self {
        case .once:
            return "takeoutbag.and.cup.and.straw.fill"
        case .fiveTimes:
            return "fork.knife.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .once:
            return Color(red: 0.94, green: 0.58, blue: 0.25)
        case .fiveTimes:
            return Color(red: 0.18, green: 0.64, blue: 0.52)
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

    var animationSpeedMultiplier: Double {
        switch self {
        case .chill:
            return 0.5  // Half speed = 0.5x fps
        case .normal:
            return 1.0  // Normal speed
        case .turbo:
            return 2.0  // Double speed = 2x fps
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

    var pipeColor: Color {
        switch self {
        case .meadow:
            return Color(red: 0.15, green: 0.63, blue: 0.46)
        case .sunset:
            return Color(red: 0.79, green: 0.41, blue: 0.32)
        case .moonlight:
            return Color(red: 0.33, green: 0.48, blue: 0.74)
        }
    }
}

private enum HomePage: CaseIterable {
    case home
    case upgrades
    case settings
    case log

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
        }
    }
}

private struct SpriteLevel: Codable, Equatable {
    let spriteID: String
    var level: Int
    var experienceInLevel: Int

    init(spriteID: String, level: Int = 1, experienceInLevel: Int = 0) {
        self.spriteID = spriteID
        self.level = max(1, level)
        self.experienceInLevel = max(0, experienceInLevel)
        normalize()
    }

    mutating func addExperience(_ amount: Int) -> Bool {
        guard amount > 0 else { return false }

        let startingLevel = level
        experienceInLevel += amount
        normalize()
        return level > startingLevel
    }

    func progressToNextLevel() -> Double {
        let required = Double(experienceForNextLevel())
        guard required > 0 else { return 1 }
        return min(max(Double(experienceInLevel) / required, 0), 1)
    }

    private mutating func normalize() {
        while experienceInLevel >= experienceForNextLevel() {
            experienceInLevel -= experienceForNextLevel()
            level += 1
        }
    }

    private func experienceForNextLevel() -> Int {
        // Gradual, predictable curve: 100, 130, 160, ...
        100 + max(0, (level - 1) * 30)
    }
}

private enum LevelPersistence {
    private static let storageKey = "sprite.levels"

    static func load() -> [String: SpriteLevel] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let levels = try? JSONDecoder().decode([String: SpriteLevel].self, from: data)
        else {
            return [:]
        }

        let migratedLevels = SpriteIDMigration.migratedLevels(levels)
        if migratedLevels != levels {
            save(migratedLevels)
        }
        return migratedLevels
    }

    static func save(_ levels: [String: SpriteLevel]) {
        let migratedLevels = SpriteIDMigration.migratedLevels(levels)
        guard let encoded = try? JSONEncoder().encode(migratedLevels) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}

private struct PixelLevelBadge: View {
    let level: Int
    let experienceProgress: Double
    var showsProgress: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LV \(level)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.75))
                )

            if showsProgress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.25))
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.30, green: 0.84, blue: 0.54))
                            .frame(width: geometry.size.width * experienceProgress)
                    }
                }
                .frame(width: 44, height: 5)
            }
        }
    }
}

private extension TamagotchiSpriteProfile {
    var currencyTint: Color {
        switch id.lowercased() {
        case "t1", "slime":
            return Color(red: 0.49, green: 0.85, blue: 0.13)
        case "imp":
            return Color(red: 0.90, green: 0.16, blue: 0.20)
        case "t2", "cecil":
            return Color(red: 0.18, green: 0.48, blue: 0.95)
        case "ghost":
            return Color(red: 0.16, green: 0.17, blue: 0.19)
        default:
            return currencyTintFromName
        }
    }

    private var currencyTintFromName: Color {
        switch displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "slime":
            return Color(red: 0.49, green: 0.85, blue: 0.13)
        case "imp":
            return Color(red: 0.90, green: 0.16, blue: 0.20)
        case "cecil":
            return Color(red: 0.18, green: 0.48, blue: 0.95)
        case "ghost":
            return Color(red: 0.16, green: 0.17, blue: 0.19)
        default:
            return Color(red: 0.94, green: 0.62, blue: 0.18)
        }
    }
}
