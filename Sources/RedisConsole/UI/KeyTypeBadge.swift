import SwiftUI

struct KeyTypeBadge: View {
    let type: String

    var body: some View {
        if type.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(width: 42)
        } else {
            Text(type)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.spacingSmall)
                .padding(.vertical, 1)
                .frame(minWidth: 42)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        }
    }
}
