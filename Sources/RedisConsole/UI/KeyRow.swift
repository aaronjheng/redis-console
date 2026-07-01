import SwiftUI

struct KeyRow: View {
    let entry: RedisKeyEntry
    var displayName: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.type)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 48, alignment: .center)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous))
            Text(displayName ?? entry.key)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, AppTheme.spacing)
        .help(entry.key)
        .accessibilityLabel(entry.key)
    }
}
