//
//  CookModeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import AppIntents
import SwiftUI
import AppIntents
import AudioToolbox

/// Step-by-step cooking mode view
struct CookModeView: View {
    let recipe: Recipe
    let coordinator: CookModeCoordinator
    let dependencies: DependencyContainer

    @ObservedObject private var timerManager: TimerManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var showingAllTimers = false
    @State private var showingIngredients = false
    @State private var showingIngredientSheet = false
    @State private var showingEndSessionAlert = false
    private var checkedIngredientIDs: Set<UUID> {
        coordinator.referenceState.checkedIngredientIDs.intersection(recipe.ingredients.map(\.id))
    }

    private var referencePage: Binding<Int> {
        Binding(
            get: { coordinator.referenceState.page },
            set: { coordinator.updateReference(.selectPage($0)) }
        )
    }
    @State private var experiencePreferences: ExperiencePreferences

    private var scaleFactor: Double { experiencePreferences.recipeScaleFactor }
    private var unitSystem: UnitSystem { experiencePreferences.recipeUnitSystem }
    private var shouldReduceMotion: Bool {
        accessibilityReduceMotion || experiencePreferences.reduceMotion
    }

    /// Ingredients adjusted for the current scale factor and unit system.
    /// Ingredient ids are preserved by both transforms, so check-off state
    /// survives scaling and conversion.
    private var displayedIngredients: [Ingredient] {
        let scaled = scaleFactor == 1.0
            ? recipe.ingredients
            : RecipeScaler.scale(recipe, by: scaleFactor).recipe.ingredients
        return UnitConverter.convert(scaled, to: unitSystem)
    }

    private var scaleFactorLabel: String {
        switch scaleFactor {
        case 0.5: return "½×"
        case 1.0: return "1×"
        default: return "\(scaleFactor.formatted(.number.precision(.fractionLength(0...1))))×"
        }
    }

    init(recipe: Recipe, coordinator: CookModeCoordinator, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.coordinator = coordinator
        self.dependencies = dependencies
        _timerManager = ObservedObject(wrappedValue: dependencies.timerManager)
        _experiencePreferences = State(initialValue: .shared)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            if !isRegularWidthLayout {
                ProgressView(value: coordinator.progress)
                    .tint(Color.cauldronOrange)
            }

            GeometryReader { proxy in
                cookingContent(availableWidth: proxy.size.width)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .recipeOnscreenContext(recipe)
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Minimize", systemImage: "chevron.down") {
                    coordinator.minimizeToBackground()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CookModeDisplayControls(preferences: experiencePreferences)
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingAllTimers) {
            AllTimersView(timerManager: timerManager)
                .appSheetSizing(.standard)
        }
        .sheet(isPresented: $showingIngredientSheet) {
            NavigationStack {
                ScrollView {
                    ingredientChecklistSection.padding()
                }
                .navigationTitle("Ingredients")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") {
                            showingIngredientSheet = false
                        }
                    }
                }
            }
            .appSheetSizing(.standard)
        }
        .alert("End Cooking Session?", isPresented: $showingEndSessionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Session", role: .destructive) {
                coordinator.endSession()
            }
        } message: {
            Text("Your progress will be saved and you can resume anytime.")
        }
        .onAppear {
            // Record in cooking history (only once when starting)
            if coordinator.currentStepIndex == 0 {
                Task {
                    try? dependencies.cookingHistoryRepository.recordCooked(
                        recipeId: recipe.id,
                        recipeTitle: recipe.title
                    )
                }
            }
        }
    }

    private var isRegularWidthLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var controlPanelBackground: some View {
        GeometryReader { proxy in
            recipeArtwork
                .frame(width: proxy.size.width, height: proxy.size.height)
                .blur(radius: 60)
                .overlay {
                    (colorScheme == .dark ? Color.black : Color.appBackground)
                        .opacity(colorScheme == .dark ? 0.78 : 0.84)
                }
                .clipped()
        }
        .allowsHitTesting(false)
    }

    private var recipeArtwork: some View {
        RecipeImageView(
            imageURL: recipe.imageURL, size: .hero, showPlaceholderText: false,
            recipeImageService: dependencies.recipeImageService,
            recipeId: recipe.id, ownerId: recipe.ownerId,
            privateRecordName: recipe.cloudRecordName,
            imageCacheIdentity: recipe.imageModifiedAt.map(RecipeImageView.cacheIdentity)
        )
    }

    @ViewBuilder
    private func cookingContent(availableWidth: CGFloat) -> some View {
        // Runtime guards alone cannot compile these APIs with the shipping SDK.
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, macCatalyst 27.1, *), isRegularWidthLayout {
            ArrangementView {
                readingPane
            } secondary: {
                workbenchPanel
            }
            .arrangementViewStyle(.split)
            // The split layout reserves the hinge for content. Paint behind the
            // entire arrangement so that region does not expose a blank band.
            .background(controlPanelBackground.ignoresSafeArea(.container))
        } else {
            fallbackCookingContent(availableWidth: availableWidth)
        }
        #else
        fallbackCookingContent(availableWidth: availableWidth)
        #endif
    }

    @ViewBuilder
    private func fallbackCookingContent(availableWidth: CGFloat) -> some View {
        if RecipeReadingLayout.usesColumns(
            availableWidth: availableWidth,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        ) {
            HStack(spacing: 0) {
                readingPane
                Divider()
                workbenchPanel
                    .frame(width: RecipeReadingLayout.workbenchWidth(availableWidth: availableWidth))
                    .background(controlPanelBackground.ignoresSafeArea(.container, edges: .bottom))
            }
        } else {
            compactContent
        }
    }

    private var compactContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    stepProgressBadge
                    stepContent
                    timersSection
                    DisclosureGroup("Ingredients", isExpanded: $showingIngredients) {
                        ingredientChecklistSection
                            .padding(.top, Theme.Spacing.sm)
                    }
                }
                .padding(.top, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }

            navigationControls
            cookingOptionsMenu
                .padding(.bottom, Theme.Spacing.md)
        }
    }

    private var readingPane: some View {
        GeometryReader { proxy in
            // Size follows the pane, never the instruction's text length.
            let instructionHeight = min(180, max(120, proxy.size.height * 0.36))
            ZStack(alignment: .bottom) {
                ScrollView {
                    recipeArtwork
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .backgroundExtensionEffect()
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeEffectStyle(.soft, for: .top)

                GlassEffectContainer {
                    ScrollView {
                        stepContent
                            .padding(20)
                    }
                    .id(coordinator.currentStepIndex)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                    .frame(width: proxy.size.width, height: instructionHeight)
                    .glassEffect(.regular, in: Rectangle())
                    .accessibilityIdentifier("cookInstructionPanel")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var stepProgressBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.number")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 34, height: 34)
                .background(Color.cauldronOrange.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                    .font(isRegularWidthLayout ? .title3.weight(.bold) : .headline.weight(.semibold))
                    .foregroundStyle(Color.cauldronOrange)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.cauldronSecondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private var stepContent: some View {
        Group {
            if let currentStep = coordinator.currentStep {
                Text(currentStep.text)
                    .font(experiencePreferences.largerStepText ? .title : .title3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var timersSection: some View {
        if let currentStep = coordinator.currentStep {
            VStack(spacing: 12) {
                // Show ALL active timers (not just for current step)
                if !timerManager.activeTimers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Timers")
                            .font(.headline)
                            .foregroundColor(.cauldronOrange)

                        ForEach(timerManager.activeTimers) { activeTimer in
                            ImprovedTimerRowView(timer: activeTimer, timerManager: timerManager)
                        }
                    }
                }

                // Show start buttons for timers defined in current step that haven't been started yet
                if !currentStep.timers.isEmpty {
                    let stepActiveTimers = timerManager.activeTimers.filter { $0.stepIndex == coordinator.currentStepIndex }

                    VStack(alignment: .leading, spacing: 8) {
                        if !timerManager.activeTimers.isEmpty {
                            Text("Step Timers")
                                .font(.headline)
                                .padding(.top, 8)
                        }

                        ForEach(currentStep.timers) { timerSpec in
                            // Check if this timer is already running for this step
                            let isRunning = stepActiveTimers.contains { activeTimer in
                                activeTimer.spec.seconds == timerSpec.seconds &&
                                activeTimer.spec.label == timerSpec.label
                            }

                            if !isRunning {
                                // Start button for timer
                                Button {
                                    timerManager.startTimer(
                                        spec: timerSpec,
                                        stepIndex: coordinator.currentStepIndex,
                                        recipeName: recipe.title
                                    )
                                    Task { await RecipeIntentDonation.recordTimerStarted(timerSpec) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(timerSpec.label)
                                                .font(.headline)
                                            Text(timerSpec.displayDuration)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "play.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.cauldronOrange)
                                    }
                                    .padding(16)
                                    .background(Color.cauldronSecondaryBackground)
                                    .cornerRadius(Theme.Radius.large)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Quick timer button
                QuickTimerButton(
                    timerManager: timerManager,
                    recipeName: recipe.title,
                    stepIndex: coordinator.currentStepIndex
                )
            }
        }
    }

    private var cookingOptionsMenu: some View {
        Menu {
            Section("Cooking") {
                Button("Ingredients", systemImage: "checklist") {
                    showingIngredientSheet = true
                }

                NavigationLink {
                    RecipeDetailView(
                        recipe: recipe,
                        dependencies: dependencies,
                        highlightedStepIndex: coordinator.currentStepIndex
                    )
                } label: {
                    Label("View Full Recipe", systemImage: "book.fill")
                }

                Button {
                    showingAllTimers = true
                } label: {
                    Label("Timers (\(timerManager.activeTimers.count))", systemImage: "timer")
                }
            }

            Section("Recipe") {
                Picker("Servings", selection: Binding(
                    get: { experiencePreferences.recipeScaleFactor },
                    set: { experiencePreferences.recipeScaleFactor = $0 }
                )) {
                    Text("½×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                }


            }

            Section("Display") {
                cookModeSettingsMenu
            }

            Section {
                Button(role: .destructive) {
                    showingEndSessionAlert = true
                } label: {
                    Label("End Cooking", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel("Cooking options")
    }

    private var workbenchPanel: some View {
        GeometryReader { proxy in
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Step \(coordinator.currentStepIndex + 1) of \(coordinator.totalSteps)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Spacer()
                        Button("End Session", systemImage: "xmark.circle", role: .destructive) {
                            showingEndSessionAlert = true
                        }
                        .font(.subheadline)
                        .buttonStyle(.glass)
                        .controlSize(.regular)
                    }

                    TabView(selection: referencePage) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(coordinator.isLastStep ? "FINAL STEP" : "UP NEXT")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if recipe.steps.indices.contains(coordinator.currentStepIndex + 1) {
                                Text(recipe.steps[coordinator.currentStepIndex + 1].text)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            } else {
                                Text("You're on the final instruction.")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.bottom, 32)
                        .tag(0)

                        ScrollView {
                            ingredientChecklistSection
                                .padding(.bottom, 32)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(maxHeight: .infinity)
                    .padding(.top, 8)
                    .accessibilityIdentifier("cookReferencePager")

                    CookModeActiveTimerSummary(timerManager: timerManager) {
                        showingAllTimers = true
                    }

                    HStack(spacing: 16) {
                        QuickTimerButton(timerManager: timerManager, recipeName: recipe.title,
                                         stepIndex: coordinator.currentStepIndex,
                                         isWorkbenchControl: true, suggestedTimers: unstartedCurrentStepTimers)
                        CookModeServingsMenu(preferences: experiencePreferences)
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, dependencies: dependencies,
                                             highlightedStepIndex: coordinator.currentStepIndex)
                        } label: {
                            Label("Full Recipe", systemImage: "book")
                        }
                    }
                    .buttonStyle(CookModeControlTileStyle(height: 60))
                    .font(.subheadline.weight(.medium))

                    HStack(spacing: 16) {
                        previousStepButton
                        nextStepButton
                    }
                }
                .padding(20)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var ingredientChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Ingredients")
                    .font(.headline)
                if scaleFactor != 1.0 {
                    Text(scaleFactorLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.cauldronOrange)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.cauldronOrange.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("\(checkedIngredientIDs.count)/\(displayedIngredients.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if displayedIngredients.isEmpty {
                Text("No ingredients available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedIngredients) { ingredient in
                    let isChecked = checkedIngredientIDs.contains(ingredient.id)

                    Button {
                        toggleIngredientCheck(ingredient.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChecked ? Color.cauldronOrange : .secondary)
                                .font(.body)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: isChecked)

                            Text(ingredient.displayString)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(isChecked ? .secondary : .primary)
                                .strikethrough(isChecked)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var unstartedCurrentStepTimers: [TimerSpec] {
        guard let currentStep = coordinator.currentStep else { return [] }
        let stepActiveTimers = timerManager.activeTimers.filter { $0.stepIndex == coordinator.currentStepIndex }

        return currentStep.timers.filter { timerSpec in
            !stepActiveTimers.contains { activeTimer in
                activeTimer.spec.seconds == timerSpec.seconds &&
                activeTimer.spec.label == timerSpec.label
            }
        }
    }

    private func toggleIngredientCheck(_ ingredientID: UUID) {
        coordinator.updateReference(.toggleIngredient(ingredientID))
    }

    private var navigationControls: some View {
        GlassEffectContainer(spacing: 24) {
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 24) {
                        previousStepButton
                        nextStepButton
                    }
                }
                VStack(spacing: 20) {
                    previousStepButton
                    nextStepButton
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .animation(
            shouldReduceMotion ? nil : Theme.Animation.snappy,
            value: coordinator.currentStepIndex
        )
    }

    private var previousStepButton: some View {
        Button {
            coordinator.previousStep()
        } label: {
            Label("Back", systemImage: "chevron.left")
                .fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(CookModeControlTileStyle(height: isRegularWidthLayout ? 80 : 52))
        .controlSize(.extraLarge)
        .disabled(coordinator.isFirstStep)
    }

    private var nextStepButton: some View {
        Button {
            if coordinator.isLastStep {
                if experiencePreferences.timerHaptics {
                    Haptics.success()
                }
                coordinator.endSession()
            } else {
                coordinator.nextStep()
            }
        } label: {
            HStack {
                Text(coordinator.isLastStep ? "Done" : "Next")
                    .fontWeight(.semibold)
                Image(systemName: coordinator.isLastStep ? "checkmark" : "chevron.right")
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(CookModeControlTileStyle(height: isRegularWidthLayout ? 80 : 52, isPrimary: true))
        .controlSize(.extraLarge)
        .tint(.cauldronOrange)
    }

    private var cookModeSettingsMenu: some View {
        Menu("Cook Mode Settings", systemImage: "gearshape") {
            Toggle("Keep Screen Awake", isOn: Binding(
                get: { experiencePreferences.keepScreenAwake },
                set: { experiencePreferences.keepScreenAwake = $0 }
            ))
            Toggle("Larger Step Text", isOn: Binding(
                get: { experiencePreferences.largerStepText },
                set: { experiencePreferences.largerStepText = $0 }
            ))
            Toggle("Reduce Motion", isOn: Binding(
                get: { experiencePreferences.reduceMotion },
                set: { experiencePreferences.reduceMotion = $0 }
            ))

            Section("Timer Feedback") {
                Toggle("Haptics", isOn: Binding(
                    get: { experiencePreferences.timerHaptics },
                    set: { experiencePreferences.timerHaptics = $0 }
                ))
                Toggle("Sounds", isOn: Binding(
                    get: { experiencePreferences.timerSounds },
                    set: { experiencePreferences.timerSounds = $0 }
                ))
            }
        }
    }
}


private struct CookModeControlTileStyle: ButtonStyle {
    var height: CGFloat = 72
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .glassEffect(
                isPrimary ? .regular.tint(.cauldronOrange).interactive() : .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

private struct CookModeServingsMenu: View {
    @Bindable var preferences: ExperiencePreferences

    private var multiplier: String {
        preferences.recipeScaleFactor == 0.5
            ? "½×"
            : "\(preferences.recipeScaleFactor.formatted(.number.precision(.fractionLength(0...1))))×"
    }

    var body: some View {
        Menu {
            Picker("Servings", selection: $preferences.recipeScaleFactor) {
                Text("½×").tag(0.5)
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("3×").tag(3.0)
            }
        } label: {
            Label("Servings \(multiplier)", systemImage: "person.2")
        }
        .accessibilityValue(multiplier)
    }
}

private struct CookModeDisplayControls: View {
    @Bindable var preferences: ExperiencePreferences

    var body: some View {
        Menu {
            Toggle("Keep Screen Awake", isOn: $preferences.keepScreenAwake)
            Toggle("Larger Step Text", isOn: $preferences.largerStepText)
            Toggle("Reduce Motion", isOn: $preferences.reduceMotion)
            Section("Timer Feedback") {
                Toggle("Haptics", isOn: $preferences.timerHaptics)
                Toggle("Sounds", isOn: $preferences.timerSounds)
            }
        } label: {
            Label("Accessibility", systemImage: "accessibility")
        }
    }
}

private struct CookModeActiveTimerSummary: View {
    @ObservedObject var timerManager: TimerManager
    let showAllTimers: () -> Void

    var body: some View {
        if let timer = timerManager.activeTimers.first {
            HStack(spacing: 12) {
                Image(systemName: "timer").foregroundStyle(Color.cauldronOrange)
                Text(timer.spec.label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if timerManager.activeTimers.count > 1 {
                    Button("+\(timerManager.activeTimers.count - 1)", action: showAllTimers)
                        .accessibilityLabel("Show all \(timerManager.activeTimers.count) timers")
                        .frame(minWidth: 44, minHeight: 44)
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let seconds = max(0, timerManager.getRemainingTime(id: timer.id))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.cauldronOrange)
                }
                Button(timer.isRunning ? "Pause timer" : "Resume timer",
                       systemImage: timer.isRunning ? "pause.fill" : "play.fill") {
                    if timer.isRunning { timerManager.pauseTimer(id: timer.id) }
                    else { timerManager.resumeTimer(id: timer.id) }
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                Button("Stop timer", systemImage: "stop.fill") {
                    timerManager.stopTimer(id: timer.id)
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .frame(height: 44)
        }
    }
}

#Preview {
    let container = DependencyContainer.preview()
    let coordinator = CookModeCoordinator(dependencies: container)
    let recipe = Recipe(
        title: "Sample Recipe",
        ingredients: [],
        steps: [
            CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
            CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30, label: "Bake")])
        ]
    )

    Task { @MainActor in
        await coordinator.startCooking(recipe)
    }

    return NavigationStack {
        CookModeView(
            recipe: recipe,
            coordinator: coordinator,
            dependencies: container
        )
    }
    .dependencies(container)
}
