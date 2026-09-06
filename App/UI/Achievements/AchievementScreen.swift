import SwiftUI

// Rationale
// Flipping is a sighted-only visual delight. With VoiceOver enabled, each card is a readable, non-interactive element
// that directly communicates name, locked/unlocked, and how to unlock (description).

@available(iOS 18.0, *)
struct AchievementsScreen: View {
    @Environment(AchievementEngine.self) private var engine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var flippedCardID: AchievementId?
    @State private var flipHapticTrigger = false

    private var columns: [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Achievements")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(Achievements.all, id: \.id) { achievement in
                        let unlocked = engine.isUnlocked(achievement.id)

                        AchievementCard(
                            achievement: achievement,
                            isUnlocked: unlocked,
                            isFlipped: flippedCardID == achievement.id,
                            isInteractive: !voiceOverEnabled,
                            onToggle: { toggleCard(for: achievement.id) }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 140)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: flipHapticTrigger)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func toggleCard(for id: AchievementId) {
        guard !voiceOverEnabled else { return }
        flipHapticTrigger.toggle()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            flippedCardID = (flippedCardID == id) ? nil : id
        }
    }
}

@available(iOS 18.0, *)
private struct AchievementCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let achievement: Achievement
    let isUnlocked: Bool
    let isFlipped: Bool
    let isInteractive: Bool
    let onToggle: () -> Void

    var body: some View {
        Group {
            if isInteractive {
                Button(action: onToggle) { cardVisual }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(achievement.name))
                    .accessibilityValue(Text(isUnlocked ? "Unlocked" : "Locked"))
                    .accessibilityHint(Text(isFlipped ? "Shows the front." : "Shows details."))
            } else {
                cardVisual
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(achievement.name))
                    .accessibilityValue(Text("\(isUnlocked ? "Unlocked" : "Locked"). \(achievement.description)"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cardVisual: some View {
        ZStack {
            CardBack(achievement: achievement, isUnlocked: isUnlocked)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : (isFlipped ? 0 : 180)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )

            CardFront(achievement: achievement, isUnlocked: isUnlocked)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : (isFlipped ? -180 : 0)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Name Style (old look, accessible)

private struct AchievementNameText: View {
    // Starts at 15pt but scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 15

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: nameSize, weight: .regular, design: .serif))
            .italic()
            // Adaptive "dark gray" that stays readable in dark mode and higher contrast.
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

// MARK: - Card Front

private struct CardFront: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 12) {
            achievementImage
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            AchievementNameText(text: achievement.name)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var achievementImage: some View {
        if let uiImage = UIImage(named: achievement.imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .saturation(isUnlocked ? 1.0 : 0.0)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemGray5))

                Image(systemName: achievement.fallbackIconName)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(isUnlocked ? GameTheme.green : Color(.systemGray2))
            }
        }
    }
}

// MARK: - Card Back

private struct CardBack: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundFill)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.5)

                VStack(spacing: 10) {
                    Image(systemName: isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isUnlocked ? GameTheme.green : .secondary)
                        .accessibilityHidden(true)

                    Text(achievement.description)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 8)
                        .accessibilityHidden(true)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            AchievementNameText(text: achievement.name)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var backgroundFill: LinearGradient {
        LinearGradient(
            colors: isUnlocked
                ? [GameTheme.green.opacity(0.14), GameTheme.green.opacity(0.06)]
                : [Color(.systemGray6), Color(.systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        isUnlocked ? GameTheme.green.opacity(0.45) : Color(.separator)
    }
}

// MARK: - Fallback Icons

private extension Achievement {
    var fallbackIconName: String {
        switch id {
        case .theBeginning: return "star.fill"
        case .wordsWordsWords: return "text.book.closed.fill"
        case .smallTalk: return "textformat.size.smaller"
        case .palindromeHunter: return "arrow.left.arrow.right"
        case .alphabetSoup: return "textformat.abc"
        case .earlyBird: return "sunrise.fill"
        case .touchGrass: return "leaf.fill"
        case .whatCameFirst: return "bird.fill"
        case .chasingRainbows: return "rainbow"
        case .lightningInABottle: return "bolt.fill"
        case .whatItSaysOnTheTin: return "rectangle.and.text.magnifyingglass"
        case .aboveTheClouds: return "cloud.fill"
        default: return "seal.fill"
        }
    }
}
