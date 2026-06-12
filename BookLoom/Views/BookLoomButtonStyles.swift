import SwiftUI

struct BookLoomSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = BookLoomStyle.plum

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .modifier(BookLoomActionWidthModifier(minWidth: 190))
            .opacity(isEnabled ? 1 : 0.5)
    }

    private func background(pressed: Bool) -> some View {
        let opacity: Double
        if !isEnabled {
            opacity = colorScheme == .dark ? 0.06 : 0.05
        } else if pressed {
            opacity = colorScheme == .dark ? 0.42 : 0.28
        } else {
            opacity = colorScheme == .dark ? 0.30 : 0.18
        }
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(opacity))
    }

    private var strokeColor: Color {
        if !isEnabled {
            return tint.opacity(colorScheme == .dark ? 0.18 : 0.20)
        }
        return tint.opacity(colorScheme == .dark ? 0.55 : 0.45)
    }
}

struct BookLoomProminentButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color = BookLoomStyle.plum

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .lineLimit(3)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(background(pressed: configuration.isPressed))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private func background(pressed: Bool) -> some View {
        let opacity: Double
        if !isEnabled {
            opacity = colorScheme == .dark ? 0.14 : 0.12
        } else if pressed {
            opacity = colorScheme == .dark ? 0.78 : 0.82
        } else {
            opacity = 1
        }
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tint.opacity(opacity))
    }
}

struct AdaptiveSegmentedControl<Option: Hashable & Identifiable, LabelContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> LabelContent

    init(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        @ViewBuilder label: @escaping (Option) -> LabelContent
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        if dynamicTypeSize.prefersExpandedControlLayout {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(segmentBackground(isSelected: selection == option))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(segmentStroke(isSelected: selection == option), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    label(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segmentBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? BookLoomStyle.plum.opacity(colorScheme == .dark ? 0.32 : 0.18) : Color.secondary.opacity(0.10))
    }

    private func segmentStroke(isSelected: Bool) -> Color {
        isSelected ? BookLoomStyle.plum.opacity(0.55) : Color.secondary.opacity(0.18)
    }
}
