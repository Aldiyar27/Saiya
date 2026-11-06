import SwiftUI

struct JourneyView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showWeekly = false
    @State private var showJournal = false

    var body: some View {
        Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    levelCard
                    streakCard
                    actions
                    moodCard
                    badgesCard
                    history
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Мой путь")
            .sheet(isPresented: $showWeekly) { WeeklyView() }
            .sheet(isPresented: $showJournal) { JournalView() }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            QuickAction(title: "Итоги недели", icon: "chart.bar.fill", color: Theme.blue) { showWeekly = true }
            QuickAction(title: "Дневник", icon: "book.closed.fill", color: Theme.mint) { showJournal = true }
        }
    }

    private var moodCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Динамика самочувствия", subtitle: "Последние отметки дня")
                MoodChart(checkIns: vm.checkIns)
            }
        }
    }

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Награды", subtitle: "\(vm.badges.filter { $0.unlocked }.count) из \(vm.badges.count)")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(vm.badges) { b in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: b.icon).font(.title2)
                                .foregroundStyle(b.unlocked ? Theme.peach : Color.gray.opacity(0.5))
                            Text(b.title).font(.subheadline.weight(.semibold))
                            Text(b.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }.opacity(b.unlocked ? 1 : 0.55)
                }
            }
        }
    }

    private var levelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Уровень \(vm.level)").font(.system(.title, design: .rounded).weight(.bold))
                        Text(Levels.title(vm.level)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
                        Text("\(vm.xp) XP").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(Theme.peach)
                }
                ProgressView(value: Double(vm.xp % 100), total: 100).tint(Theme.mint)
                Text("До следующего уровня: \(100 - vm.xp % 100) XP").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var streakCard: some View {
        Card {
            HStack {
                Image(systemName: "flame.fill").font(.largeTitle).foregroundStyle(Theme.peach)
                VStack(alignment: .leading) {
                    Text("Серия отметок").font(.headline)
                    Text("\(vm.streak) дней подряд").font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Отмечай самочувствие каждый день").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Последние отметки", subtitle: "Твоя история самочувствия")
            if vm.checkIns.isEmpty {
                Card { Text("Пока нет отметок. Начни с экрана «Сегодня».").foregroundStyle(.secondary) }
            } else {
                ForEach(vm.checkIns.suffix(10).reversed()) { c in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(c.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text("\(MoodEmoji.emoji(c.mood)) \(c.mood)  ⚡ \(c.energy)  •  😣 \(c.stress)")
                                    .font(.caption).monospacedDigit()
                            }
                            if let note = c.note {
                                Text(note).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
