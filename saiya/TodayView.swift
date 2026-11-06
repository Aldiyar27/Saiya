import SwiftUI

struct TodayView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showCheckIn = false
    @State private var showGoal = false
    @State private var showSources = false
    @State private var showWater = false
    @State private var showBreath = false
    @State private var showFocus = false
    @State private var showJournal = false
    @State private var showWeekly = false
    @State private var showScore = false

    var body: some View {
        Nav {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { showScore = true } label: { hero }.buttonStyle(.plain)
                    quickActions
                    quickStats
                    insightCard
                    quoteCard
                    contextCard
                    sleepCard
                    waterCard
                    breathCard
                    missionsCard
                    Button { showCheckIn = true } label: {
                        Label("Как ты сегодня?", systemImage: "face.smiling.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(.borderedProminent).tint(Theme.primary)
                }.padding()
            }
            .refreshable {
                await vm.refreshHealth()
                await vm.refreshContext()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Saiya")
            .toolbar { ToolbarItemGroup(placement: .navigationBarTrailing) { Button { showSources = true } label: { Image(systemName: "gearshape") }; Button { showGoal = true } label: { Image(systemName: "target") } } }
            .sheet(isPresented: $showCheckIn) { CheckInView() }
            .sheet(isPresented: $showGoal) { GoalView() }
            .sheet(isPresented: $showSources) { SourcesView() }
            .sheet(isPresented: $showWater) { WaterView() }
            .sheet(isPresented: $showBreath) { BreathView() }
            .sheet(isPresented: $showFocus) { FocusView() }
            .sheet(isPresented: $showJournal) { JournalView() }
            .sheet(isPresented: $showWeekly) { WeeklyView() }
            .sheet(isPresented: $showScore) { ScoreDetailView() }
            .overlay { if vm.isLoading { ProgressView() } }
        }
    }

    private var hero: some View {
        let score = vm.dayScore
        let name = vm.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(name.isEmpty ? "Твой день" : "\(name), твой день").font(.subheadline).opacity(0.8)
                    Text(score.headline).font(.system(.title, design: .rounded).weight(.bold))
                    Text(score.hint).font(.footnote).opacity(0.85)
                }
                Spacer()
                ScoreRing(score: score.value).frame(width: 78, height: 78)
            }
            HStack(spacing: 10) {
                Label("\(vm.streak) дн. серия", systemImage: "flame.fill")
                Spacer(); Text("Ур. \(vm.level) · \(Levels.title(vm.level))")
            }.font(.caption.bold())
        }
        .foregroundStyle(.white).padding(22).background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickAction(title: "Фокус", icon: "timer", color: Theme.peach) { showFocus = true }
            QuickAction(title: "Дневник", icon: "book.closed.fill", color: Theme.mint) { showJournal = true }
            QuickAction(title: "Итоги", icon: "chart.bar.fill", color: Theme.blue) { showWeekly = true }
        }
    }

    private var quoteCard: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening").font(.title3).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Мысль дня").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(Quotes.today()).font(.system(.callout, design: .rounded).weight(.medium))
                }
            }
        }
    }

    private var quickStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MiniStat(title: "Шаги", value: "\(vm.todaySteps)", icon: "figure.walk", color: Theme.mint)
            MiniStat(title: "Цель", value: "\(vm.stepGoal)", icon: "target", color: Theme.peach)
            MiniStat(title: "Сон", value: vm.lastNight.map { SleepAnalytics.hm($0.asleepHours) } ?? "—", icon: "moon.zzz.fill", color: Theme.blue)
            MiniStat(title: "Вода, мл", value: "\(vm.waterML)", icon: "drop.fill", color: Theme.blue)
            MiniStat(title: "XP", value: "\(vm.xp)", icon: "star.fill", color: Theme.lime)
            MiniStat(title: "Отметок", value: "\(vm.checkIns.count)", icon: "checkmark.seal.fill", color: Theme.blue)
        }
    }

    private var insightCard: some View {
        Card { VStack(alignment: .leading, spacing: 8) { Label("Личный инсайт", systemImage: "sparkles").font(.headline); Text(vm.insight?.summary ?? "Собираю твою динамику…").font(.system(.body, design: .rounded).weight(.medium)); if let p = vm.patternNote { Text(p).font(.footnote) }; Text(vm.usingDemoData ? "Демо-данные" : "Сравнение с твоей личной нормой").font(.caption).foregroundStyle(.secondary) } }
    }

    @ViewBuilder private var contextCard: some View {
        if vm.context.hasData {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Контекст дня", systemImage: "calendar").font(.headline)
                    if let w = vm.context.weather {
                        Label("\(w.tempC)°C · \(w.summary)", systemImage: w.isRainy ? "cloud.rain.fill" : "sun.max.fill")
                    }
                    if let f = vm.context.freeEveningHours {
                        Label("Свободно вечером: ~\(String(format: "%.1f", f)) ч", systemImage: "clock.fill")
                    }
                    if let n = vm.context.eventsToday {
                        Label("Событий сегодня: \(n)", systemImage: "calendar.badge.clock")
                    }
                }.font(.subheadline)
            }
        }
    }

    private var sleepCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Сон", systemImage: "moon.zzz.fill").font(.headline)
                    Spacer()
                    if let n = vm.lastNight { Text(SleepAnalytics.hm(n.asleepHours)).font(.caption.bold()) }
                }
                if let n = vm.lastNight {
                    ProgressView(value: min(n.asleepHours / max(vm.sleepGoal, 1), 1)).tint(Theme.blue)
                    Text("\(vm.nightLabel(n)) · цель \(SleepAnalytics.hm(vm.sleepGoal))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Сон берётся из Apple Health. Пока там пусто — включи «Сон» в приложении «Здоровье» или носи Apple Watch ночью.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var breathCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Подышать", systemImage: "wind").font(.headline)
                    Text("1–3 минуты, чтобы выдохнуть").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Начать") { showBreath = true }.buttonStyle(.borderedProminent).tint(Theme.mint)
            }
        }
    }

    private var waterCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Вода", systemImage: "drop.fill").font(.headline)
                    Spacer()
                    Text("\(vm.waterML) / \(vm.waterGoal) мл").font(.caption.bold())
                }
                ProgressView(value: vm.waterProgress).tint(Theme.blue)
                HStack(spacing: 8) {
                    ForEach([150, 250, 500], id: \.self) { ml in
                        Button("+\(ml)") { vm.addWater(ml) }
                            .buttonStyle(.borderedProminent).tint(Theme.blue)
                    }
                    Spacer()
                    Button("Подробнее") { showWater = true }.font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var missionsCard: some View {
        if !vm.missions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Задания дня", systemImage: "checklist").font(.headline)
                        Spacer()
                        Text("\(vm.missionsDone)/\(vm.missions.count)").font(.caption.bold())
                    }
                    ProgressView(value: Double(vm.missionsDone), total: Double(max(vm.missions.count, 1))).tint(Theme.mint)
                    ForEach(vm.missions) { m in
                        MissionRow(mission: m) { vm.completeMission(m.id) }
                    }
                    if vm.allMissionsDone {
                        Label("Все задания выполнены: бонус +\(AppViewModel.bonusXP) XP", systemImage: "gift.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.peach)
                    }
                }
            }
        }
    }
}

struct MissionRow: View {
    let mission: Mission
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: mission.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(mission.isDone ? Theme.mint : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(mission.isDone || mission.auto != nil)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mission.title).font(.subheadline.weight(.semibold)).strikethrough(mission.isDone)
                    Spacer()
                    Text("+\(mission.xp) XP").font(.caption2.bold()).foregroundStyle(Theme.peach)
                }
                Text(mission.detail).font(.footnote).foregroundStyle(.secondary)
                if mission.auto != nil && !mission.isDone {
                    Text("Засчитается автоматически").font(.caption2).foregroundStyle(Theme.mint)
                }
            }
        }
    }
}

struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
    }
}

struct MiniStat: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View { Card { VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(color); Text(value).font(.system(.title3, design: .rounded).weight(.bold)); Text(title).font(.caption).foregroundStyle(.secondary) } } }
}

struct GoalView: View {
    @EnvironmentObject var vm: AppViewModel; @Environment(\.dismiss) private var dismiss
    @State private var goal = 8000.0
    var body: some View { Nav { Form { Section("Цель по шагам") { Slider(value: $goal, in: 3000...15000, step: 500); Text("\(Int(goal)) шагов в день").font(.headline) } }.navigationTitle("Моя цель").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { vm.setStepGoal(Int(goal)); dismiss() } } } }.onAppear { goal = Double(vm.stepGoal) } }
}
