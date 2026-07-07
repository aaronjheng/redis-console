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
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(displayName ?? entry.key)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 8)
        .help(entry.key)
        .accessibilityLabel(entry.key)
    }
}
