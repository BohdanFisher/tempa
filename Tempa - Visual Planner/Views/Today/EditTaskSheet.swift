import SwiftUI
import CoreData

/// Edit an existing task. Same form vocabulary as the create sheet — just
/// without the AI/voice actions, which aren't needed when editing.
struct EditTaskSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var task: TaskBlock

    @State private var title: String
    @State private var category: String
    @State private var startTime: Date
    @State private var durationMinutes: Double
    @State private var priority: Int

    init(task: TaskBlock) {
        self.task = task
        _title = State(initialValue: task.title ?? "")
        _category = State(initialValue: task.category ?? "work")
        _startTime = State(initialValue: task.startTime ?? Date())
        _durationMinutes = State(initialValue: Double(task.durationMinutes))
        _priority = State(initialValue: Int(task.priority))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        TaskFieldLabel("TITLE")
                        TextField("Task title", text: $title, axis: .vertical)
                            .font(.custom(T.fontHeader, size: 18).weight(.bold))
                            .foregroundColor(T.text)
                            .lineLimit(1...4)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
                            .tempaShadowSm()
                    }

                    CategorySection(category: $category)
                    WhenSection(startTime: $startTime)
                    DurationSection(minutes: $durationMinutes)
                    PrioritySection(priority: $priority)
                }
                .padding(20)
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Refresh the icon to match the category only if it's still a default/placeholder.
        if Cat.defaultIcons.contains(task.iconName ?? "circle") {
            task.iconName = Cat.icon(for: category)
        }
        task.category = category
        task.startTime = startTime
        task.durationMinutes = Int32(durationMinutes)
        task.priority = Int16(priority)
        try? viewContext.save()
        dismiss()
    }
}
