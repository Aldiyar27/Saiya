import SwiftUI

struct CheckInView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mood = 3
    @State private var energy = 3.0
    @State private var stress = 3.0
    @State private var note = ""
    @State private var addScreen = false
    @State private var screenHours = 4.0

    var body: some View {
        Nav {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Настроение", systemImage: "face.smiling.fill").font(.headline)
                        MoodPicker(value: $mood)
                    }
                }
                slider("Энергия", "bolt.fill", $energy)
                slider("Стресс", "brain.head.profile", $stress)
                Section("Заметка (необязательно)") {
                    TextField("Что повлияло на твой день?", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    Toggle("Указать экранное время за день", isOn: $addScreen)
                    if addScreen {
                        Stepper(value: $screenHours, in: 0...16, step: 0.5) {
                            Text("\(screenHours, specifier: "%.1f") ч")
                        }
                        Text("Посмотри в Настройки → Экранное время")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        vm.add(CheckIn(mood: mood, energy: Int(energy), stress: Int(stress),
                                       screenHours: addScreen ? screenHours : nil,
                                       note: clean.isEmpty ? nil : clean))
                        dismiss()
                    }
                }
            }
        }
    }

    private func slider(_ title: String, _ icon: String, _ v: Binding<Double>) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                Text("\(Int(v.wrappedValue)) из 5").foregroundStyle(.secondary)
                Slider(value: v, in: 1...5, step: 1).tint(Theme.mint)
            }
        }
    }
}
