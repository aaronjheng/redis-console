import SwiftUI

struct KeyRow: View {
    let entry: RedisKeyEntry
    var displayName: String?

    var body: some View {
        HStack(spacing: 8) {
            if entry.type.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 42)
            } else {
                Text(entry.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.spacingSmall)
                    .padding(.vertical, 1)
                    .frame(minWidth: 42)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            }
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
