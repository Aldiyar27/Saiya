import SwiftUI

/// Одна составляющая «Баланса дня».
struct ScorePart: Identifiable {
    let id: String
    let title: String
    let icon: String
    /// 0...1
    let value: Double
    let weight: Double
    let detail: String
    let color: Color
}

/// «Баланс дня» 0–100: сон, шаги, вода, задания и самочувствие.
/// Это не медицинская оценка, а игровой индикатор прогресса за сегодня.
struct DayScore {
    let parts: [ScorePart]

    var value: Int {
        let total = parts.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let sum = parts.reduce(0) { $0 + $1.value * $1.weight }
        return min(max(Int((sum / total * 100).rounded()), 0), 100)
    }

    var headline: String {
        switch value {
        case 80...: return "Отличный ритм"
        case 60..<80: return "Хороший ход"
        case 35..<60: return "Набираем обороты"
        default: return "Начни с малого"
        }
    }

    var weakest: ScorePart? { parts.min { $0.value < $1.value } }

    var hint: String {
        if let w = weakest, w.value < 0.8 {
            return "Сильнее всего прибавит: \(w.title.lowercased())"
        }
        return "Всё идёт ровно — так держать"
    }
}

/// Названия уровней.
enum Levels {
    static let names = ["Росток", "Путник", "Искатель", "Ритм", "Опора", "Мастер баланса", "Сенсей", "Легенда"]

    static func title(_ level: Int) -> String {
        names[min(max(level, 1), names.count) - 1]
    }
}

struct ScoreRing: View {
    let score: Int
    var lineWidth: CGFloat = 8
    var tint: Color = .white
    var track: Color = Color.white.opacity(0.25)

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: score)
            VStack(spacing: 0) {
                Text("\(score)").font(.system(.title2, design: .rounded).weight(.bold))
                Text("баланс").font(.system(size: 9, weight: .medium)).opacity(0.8)
            }
            .foregroundStyle(tint)
        }
    }
}

/// Разбор баланса дня по составляющим.
struct ScoreDetailView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let score = vm.dayScore
        return Nav {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        VStack(spacing: 12) {
                            ScoreRing(score: score.value, lineWidth: 16, tint: Theme.mint, track: Theme.mint.opacity(0.15))
                                .frame(width: 170, height: 170)
                            Text(score.headline).font(.system(.title2, design: .rounded).weight(.bold))
                            Text(score.hint).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Из чего складывается").font(.headline)
                            ForEach(score.parts) { p in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(p.title, systemImage: p.icon).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("\(Int((p.value * 100).rounded()))%").font(.caption.bold()).monospacedDigit()
                                    }
                                    ProgressView(value: p.value).tint(p.color)
                                    Text(p.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("Баланс дня — игровой индикатор прогресса за сегодня. Это не медицинская оценка.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Баланс дня")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
