import SwiftUI

struct SourcesView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var confirmDelete = false

    var body: some View {
        Nav {
            Form {
                Section("Как к тебе обращаться?") {
                    TextField("Имя (необязательно)", text: $vm.userName)
                }
                Section("Источники данных") {
                    Toggle("Календарь (свободное время вечером)", isOn: $vm.useCalendar)
                    Toggle("Погода по примерному местоположению", isOn: $vm.useWeather)
                    Text("Доступ к Apple Health настраивается в Настройки → Здоровье → Доступ к данным. Календарь читается только на сегодня и нигде не хранится. Координаты округляются до ~1 км, не сохраняются и нужны только для погоды.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("AI-анализ") {
                    Toggle("Отправлять сводку в Gemini", isOn: $vm.aiEnabled)
                    SecureField("Gemini API-ключ", text: $key)
                    Button("Сохранить ключ") { vm.saveKey(key); key = "" }.disabled(key.isEmpty)
                    Text(AIConfig.isConfigured ? "Ключ сохранён в Keychain" : "Ключ не задан")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Уходят только усреднённые показатели, погода и свободное время, без координат и названий событий. Имя уходит только если ты его указал. Без AI приложение работает на локальных советах.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Напоминания") {
                    Toggle("Напоминать в течение дня", isOn: $vm.remindersEnabled)
                    if vm.remindersEnabled {
                        Picker("Каждые", selection: $vm.reminderInterval) {
                            ForEach([1, 2, 3, 4], id: \.self) { Text("\($0) ч").tag($0) }
                        }
                        Picker("С", selection: $vm.reminderStart) {
                            ForEach(6...12, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        Picker("До", selection: $vm.reminderEnd) {
                            ForEach(16...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                        Button("Отправить тест через 5 секунд") { vm.sendTestReminder() }
                    }
                    if vm.notificationsDenied {
                        Text("Уведомления для Saiya выключены в системе.")
                            .font(.caption).foregroundStyle(Theme.rose)
                        Button("Открыть настройки iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Text("Напоминания про воду, движение, дыхание, сон и задания приходят по расписанию. iOS не даёт приложению просыпаться само, поэтому они планируются на 3 дня вперёд и обновляются при каждом открытии Saiya. Тексты подстраиваются под твой день на момент планирования.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Экранное время") {
                    Text("iOS не отдаёт данные Screen Time сторонним приложениям, поэтому их можно вводить вручную в отметке дня.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Данные") {
                    Button("Удалить все локальные данные", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Источники и приватность")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .alert("Удалить все данные?", isPresented: $confirmDelete) {
                Button("Удалить", role: .destructive) { vm.wipe() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Отметки, чат, XP, задания, вода, записи сна и API-ключ будут удалены с этого устройства. Данные Apple Health не затрагиваются.") }
        }
    }
}
