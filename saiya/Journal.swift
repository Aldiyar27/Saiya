import SwiftUI

enum MoodEmoji {
    static let all = ["😞", "🙁", "😐", "🙂", "😄"]
    static func emoji(_ value: Int) -> String { all[min(max(value, 1), all.count) - 1] }
}

/// Ряд из пяти смайлов для выбора настроения.
struct MoodPicker: View {
    @Binding var value: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    value = i
                    Haptics.tap()
                } label: {
                    Text(MoodEmoji.emoji(i))
                        .font(.system(size: 30))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(value == i ? Theme.mint.opacity(0.22) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .scaleEffect(value == i ? 1.08 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Дневник: пара строк в день. Помогает замечать хорошее и видеть динамику настроения.
struct JournalView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mood = 4

    var body: some View {
        Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    composer
                    entries
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Дневник")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private var composer: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Мысль дня", systemImage: "sparkles").font(.headline)
                Text(JournalPrompts.today()).font(.system(.body, design: .rounded).weight(.medium))
                MoodPicker(value: $mood)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(6)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if text.isEmpty {
                        Text("Пара строк — этого достаточно…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                Button {
                    vm.addJournal(text: text, mood: mood)
                    text = ""
                } label: {
                    Label("Сохранить запись", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.mint)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Записи хранятся только на этом устройстве и не отправляются в AI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var entries: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Записи", subtitle: vm.journal.isEmpty ? nil : "Всего: \(vm.journal.count)")
            if vm.journal.isEmpty {
                Card { Text("Пока пусто. Первая запись — вверху 👆").foregroundStyle(.secondary) }
            } else {
                ForEach(vm.journal.sorted { $0.date > $1.date }.prefix(60)) { e in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(MoodEmoji.emoji(e.mood)).font(.title3)
                                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { vm.deleteJournal(e.id) } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(e.text).font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}
