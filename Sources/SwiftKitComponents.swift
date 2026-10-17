// Vendored atoms adapted from the user's SwiftKitComponents.swift library
// (MIT, The Swift Kit). Only the components Voxflow actually uses are
// vendored here — no dead code, no iOS screens, no paywall.
// macOS adaptations: UIImpactFeedbackGenerator / UISelectionFeedbackGenerator
// → NSHapticFeedbackManager; UIKit colors → AppKit/voxflow equivalents;
// iOS-only modifiers (.textInputAutocapitalization, .submitLabel,
// .presentationDetents, navigation-bar APIs) dropped.
// Where the library conflicts with Voxflow's decided styles, Voxflow wins:
// pearl = primary actions, glass = secondary/destructive.
// NOT vendored, deliberately: PricingCard (Voxflow is free — a pricing card
// would be misleading), DeleteAccountButton (no accounts), LibraryScreen /
// BottomSheetExample (iOS example screens), AvatarRow (no user avatars),
// FeatureRow (paywall-only), PrimaryButton / LoadingButton / IconButton /
// PressableStyle (Voxflow's pearl + glass button styles already cover
// those roles — no second button system), GlassCard (no honest use; the
// hero builds its own glass), ProgressRing (no honest progress metric in
// the app — a ring without a real goal would be decoration).

import SwiftUI
import AppKit

// MARK: - Buttons

/// Secondary action: Voxflow glass style (frosted, translucent).
struct SecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.voxflowGlass)
    }
}

/// Destructive action: red-tinted glass + confirmation dialog.
struct DestructiveButton: View {
    let title: String
    var onConfirm: () -> Void
    @State private var confirming = false

    var body: some View {
        Button(role: .destructive) {
            confirming = true
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.voxflowGlassDestructive)
        .confirmationDialog("Are you sure?", isPresented: $confirming, titleVisibility: .visible) {
            Button(title, role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Cards

/// The workhorse surface — title, body, and a soft elevation shadow.
struct ContentCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.voxflowCard, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

/// Metric tile with an optional trend delta — tabular figures so columns
/// line up. Delta is nil when there is no meaningful comparison (e.g. day
/// streak), in which case the delta row is hidden.
struct StatCard: View {
    let label: String
    let value: String
    let delta: Double?

    init(label: String, value: String, delta: Double? = nil) {
        self.label = label
        self.value = value
        self.delta = delta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()          // stops the number jittering on update

            if let delta {
                Label(delta.formatted(.percent.precision(.fractionLength(1))),
                      systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(delta >= 0 ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.voxflowCard, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

// MARK: - Inputs

/// Focus-aware field that animates its border and exposes a clear button.
/// iOS-only `.textInputAutocapitalization` dropped (not on macOS).
struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .focused($focused)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.voxflowCard, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.18), value: focused)
        .animation(.easeOut(duration: 0.18), value: text.isEmpty)
    }
}

/// Inline search bar with a leading glyph and a cancel affordance.
/// iOS-only `.submitLabel` dropped.
struct SearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .focused($focused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.voxflowCard, in: .rect(cornerRadius: 10))

            if focused {
                Button("Cancel") {
                    query = ""
                    focused = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: focused)
    }
}

/// Settings-style switch with a title, subtitle and tinted icon.
struct ToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Custom segmented control with a spring-animated selection pill.
struct SegmentedPicker: View {
    let options: [String]
    @Binding var selection: Int
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    selection = index
                } label: {
                    Text(options[index])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == index ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == index {
                                // matchedGeometryEffect is what makes the pill slide.
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

// MARK: - Feedback

/// Transient top banner that auto-dismisses — attach anywhere with one modifier.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval = 2.5

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    // .task(id:) cancels automatically if the message changes.
                    try? await Task.sleep(for: .seconds(duration))
                    self.message = nil
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// Shimmering placeholder that holds layout while content loads.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 350)
                .blendMode(.plusLighter)
            }
            .mask(content)          // keep the shine inside the shape
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
            }
        }
        .foregroundStyle(Color.primary.opacity(0.08))
        .modifier(Shimmer())
    }
}

// MARK: - States

/// The screen most apps forget — icon, explanation, and one clear action.
/// Primary action uses Voxflow's pearl style (not borderedProminent).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title).font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.pearl)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// Failure view that explains what broke and offers a retry.
struct ErrorStateView: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Something went wrong").font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button("Try again", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.voxflowGlass)
                .padding(.top, 4)
        }
        .padding(32)
    }
}

// MARK: - Lists & Rows

/// Tinted-icon navigation row — the building block of every settings screen.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .rect(cornerRadius: 8))

            Text(title)

            Spacer(minLength: 8)

            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)        // makes the whole row tappable
    }
}

/// History list with swipe actions, adapted from the library's InboxList.
/// Leading swipe = Copy (real clipboard copy); trailing swipe = Delete
/// (real history deletion). The items are the caller's real dictations —
/// never placeholder data.
struct HistoryList<Item: Identifiable>: View {
    let items: [Item]
    let onCopy: (Item) -> Void
    let onDelete: (Item) -> Void
    var rowContent: (Item) -> AnyView

    init(
        items: [Item],
        onCopy: @escaping (Item) -> Void,
        onDelete: @escaping (Item) -> Void,
        @ViewBuilder rowContent: @escaping (Item) -> some View
    ) {
        self.items = items
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.rowContent = { AnyView(rowContent($0)) }
    }

    var body: some View {
        ForEach(items) { item in
            rowContent(item)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        onCopy(item)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .tint(.green)
                }
        }
    }
}

// MARK: - Badges

/// Semantic pill for states — colour and label derived from one enum.
enum Status {
    case active, pending, failed

    var label: String {
        switch self {
        case .active:  "Active"
        case .pending: "Pending"
        case .failed:  "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .active:  .green
        case .pending: .orange
        case .failed:  .red
        }
    }
}

struct StatusBadge: View {
    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.tint)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(status.tint.opacity(0.14), in: .capsule)
        .foregroundStyle(status.tint)
    }
}

/// Notification counter that caps at 99+ and never distorts on wide numbers.
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)   // stays circular at 1 digit
                .background(.red, in: .capsule)
        }
    }
}

// MARK: - Navigation

/// Floating glass tab bar with a spring-animated selection indicator.
/// macOS adaptation: haptics via NSHapticFeedbackManager; the bar scrolls
/// horizontally on narrow windows so tabs are never clipped away; every
/// tab gets a tooltip (`.help`) and a keyboard-focusable Button.
struct CustomTabBar: View {
    @Binding var selection: Int
    let tabs: [(icon: String, label: String)]
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button {
                        selection = i
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tabs[i].icon)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolVariant(selection == i ? .fill : .none)
                            Text(tabs[i].label).font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(selection == i ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background {
                            if selection == i {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                                    .matchedGeometryEffect(id: "tab", in: ns)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tabs[i].label)
                    .accessibilityLabel(tabs[i].label)
                }
            }
            .padding(6)
        }
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: selection)
    }
}
