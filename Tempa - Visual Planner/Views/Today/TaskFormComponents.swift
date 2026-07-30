import SwiftUI

// MARK: - Shared task-form vocabulary
// One system used by both "New task" (create) and "Edit task".
// Create adds the AI/voice actions on top; everything else is identical.

/// Small uppercase section header, e.g. "CATEGORY".
struct TaskFieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.custom(T.fontBody, size: 12).weight(.semibold))
            .tracking(0.7)
            .foregroundColor(T.textSec)
    }
}

// MARK: - Category

struct CategorySection: View {
    @Binding var category: String
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskFieldLabel("CATEGORY")
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Cat.all, id: \.0) { name, colors in
                    chip(name, colors)
                }
            }
        }
    }

    private func chip(_ name: String, _ colors: CatColors) -> some View {
        let picked = category == name
        return Button {
            category = name
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(spacing: 6) {
                Circle().fill(colors.solid).frame(width: 10, height: 10)
                Text(catDisplayName(name))
                    .font(.custom(T.fontHeader, size: 13).weight(.bold))
                    .foregroundColor(picked ? colors.ink : T.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(picked ? colors.bg : T.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(picked ? colors.ink : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - When (pill + quick-time sheet)

struct WhenSection: View {
    @Binding var startTime: Date
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskFieldLabel("WHEN")
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 14, weight: .medium))
                    Text(label).font(.custom(T.fontHeader, size: 15).weight(.bold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).opacity(0.45)
                    Spacer()
                }
                .foregroundColor(T.text)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
                .tempaShadowSm()
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) { QuickTimeSheet(startTime: $startTime) }
    }

    private var label: String {
        let cal = Calendar.current
        let timeStr = startTime.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(startTime) { return String(localized: "Today, \(timeStr)", bundle: .appLanguage) }
        if cal.isDateInTomorrow(startTime) { return String(localized: "Tomorrow, \(timeStr)", bundle: .appLanguage) }
        return startTime.formatted(date: .abbreviated, time: .shortened)
    }
}

struct QuickTimeSheet: View {
    @Binding var startTime: Date
    @Environment(\.dismiss) private var dismiss

    private var quickTimes: [(String, Date)] {
        let cal = Calendar.current
        let now = Date()
        let inHour = now.addingTimeInterval(3600)
        let tonight = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let tomorrowBase = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrowBase) ?? now
        return [(String(localized: "In 1 hour", bundle: .appLanguage), inHour), (String(localized: "Tonight 6 PM", bundle: .appLanguage), tonight), (String(localized: "Tomorrow 9 AM", bundle: .appLanguage), tomorrow9)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("When?")
                    .font(.custom(T.fontHeader, size: 20).weight(.heavy))
                    .foregroundColor(T.text)
                Spacer()
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.custom(T.fontHeader, size: 15).weight(.bold))
                        .foregroundColor(T.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(quickTimes.enumerated()), id: \.offset) { _, item in
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            startTime = item.1
                        } label: {
                            Text(item.0)
                                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                                .foregroundColor(T.text)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.surface))
                                .tempaShadowSm()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            DatePicker("", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
        .presentationBackground(T.bg)
    }
}

// MARK: - Duration

struct DurationSection: View {
    @Binding var minutes: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TaskFieldLabel("DURATION")
                Spacer()
                Text("\(Int(minutes)) min")
                    .font(.custom(T.fontHeader, size: 14).weight(.bold))
                    .foregroundColor(T.primary)
            }
            Slider(value: $minutes, in: 5...120, step: 5)
                .tint(T.primary)
        }
    }
}

// MARK: - Priority

struct PrioritySection: View {
    @Binding var priority: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskFieldLabel("PRIORITY")
            HStack(spacing: 8) {
                ForEach(0..<4) { p in
                    chip(p)
                }
            }
        }
    }

    private func chip(_ p: Int) -> some View {
        let picked = priority == p
        let color = Self.color(p)
        return Button {
            priority = p
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(Self.name(p))
                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                .foregroundColor(picked ? .white : T.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(picked ? color : T.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(picked ? .clear : color.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    static func name(_ p: Int) -> String {
        [String(localized: "None", bundle: .appLanguage), String(localized: "Low", bundle: .appLanguage), String(localized: "Med", bundle: .appLanguage), String(localized: "High", bundle: .appLanguage)][safe: p] ?? String(localized: "None", bundle: .appLanguage)
    }
    static func color(_ p: Int) -> Color { [T.textSec, T.secondary, T.warning, T.primary][safe: p] ?? T.textSec }
}
