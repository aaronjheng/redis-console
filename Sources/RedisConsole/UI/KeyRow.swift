import SwiftUI

struct KeyRow: View {
    let entry: RedisKeyEntry
    var displayName: String?

    var body: some View {
        HStack(spacing: 8) {
            Badge(text: entry.type, isLoading: entry.type.isEmpty)
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
