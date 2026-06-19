import SwiftUI
import CoreData

/// Move a task to a different date (keeps its time-of-day).
struct MoveTaskSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var task: TaskBlock
    @State private var date: Date

    init(task: TaskBlock) {
        self.task = task
        _date = State(initialValue: task.startTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .tint(T.primary)
                    .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle("Move task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { move() }.fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func move() {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: task.startTime ?? Date())
        if let newDate = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: date) {
            task.startTime = newDate
            try? viewContext.save()
        }
        dismiss()
    }
}
