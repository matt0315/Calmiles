import SwiftUI

struct CalmilesCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calmilesCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

struct CalmilesPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CalmilesTypography.headline)
                .foregroundStyle(CalmilesColor.mist)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isEnabled ? CalmilesColor.copper : CalmilesColor.copper.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

struct CalmilesSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CalmilesTypography.headline)
                .foregroundStyle(CalmilesColor.copper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(CalmilesColor.sand.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "car.side"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(CalmilesColor.copperSoft)
                .accessibilityHidden(true)
            Text(title)
                .font(CalmilesTypography.title)
                .foregroundStyle(Color.calmilesPrimaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(CalmilesTypography.body)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                CalmilesPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

struct LoadingStateView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(CalmilesTypography.callout)
                .foregroundStyle(Color.calmilesSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(CalmilesColor.danger)
            Text(message)
                .font(CalmilesTypography.body)
                .foregroundStyle(Color.calmilesPrimaryText)
                .multilineTextAlignment(.center)
            if let retry {
                CalmilesSecondaryButton(title: "Try Again", action: retry)
            }
        }
        .padding(32)
    }
}

struct ClassificationChip: View {
    let classification: TripClassification
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Text(classification.displayName)
                .font(CalmilesTypography.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(border, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(classification.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var background: Color {
        switch classification {
        case .business: return CalmilesColor.business.opacity(isSelected ? 0.25 : 0.12)
        case .personal: return CalmilesColor.personal.opacity(isSelected ? 0.25 : 0.12)
        case .undecided: return CalmilesColor.undecided.opacity(isSelected ? 0.35 : 0.18)
        }
    }

    private var foreground: Color {
        switch classification {
        case .business: return CalmilesColor.copper
        case .personal: return CalmilesColor.personal
        case .undecided: return Color.calmilesPrimaryText
        }
    }

    private var border: Color { foreground }
}
