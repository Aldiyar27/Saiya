import Foundation
import EventKit
import CoreLocation

struct WeatherInfo {
    let tempC: Int
    let isRainy: Bool
    let summary: String
}

struct DayContext {
    var eventsToday: Int?
    var freeEveningHours: Double?
    var weather: WeatherInfo?

    var hasData: Bool { eventsToday != nil || weather != nil }

    var promptLines: [String] {
        var out: [String] = []
        if let n = eventsToday, let f = freeEveningHours {
            out.append("Календарь: сегодня событий \(n), свободно вечером (17–22) около \(String(format: "%.1f", f)) ч")
        }
        if let w = weather {
            out.append("Погода: \(w.tempC)°C, \(w.summary)")
        }
        return out
    }
}

// MARK: - Календарь (EventKit). Читает только занятость на сегодня, ничего не сохраняет.
final class CalendarService {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return (try? await store.requestAccess(to: .event)) ?? false
        }
    }

    func todaySummary() -> (count: Int, freeEvening: Double) {
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay }

        let seventeen = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        let eveStart = max(now, seventeen)
        let eveEnd = cal.date(bySettingHour: 22, minute: 0, second: 0, of: now)!
        guard eveStart < eveEnd else { return (events.count, 0) }

        var busy: [(Date, Date)] = []
        for e in events {
            let a = max(e.startDate, eveStart), b = min(e.endDate, eveEnd)
            if a < b { busy.append((a, b)) }
        }
        busy.sort { $0.0 < $1.0 }

        var busySeconds: TimeInterval = 0
        var current: (Date, Date)?
        for iv in busy {
            if let c = current {
                if iv.0 <= c.1 { current = (c.0, max(c.1, iv.1)) }
                else { busySeconds += c.1.timeIntervalSince(c.0); current = iv }
            } else { current = iv }
        }
        if let c = current { busySeconds += c.1.timeIntervalSince(c.0) }

        let total = eveEnd.timeIntervalSince(eveStart)
        return (events.count, max(0, total - busySeconds) / 3600)
    }
}

// MARK: - Примерное местоположение (≈1 км). Координаты не сохраняются, нужны только для погоды.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async -> CLLocation? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            if status == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { manager.requestLocation() }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ loc: CLLocation?) {
        continuation?.resume(returning: loc)
        continuation = nil
    }
}

// MARK: - Погода (Open-Meteo, без ключа). Координаты округляются до 2 знаков.
enum WeatherService {
    private struct Resp: Decodable {
        struct Cur: Decodable {
            let temperature_2m: Double
            let precipitation: Double
            let weather_code: Int
        }
        let current: Cur
    }

    static func fetch(lat: Double, lon: Double) async -> WeatherInfo? {
        let la = (lat * 100).rounded() / 100, lo = (lon * 100).rounded() / 100
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(la)&longitude=\(lo)&current=temperature_2m,precipitation,weather_code&timezone=auto"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Resp.self, from: data) else { return nil }
        let code = r.current.weather_code
        let rainy = code >= 51 || r.current.precipitation > 0
        return WeatherInfo(tempC: Int(r.current.temperature_2m.rounded()),
                           isRainy: rainy, summary: describe(code))
    }

    private static func describe(_ c: Int) -> String {
        switch c {
        case 0: return "ясно"
        case 1...3: return "облачно"
        case 45, 48: return "туман"
        case 51...57: return "морось"
        case 61...67: return "дождь"
        case 71...77: return "снег"
        case 80...82: return "ливни"
        case 85, 86: return "снегопад"
        case 95...99: return "гроза"
        default: return "без осадков"
        }
    }
}
