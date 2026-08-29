import SwiftUI

struct KeyRow: View {
    let entry: RedisKeyEntry
    var displayName: String?

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Text(entry.type)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: AppSize.typeBadgeWidth, alignment: .center)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(AppColor.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            Text(displayName ?? entry.key)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, AppSpacing.medium)
        .padding(.leading, AppSpacing.small)
        .contentShape(Rectangle())
        .help(entry.key)
        .accessibilityLabel(entry.key)
    }
}
