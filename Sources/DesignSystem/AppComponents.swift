import SwiftUI

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5)
            }
    }
}

extension View {
    func appCard() -> some View { modifier(CardStyle()) }
}

struct StatusPill: View {
    let text: String
    var color: Color = AppColors.secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(.secondary) }
            Text(title).font(AppTypography.sectionTitle)
        }
        .frame(height: 24)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, AppSpacing.xxs)
            Text(title).font(AppTypography.pageTitle)
            Text(message)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, AppSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xxl)
    }
}

struct RepositoryAvatar: View {
    let urlString: String?
    var size: CGFloat = AppLayout.rowIconSize
    var isSelected = false

    var body: some View {
        AsyncImage(url: URL(string: urlString ?? "")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: isSelected
                            ? [.white.opacity(0.24), .white.opacity(0.10)]
                            : [.accentColor.opacity(0.18), .accentColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.22) : AppColors.separator.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        GridRow {
            Text(key).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).gridColumnAlignment(.leading)
        }
    }
}
