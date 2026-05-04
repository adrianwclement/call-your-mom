//
//  DashboardView.swift
//  call-your-mom
//
//  Created by Ben Cerbin, Adrian Clement, and Dylan O'Connor on 4/21/26.
//

import SwiftUI
import Contacts
import ContactsUI
internal import Combine

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var activePage: HomePage = .home
    @State private var pageHistory: [HomePage] = []
    @State private var quickActionsExpanded = false
    @State private var health = HealthPersistence.defaultHealth
    @State private var callsLogged = HealthPersistence.defaultCallsLogged
    @State private var contacts = SettingsPersistence.defaultSettings.contacts
    @State private var preferredContactID = SettingsPersistence.defaultSettings.preferredContactID
    @State private var selectedLogContactID = SettingsPersistence.defaultSettings.preferredContactID
    @State private var pendingContactName = ""
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
    @State private var selectedTheme: AppTheme = .meadow
    @State private var streakDays: Int = 0
    @State private var isContactPickerPresented = false
    @State private var pendingCallSession: PendingCallSession?
    @State private var postCallPrompt: PendingCallSession?
    @State private var callFailureMessage: String?
    @State private var isReminderPickerPresented = false
    @State private var reminderDraftDate = Date()
    @State private var isDefaultContactPickerPresented = false
    @State private var selectedDefaultContactDraftID: UUID?
    @State private var isWalkthroughPresented = false
    @State private var walkthroughIndex = 0
    @State private var isGameMode = false
    @State private var isLaunchingGame = false
    @State private var gameEntryProgress: CGFloat = 0
    @State private var activeHomePanelIndex = 1
    @State private var homeDragTranslation: CGFloat = 0
    private let decayTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var notifications: [InboxItem] {
        buildNotifications()
    }

    private var streakTier: Int {
        StreakCalculator.tier(for: streakDays)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = LayoutMetrics(container: geometry.size, safeArea: geometry.safeAreaInsets)
            let showingGame = activePage == .home && (isGameMode || isLaunchingGame)

            ZStack {
                AppSkyBackground(theme: selectedTheme)

                AppSceneBackground(theme: selectedTheme)

                if showingGame {
                    FlappyTamagotchiGameView(
                        theme: selectedTheme,
                        health: health,
                        sprite: selectedSprite,
                        clothing: selectedClothing,
                        birdVisible: !isLaunchingGame,
                        onExit: exitGameMode
                    )
                    .allowsHitTesting(isGameMode)
                    .opacity(isLaunchingGame ? gameEntryProgress : 1)
                    .scaleEffect(isLaunchingGame ? 0.96 + (gameEntryProgress * 0.04) : 1)
                    .zIndex(0)
                }

                VStack(spacing: metrics.sectionSpacing) {
                    HomeTopBar(
                        metrics: metrics,
                        isBackVisible: activePage != .home,
                        isQuickActionsExpanded: quickActionsExpanded,
                        hasNotifications: !notifications.isEmpty,
                        onTitleTap: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                quickActionsExpanded.toggle()
                            }
                        },
                        onBack: goBack,
                        onWalkthrough: restartWalkthrough,
                        onInbox: { navigate(to: .inbox) }
                    )
                    .padding(.top, metrics.topPadding)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .opacity(showingGame ? 0 : 1)
                    .offset(y: showingGame ? -80 : 0)
                    .allowsHitTesting(!showingGame)

                    Group {
                        if activePage == .home {
                            homeView(metrics: metrics, isShowingGame: showingGame, isLaunchingGame: isLaunchingGame)
                        } else {
                            detailPage(metrics: metrics, page: activePage)
                        }
                    }
                    .offset(y: showingGame ? 120 : 0)
                    .opacity(showingGame ? 0 : 1)
                    .allowsHitTesting(!showingGame)
                }

                if activePage == .home && isLaunchingGame {
                    LaunchingGameSpriteOverlay(
                        containerSize: geometry.size,
                        metrics: metrics,
                        progress: gameEntryProgress,
                        health: health,
                        sprite: selectedSprite,
                        clothing: selectedClothing
                    )
                    .allowsHitTesting(false)
                    .zIndex(2)
                }

                if isWalkthroughPresented && !showingGame {
                    WalkthroughOverlay(
                        metrics: metrics,
                        step: WalkthroughStep.allCases[walkthroughIndex],
                        currentIndex: walkthroughIndex,
                        totalCount: WalkthroughStep.allCases.count,
                        onNext: advanceWalkthrough,
                        onSkip: finishWalkthrough
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(4)
                }

            }
            .safeAreaInset(edge: .bottom) {
                if !showingGame {
                    ActionDock(
                        activePage: $activePage,
                        metrics: metrics,
                        isTutorialActive: isWalkthroughPresented,
                        tutorialTarget: isWalkthroughPresented ? WalkthroughStep.allCases[walkthroughIndex].dockTarget : nil,
                        onLogTap: { navigate(to: .log) },
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .transaction { transaction in
                        if isWalkthroughPresented {
                            transaction.animation = nil
                        }
                    }
                    .allowsHitTesting(!isWalkthroughPresented)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                healthPulse = true
            }
            reloadSpriteCatalog()
            restoreAppState()
            LocalNotificationManager.shared.requestAuthorization()
            restorePersistedHealth()
            restoreSettings()
            restorePendingCallTracking()
            refreshStreakDays()
            syncNotificationSchedules()
            presentPostCallPromptIfReady()
            startWalkthroughIfNeeded()
        }
        .onReceive(decayTimer) { _ in
            guard scenePhase == .active else { return }
            applyElapsedDecay(now: Date())
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                reloadSpriteCatalog()
                restorePersistedHealth()
                restoreSettings()
                restorePendingCallTracking()
                presentPostCallPromptIfReady()
            } else if newValue == .background || newValue == .inactive {
                persistHealthState()
                persistAppState()
                persistSettings()
                persistPendingCallTracking()
                syncLowHealthNotification()
            }
        }
        .onChange(of: health) { _, _ in
            persistHealthState()
            syncLowHealthNotification()
        }
        .onChange(of: callLogs) { _, _ in
            AppStatePersistence.saveCallLogs(callLogs)
        }
        .onChange(of: selectedSprite) { _, _ in
            AppStatePersistence.saveSelectedSpriteID(selectedSprite.id)
        }
        .onChange(of: contacts) { _, _ in
            sanitizeContactsAfterMutation()
            persistSettings()
            syncNotificationSchedules()
        }
        .onChange(of: preferredContactID) { _, _ in
            if selectedLogContactID == nil || !contacts.contains(where: { $0.id == selectedLogContactID }) {
                selectedLogContactID = preferredContactID
            }
            persistSettings()
            syncNotificationSchedules()
        }
        .onChange(of: notificationPreferences) { _, _ in
            persistSettings()
            syncNotificationSchedules()
        }
        .onChange(of: defaultCallMinutes) { _, _ in
            defaultCallMinutes = min(max(defaultCallMinutes, 1), 240)
            if logMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logMinutes = String(defaultCallMinutes)
            }
            persistSettings()
            syncNotificationSchedules()
        }
        .sheet(isPresented: $isContactPickerPresented) {
            SystemContactPicker { contact in
                importSystemContact(contact)
            }
        }
        .sheet(isPresented: $isReminderPickerPresented) {
            ReminderTimePickerSheet(
                selectedDate: $reminderDraftDate,
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
        .alert(
            "Log your call?",
            isPresented: Binding(
                get: { postCallPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        postCallPrompt = nil
                    }
                }
            ),
            presenting: postCallPrompt
        ) { session in
            Button("Save \(estimatedMinutes(for: session)) min") {
                savePendingCall(session)
            }

            Button("Review") {
                reviewPendingCall(session)
            }

            Button("Later", role: .cancel) {
                postCallPrompt = nil
            }
        } message: { session in
            Text("Add your call with \(session.contactName) so your Tamagotchi gets credit.")
        }
        .alert(
            "Can't Start Call",
            isPresented: Binding(
                get: { callFailureMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        callFailureMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                callFailureMessage = nil
            }
        } message: {
            Text(callFailureMessage ?? "")
        }
    }

    @ViewBuilder
    private func homeView(metrics: LayoutMetrics, isShowingGame: Bool, isLaunchingGame: Bool) -> some View {
        GeometryReader { geometry in
            let panelWidth = geometry.size.width
            let baseOffset = CGFloat(activeHomePanelIndex) * panelWidth
            let currentOffset = min(max(baseOffset - homeDragTranslation, 0), panelWidth * 2)

            HStack(spacing: 0) {
                SpriteSelectionGridView(
                    sprites: availableSprites,
                    selectedSprite: selectedSprite,
                    selectedClothing: selectedClothing,
                    health: health,
                    selectedDanceSpeed: selectedDanceSpeed,
                    onSelectSprite: { sprite in
                        selectedSprite = sprite
                    }
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
                            health: health,
                            isAnimating: healthPulse,
                            isTutorialHighlighted: isWalkthroughPresented && WalkthroughStep.allCases[walkthroughIndex].focus == .healthBar
                        )

                        IntegratedTamagotchiStage(
                            health: health,
                            sprite: selectedSprite,
                            clothing: selectedClothing,
                            danceSpeed: selectedDanceSpeed,
                            isGameMode: isShowingGame,
                            hidesSprite: isLaunchingGame,
                            onLaunchGame: enterGameMode
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.contentBottomPadding)
                    .frame(maxWidth: .infinity, minHeight: metrics.minContentHeight)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: panelWidth)
                .frame(minHeight: metrics.minContentHeight)

                PixelGardenPlaygroundView(
                    sprites: availableSprites,
                    selectedClothing: selectedClothing
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, metrics.contentBottomPadding)
                .frame(width: panelWidth)
                .frame(minHeight: metrics.minContentHeight)
            }
            .offset(x: -currentOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isShowingGame else { return }
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        homeDragTranslation = value.translation.width
                    }
                    .onEnded { value in
                        guard !isShowingGame else { return }
                        guard abs(value.translation.width) >= abs(value.translation.height) else {
                            withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.12)) {
                                homeDragTranslation = 0
                            }
                            return
                        }
                        let velocityDelta = value.predictedEndTranslation.width - value.translation.width
                        let projectedOffset = min(max(baseOffset - value.translation.width - (velocityDelta * 0.2), 0), panelWidth * 2)
                        let resolvedPanel = Int((projectedOffset / panelWidth).rounded())
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

    private func logCall(name: String, minutes: Int) {
        applyElapsedDecay(now: Date())
        callsLogged += 1
        callLogs.insert(CallLogEntry(name: name, minutes: minutes, loggedAt: Date()), at: 0)
        refreshStreakDays()

        let durationHealing = min(max(Double(minutes) * 1.5, 18), 45)
        let streakBonus = Double(streakTier * 4)
        let healingAmount = durationHealing + streakBonus
        health = min(health + healingAmount, 100)
        selectedLogContactID = preferredContactID
        logMinutes = String(defaultCallMinutes)
        lastHealthUpdatedAt = Date()
        clearPendingCallTracking()
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
                        defaultCallMinutes: defaultCallMinutes,
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
                        pendingContactName: $pendingContactName,
                        notificationPreferences: $notificationPreferences,
                        reminderTime: reminderDateBinding,
                        defaultCallMinutes: $defaultCallMinutes,
                        onAddContact: addContact,
                        onImportContact: { isContactPickerPresented = true },
                        onDeleteContact: deleteContact
                    )
                } else {
                    DetailPageCard(
                        page: page,
                        items: notifications,
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

        logCall(name: contact.name, minutes: minutes)
    }

    private func selectRecentLogEntry(_ entry: CallLogEntry) {
        if let matchingContact = contacts.first(where: { contact in
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

        if let existing = loadedSprites.first(where: { $0.id == selectedSprite.id }) {
            selectedSprite = existing
        } else {
            selectedSprite = TamagotchiSpriteCatalog.preferredInitialSprite(from: loadedSprites)
        }
    }

    private func restoreAppState() {
        callLogs = AppStatePersistence.loadCallLogs()
        restoreSelectedSprite()
    }

    private func persistAppState() {
        AppStatePersistence.saveCallLogs(callLogs)
        AppStatePersistence.saveSelectedSpriteID(selectedSprite.id)
    }

    private func restoreSelectedSprite() {
        guard let selectedSpriteID = AppStatePersistence.loadSelectedSpriteID() else { return }
        guard let persistedSprite = availableSprites.first(where: { $0.id == selectedSpriteID }) else { return }
        selectedSprite = persistedSprite
    }

    private func refreshStreakDays() {
        streakDays = StreakCalculator.currentStreak(from: callLogs)
    }

    private func restoreSettings() {
        let settings = SettingsPersistence.load()
        contacts = settings.contacts
        preferredContactID = settings.preferredContactID
        defaultCallMinutes = settings.defaultCallMinutes
        notificationPreferences = settings.notificationPreferences
        selectedLogContactID = settings.preferredContactID ?? settings.contacts.first?.id

        if logMinutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logMinutes = String(settings.defaultCallMinutes)
        }
    }

    private func persistSettings() {
        SettingsPersistence.save(
            AppSettings(
                contacts: contacts,
                preferredContactID: preferredContactID,
                defaultCallMinutes: defaultCallMinutes,
                notificationPreferences: notificationPreferences
            )
        )
    }

    private func addContact() {
        let trimmedName = pendingContactName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        upsertContact(name: trimmedName, phoneNumber: nil)
        pendingContactName = ""
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
            fallbackMinutes: defaultCallMinutes
        )
        persistPendingCallTracking()
        selectedLogContactID = contact.id
        logMinutes = String(defaultCallMinutes)
        LocalNotificationManager.shared.schedulePostCallLogReminder(
            contactName: contact.name,
            after: max(300, TimeInterval(defaultCallMinutes * 60 + 60))
        )
        openURL(url) { accepted in
            guard !accepted else { return }
            clearPendingCallTracking()
            callFailureMessage = "This device or simulator can't place phone calls from the app. Try again on an iPhone with calling available."
        }
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
        logMinutes = String(defaultCallMinutes)

        guard let phoneNumber = preferredContact.phoneNumber, !phoneNumber.digitsOnly.isEmpty else {
            callFailureMessage = "Your default contact needs a phone number before Call now can start a call."
            navigate(to: .settings)
            return
        }

        callContact(preferredContact)
    }

    private func handleSetReminderQuickAction() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            quickActionsExpanded = false
        }

        notificationPreferences.dailyRemindersEnabled = true
        reminderDraftDate = reminderDateBinding.wrappedValue
        isReminderPickerPresented = true
    }

    private func applyReminderDraft() {
        reminderDateBinding.wrappedValue = reminderDraftDate
        notificationPreferences.dailyRemindersEnabled = true
        isReminderPickerPresented = false
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

    private func presentPostCallPromptIfReady() {
        guard let session = pendingCallSession else { return }

        let secondsSinceCallStarted = Date().timeIntervalSince(session.startedAt)
        guard secondsSinceCallStarted >= 20 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (20 - secondsSinceCallStarted)) {
                guard scenePhase == .active else { return }
                presentPostCallPromptIfReady()
            }
            return
        }

        selectedLogContactID = session.contactID
        logMinutes = String(estimatedMinutes(for: session))
        postCallPrompt = session
    }

    private func savePendingCall(_ session: PendingCallSession) {
        logCall(name: session.contactName, minutes: estimatedMinutes(for: session))
    }

    private func reviewPendingCall(_ session: PendingCallSession) {
        selectedLogContactID = session.contactID
        logMinutes = String(estimatedMinutes(for: session))
        postCallPrompt = nil
        navigate(to: .log)
    }

    private func estimatedMinutes(for session: PendingCallSession) -> Int {
        let elapsedMinutes = Int(ceil(Date().timeIntervalSince(session.startedAt) / 60))
        return max(1, elapsedMinutes == 0 ? session.fallbackMinutes : elapsedMinutes)
    }

    private func clearPendingCallTracking() {
        pendingCallSession = nil
        postCallPrompt = nil
        PendingCallPersistence.clear()
        LocalNotificationManager.shared.clearPostCallLogReminder()
    }

    private func restorePendingCallTracking() {
        guard pendingCallSession == nil else { return }
        pendingCallSession = PendingCallPersistence.load()
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
    }

    private func syncNotificationSchedules() {
        if notificationPreferences.dailyRemindersEnabled, let contact = preferredContact {
            LocalNotificationManager.shared.scheduleDailyReminder(
                hour: notificationPreferences.reminderHour,
                minute: notificationPreferences.reminderMinute,
                contactName: contact.name,
                minutes: defaultCallMinutes
            )
        } else {
            LocalNotificationManager.shared.clearDailyReminderNotification()
        }

        syncLowHealthNotification()
    }

    private func buildNotifications() -> [InboxItem] {
        var items: [InboxItem] = []
        let focusName = preferredContact?.name ?? contacts.first?.name ?? "your favorite person"

        if notificationPreferences.dailyRemindersEnabled {
            items.append(
                InboxItem(
                    title: "Daily reminder set for \(formattedReminderHour)",
                    subtitle: "Check in with \(focusName) for about \(defaultCallMinutes) minute\(defaultCallMinutes == 1 ? "" : "s").",
                    kind: .reminder
                )
            )
        }

        if notificationPreferences.streakAlertsEnabled {
            let streakTitle = streakDays > 0 ? "\(streakDays)-day streak active" : "Start a new streak today"
            let streakSubtitle = streakDays > 0
                ? "One more call keeps your streak with \(focusName) moving."
                : "Log one call today to get momentum going."

            items.append(InboxItem(title: streakTitle, subtitle: streakSubtitle, kind: .streak))
        }

        if notificationPreferences.messageAlertsEnabled, !contacts.isEmpty {
            items.append(
                InboxItem(
                    title: "\(focusName) replied",
                    subtitle: "Call me when you get a minute.",
                    kind: .message
                )
            )
        }

        if notificationPreferences.weeklySummaryEnabled {
            let weeklyStats = weeklySummary()
            items.append(
                InboxItem(
                    title: "Weekly recap: \(weeklyStats.callCount) call\(weeklyStats.callCount == 1 ? "" : "s"), \(weeklyStats.totalMinutes) minutes",
                    subtitle: weeklyStats.subtitle,
                    kind: .summary
                )
            )
        }

        if notificationPreferences.lowHealthAlertsEnabled, health <= LocalNotificationManager.lowHealthThreshold {
            items.append(
                InboxItem(
                    title: "Health is getting low",
                    subtitle: "Log a call soon to recharge your Tamagotchi.",
                    kind: .health
                )
            )
        }

        return items
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

    private var formattedReminderHour: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let components = DateComponents(
            hour: notificationPreferences.reminderHour,
            minute: notificationPreferences.reminderMinute
        )
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    private var reminderDateBinding: Binding<Date> {
        Binding(
            get: {
                let components = DateComponents(
                    hour: notificationPreferences.reminderHour,
                    minute: notificationPreferences.reminderMinute
                )
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                notificationPreferences.reminderHour = components.hour ?? notificationPreferences.reminderHour
                notificationPreferences.reminderMinute = components.minute ?? notificationPreferences.reminderMinute
            }
        )
    }

    private func navigate(to page: HomePage) {
        if isGameMode {
            exitGameMode()
        }
        guard page != activePage else { return }
        pageHistory.append(activePage)
        activePage = page
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
            finishWalkthrough()
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            walkthroughIndex = nextIndex
            showWalkthroughStep(at: nextIndex)
        }
    }

    private func finishWalkthrough() {
        WalkthroughPersistence.markCompleted()
        withAnimation(.easeInOut(duration: 0.2)) {
            isWalkthroughPresented = false
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
        quickActionsExpanded = false
        gameEntryProgress = 0

        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
            isLaunchingGame = true
        }

        withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
            gameEntryProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            guard isLaunchingGame else { return }
            isGameMode = true
            isLaunchingGame = false
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

    init(
        id: UUID = UUID(),
        contactID: UUID,
        contactName: String,
        startedAt: Date,
        fallbackMinutes: Int
    ) {
        self.id = id
        self.contactID = contactID
        self.contactName = contactName
        self.startedAt = startedAt
        self.fallbackMinutes = fallbackMinutes
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
        UserDefaults.standard.string(forKey: selectedSpriteIDKey)
    }

    static func saveSelectedSpriteID(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedSpriteIDKey)
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
            return "Log Calls Fast"
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
            return "Your Tamagotchi stays healthy when you make time for real calls."
        case .health:
            return "The health bar changes color as it drops. Logging a call heals your companion."
        case .logCall:
            return "Use the Log tab to save a call, reuse recent entries, or call an imported contact."
        case .contacts:
            return "Settings lets you import iPhone contacts, choose a default person, and tune reminders."
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
                            .padding(.bottom, 42)
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
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(DetailCardPalette.mutedText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                Button(action: onNext) {
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

private struct AppSkyBackground: View {
    let theme: AppTheme

    var body: some View {
        LinearGradient(
            colors: [theme.primary, theme.secondary, theme.tertiary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
    let hasNotifications: Bool
    let onTitleTap: () -> Void
    let onBack: () -> Void
    let onWalkthrough: () -> Void
    let onInbox: () -> Void

    var body: some View {
        HStack {
            if isBackVisible {
                CircularIconButton(systemName: "arrow.left", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: false, action: onBack)
            } else {
                CircularIconButton(systemName: "info.circle.fill", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: false, action: onWalkthrough)
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

            CircularIconButton(systemName: "bell.badge.fill", diameter: metrics.topButtonSize, iconSize: metrics.topIconSize, showDot: hasNotifications, action: onInbox)
        }
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
                        width: max(28, geometry.size.width * (clampedHealth / 100)),
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
                    .shadow(color: glowColor.opacity(0.24), radius: isAnimating ? 8 : 4)
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

private struct ReminderTimePickerSheet: View {
    @Binding var selectedDate: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pick a daily reminder time for your next check-in.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DetailCardPalette.secondaryText)

                DatePicker(
                    "Reminder time",
                    selection: $selectedDate,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .fontWeight(.bold)
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
        Button(action: action) {
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
    let isGameMode: Bool
    let hidesSprite: Bool
    let onLaunchGame: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if !hidesSprite {
                PixelTamagotchi(
                    health: health,
                    sprite: sprite,
                    clothing: clothing,
                    danceSpeed: danceSpeed
                )
                .offset(y: 50)
            }

            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 120, height: 20)
                .blur(radius: 4)
                .offset(y: 20)

            if !isGameMode {
                VStack {
                    Spacer()

                    Button(action: onLaunchGame) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .black))
                            Text("Play")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.84))
                        )
                    }
                    .buttonStyle(.plain)
                    .offset(y: 54)
                }
            }
        }
        .frame(height: 300)
    }

}

private struct SpriteSelectionGridView: View {
    let sprites: [TamagotchiSpriteProfile]
    let selectedSprite: TamagotchiSpriteProfile
    let selectedClothing: ClothingOption
    let health: Double
    let selectedDanceSpeed: DanceSpeed
    let onSelectSprite: (TamagotchiSpriteProfile) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Sprite")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.09, green: 0.16, blue: 0.26))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sprites) { sprite in
                        Button(action: { onSelectSprite(sprite) }) {
                            VStack(spacing: 8) {
                                PixelTamagotchi(
                                    health: health,
                                    sprite: sprite,
                                    clothing: selectedClothing,
                                    artSize: 96,
                                    showsLabels: false,
                                    showsBadge: false,
                                    danceSpeed: selectedDanceSpeed
                                )
                                Text(sprite.displayName)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.09, green: 0.16, blue: 0.26))
                                    .lineLimit(1)
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
        }
    }
}

private struct PixelGardenPlaygroundView: View {
    let sprites: [TamagotchiSpriteProfile]
    let selectedClothing: ClothingOption

    @State private var pets: [GardenPet] = []
    @State private var lastTick = Date()
    private let tickTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let shelfRatios: [CGFloat] = [0.30, 0.50, 0.70]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shelfYs = shelfRatios.map { size.height * $0 }
            let floorY = size.height * 0.84

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.42))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pixel Garden")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.24))
                    Text("Swipe back to home. Plants coming soon.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.31, green: 0.45, blue: 0.50))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ForEach(Array(shelfYs.enumerated()), id: \.offset) { index, y in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.56, green: 0.40, blue: 0.25).opacity(0.80))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.34), lineWidth: 1)
                        )
                        .frame(width: size.width - 28, height: 12)
                        .position(x: size.width / 2, y: y)

                    if index < shelfYs.count - 1 {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.51, green: 0.36, blue: 0.23).opacity(0.85))
                            .frame(width: 10, height: shelfYs[index + 1] - y)
                            .position(x: 24, y: y + ((shelfYs[index + 1] - y) / 2))
                    }
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.45, green: 0.34, blue: 0.22).opacity(0.92))
                    .frame(width: size.width - 28, height: 16)
                    .position(x: size.width / 2, y: floorY)

                ForEach($pets) { $pet in
                    PixelTamagotchi(
                        health: 100,
                        sprite: pet.sprite,
                        clothing: selectedClothing,
                        artSize: 66,
                        showsLabels: false,
                        showsBadge: false
                    )
                    .rotationEffect(.degrees(Double(max(-18, min(18, pet.velocity.width * 0.03)))))
                    .position(pet.position)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                pet.isHeld = true
                                pet.position = value.location
                            }
                            .onEnded { value in
                                pet.isHeld = false
                                let deltaX = value.predictedEndLocation.x - value.location.x
                                let deltaY = value.predictedEndLocation.y - value.location.y
                                pet.velocity = CGSize(width: deltaX * 2.4, height: deltaY * 2.4)
                            }
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .onAppear {
                if pets.isEmpty || pets.map(\.sprite.id) != sprites.map(\.id) {
                    let initialSprites = sprites.isEmpty ? [TamagotchiSpriteCatalog.defaultSprite] : sprites
                    pets = initialSprites.enumerated().map { index, sprite in
                        let shelf = index % shelfYs.count
                        return GardenPet(
                            sprite: sprite,
                            position: CGPoint(x: CGFloat.random(in: 70...(max(80, size.width - 70))), y: shelfYs[shelf] - 36),
                            velocity: CGSize(width: CGFloat.random(in: -20...20), height: 0),
                            shelfIndex: shelf
                        )
                    }
                }
                lastTick = Date()
            }
            .onReceive(tickTimer) { now in
                let dt = min(max(now.timeIntervalSince(lastTick), 0), 1.0 / 20.0)
                lastTick = now
                guard !pets.isEmpty else { return }

                for index in pets.indices {
                    if pets[index].isHeld { continue }

                    pets[index].velocity.height += CGFloat(900 * dt)
                    pets[index].position.x += pets[index].velocity.width * CGFloat(dt)
                    pets[index].position.y += pets[index].velocity.height * CGFloat(dt)

                    let left = CGFloat(38)
                    let right = max(left + 1, size.width - 38)
                    if pets[index].position.x < left {
                        pets[index].position.x = left
                        pets[index].velocity.width = abs(pets[index].velocity.width) * 0.7
                    } else if pets[index].position.x > right {
                        pets[index].position.x = right
                        pets[index].velocity.width = -abs(pets[index].velocity.width) * 0.7
                    }

                    let shelfLandingY = shelfYs[pets[index].shelfIndex] - 36
                    if pets[index].position.y > floorY - 38 {
                        pets[index].position.y = floorY - 38
                        pets[index].velocity.height = 0
                        pets[index].velocity.width = max(-80, min(80, pets[index].velocity.width))
                    } else if pets[index].position.y >= shelfLandingY && pets[index].velocity.height > 0 {
                        pets[index].position.y = shelfLandingY
                        pets[index].velocity.height = 0
                        if abs(pets[index].velocity.width) < 8 {
                            pets[index].velocity.width = CGFloat.random(in: -35...35)
                        }
                    }
                }
            }
        }
    }
}

private struct GardenPet: Identifiable {
    let id = UUID()
    let sprite: TamagotchiSpriteProfile
    var position: CGPoint
    var velocity: CGSize
    var shelfIndex: Int
    var isHeld = false
}

private struct PixelTamagotchi: View {
    let health: Double
    let sprite: TamagotchiSpriteProfile
    let clothing: ClothingOption
    var artSize: CGFloat = 200
    var showsLabels: Bool = true
    var showsBadge: Bool = true
    var danceSpeed: DanceSpeed = .normal

    var body: some View {
        VStack(spacing: showsLabels ? 10 : 0) {
            ZStack(alignment: .topTrailing) {
                if let atlas = sprite.atlas {
                    TimelineView(.animation(minimumInterval: frameInterval(for: atlas), paused: false)) { context in
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

                if showsBadge {
                    Image(systemName: sprite.badgeSymbol)
                        .font(.system(size: max(12, artSize * 0.11), weight: .black))
                        .foregroundStyle(sprite.badgeColor)
                        .offset(x: -8, y: 6)
                }
            }

            if showsLabels {

                Text(sprite.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
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
        // Apply dance speed multiplier inversely (faster speed = shorter interval)
        return baseInterval / danceSpeed.animationSpeedMultiplier
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
        let adjustedInterval = atlas.idleAnimation.frameInterval / danceSpeed.animationSpeedMultiplier
        return Int(date.timeIntervalSinceReferenceDate / adjustedInterval)
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
    let onExit: () -> Void

    @State private var birdY: CGFloat = 0
    @State private var birdVelocity: CGFloat = 0
    @State private var pipes: [FlappyPipe] = []
    @State private var score = 0
    @State private var hasStarted = false
    @State private var isGameOver = false
    @State private var lastTick = Date()

    private let gameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            let sceneFrame = FlappyGameLayout.sceneFrame(in: containerSize)
            let sceneSize = sceneFrame.size

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
                        y: birdY
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 8)
                }

                VStack(spacing: 18) {
                    HStack(alignment: .center) {
                        ScorePill(score: score)
                        Spacer()
                        Button(action: onExit) {
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
                            subtitle: "Tap to restart the run."
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

        birdVelocity = -285
    }

    private func update(now: Date, in size: CGSize) {
        if birdY == 0 {
            birdY = FlappyGameLayout.birdSpawnY(for: size)
            lastTick = now
        }

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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 13, weight: .black))
            Text("\(score)")
                .font(.system(size: 16, weight: .black, design: .rounded))
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
    let items: [InboxItem]
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

            Text(page.description)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DetailCardPalette.secondaryText)

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
            Text("Clothing")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ClothingOption.allCases) { clothing in
                    Button(action: { selectedClothing = clothing }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(clothing.color)
                                .frame(width: 12, height: 12)
                            Text(clothing.displayName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DetailCardPalette.bodyText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedClothing == clothing ? clothing.color.opacity(0.25) : DetailCardPalette.surfaceFill)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Dance Speed")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

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

            Text("Effect: +\(streakTier * 4) health per call. Keep logging calls daily to raise this tier.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.52))

            Text("Themes")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

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

private struct LogPageCard: View {
    let contacts: [AppContact]
    @Binding var selectedContactID: UUID?
    @Binding var minutes: String
    let defaultCallMinutes: Int
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

            Text("Add who you called and how long you talked so the dashboard can track your recent check-ins.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DetailCardPalette.secondaryText)

            RecentLogShortcuts(entries: entries, onSelect: onSelectRecent)

            if contacts.isEmpty {
                EmptyLogStateCard(onImportContact: onImportContact, onOpenSettings: onOpenSettings)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ContactPickerField(contacts: contacts, selectedContactID: $selectedContactID)

                    HStack(spacing: 10) {
                        Button(action: onImportContact) {
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
                            Button(action: { onCallContact(selectedContact) }) {
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

                    LogInputField(
                        title: "Minutes",
                        placeholder: String(defaultCallMinutes),
                        text: $minutes,
                        isNumeric: true
                    )

                    Button(action: onSubmit) {
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
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Calls")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(DetailCardPalette.primaryText)

                ForEach(entries) { entry in
                    CallLogRow(entry: entry)
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
                Button(action: onImportContact) {
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

                Button(action: onOpenSettings) {
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
                        Button(action: { onSelect(entry) }) {
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
    @Binding var pendingContactName: String
    @Binding var notificationPreferences: NotificationPreferences
    @Binding var reminderTime: Date
    @Binding var defaultCallMinutes: Int
    let onAddContact: () -> Void
    let onImportContact: () -> Void
    let onDeleteContact: (AppContact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(DetailCardPalette.primaryText)

            Text("Manage the people you track, how the app reminds you, and a few defaults that shape the logging flow.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DetailCardPalette.secondaryText)

            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionTitle(title: "Contacts")

                HStack(spacing: 10) {
                    TextField("Add a contact", text: $pendingContactName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DetailCardPalette.bodyText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DetailCardPalette.surfaceStrongFill)
                        )

                    Button(action: onAddContact) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color(red: 0.12, green: 0.76, blue: 0.60))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onImportContact) {
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
                    SettingsHint(text: "Add at least one contact to enable the call log.")
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
                SettingsSectionTitle(title: "Logging Defaults")

                Stepper(value: $defaultCallMinutes, in: 1...240) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default call length: \(defaultCallMinutes) minute\(defaultCallMinutes == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(DetailCardPalette.bodyText)

                        Text("New log entries start from this value so you can save faster.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DetailCardPalette.mutedText)
                    }
                }
                .tint(DetailCardPalette.bodyText)

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

                SettingsToggleRow(
                    title: "Daily reminders",
                    subtitle: "Shows a reminder card in Inbox and schedules a local reminder.",
                    isOn: $notificationPreferences.dailyRemindersEnabled
                )

                if notificationPreferences.dailyRemindersEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminder time")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(DetailCardPalette.bodyText)

                        DatePicker(
                            "Reminder time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
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

                SettingsToggleRow(
                    title: "Low health alerts",
                    subtitle: "Adds a low-health warning to Inbox and controls system alerts.",
                    isOn: $notificationPreferences.lowHealthAlertsEnabled
                )
                SettingsToggleRow(
                    title: "Streak celebrations",
                    subtitle: "Keeps streak updates visible in Inbox.",
                    isOn: $notificationPreferences.streakAlertsEnabled
                )
                SettingsToggleRow(
                    title: "Message updates",
                    subtitle: "Shows friendly reply-style nudges from your default contact.",
                    isOn: $notificationPreferences.messageAlertsEnabled
                )
                SettingsToggleRow(
                    title: "Weekly recap",
                    subtitle: "Surfaces your running weekly summary in Inbox.",
                    isOn: $notificationPreferences.weeklySummaryEnabled
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
            Button(action: onSetPreferred) {
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

            Button(action: onDelete) {
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

                Text("\(entry.minutes) minute\(entry.minutes == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DetailCardPalette.mutedText)
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
        Button(action: onTap) {
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
        case summary
        case health

        var color: Color {
            switch self {
            case .reminder:
                return Color(red: 0.49, green: 0.84, blue: 0.97)
            case .streak:
                return Color(red: 0.49, green: 0.93, blue: 0.72)
            case .message:
                return Color(red: 1.0, green: 0.72, blue: 0.45)
            case .summary:
                return Color(red: 0.78, green: 0.69, blue: 0.98)
            case .health:
                return Color(red: 0.98, green: 0.48, blue: 0.52)
            }
        }
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let kind: Kind
}

private struct CallLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let minutes: Int
    let loggedAt: Date

    init(id: UUID = UUID(), name: String, minutes: Int, loggedAt: Date) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.loggedAt = loggedAt
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
