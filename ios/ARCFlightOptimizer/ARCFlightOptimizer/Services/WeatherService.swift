import Foundation

enum WeatherService {
    static func lookup(location: String) async throws -> Weather {
        let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
        let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encodedLocation)&count=1&language=en&format=json")!
        let (geoData, geoResponse) = try await URLSession.shared.data(from: geoURL)
        guard (geoResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw WeatherError.locationLookupFailed
        }

        let geo = try JSONDecoder().decode(GeoResponse.self, from: geoData)
        guard let place = geo.results?.first else {
            throw WeatherError.noLocationMatch
        }

        let weatherURL = URL(
            string: "https://api.open-meteo.com/v1/forecast?latitude=\(place.latitude)&longitude=\(place.longitude)&current=temperature_2m,relative_humidity_2m,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph"
        )!
        let (weatherData, weatherResponse) = try await URLSession.shared.data(from: weatherURL)
        guard (weatherResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw WeatherError.weatherLookupFailed
        }

        let weather = try JSONDecoder().decode(OpenMeteoResponse.self, from: weatherData)
        let resolved = [place.name, place.admin1, place.country].compactMap { $0 }.joined(separator: ", ")

        return Weather(
            temperatureF: weather.current.temperature,
            windMPH: weather.current.windSpeed,
            humidityPercent: weather.current.humidity,
            location: resolved
        )
    }

    static func lookup(latitude: Double, longitude: Double, label: String) async throws -> Weather {
        let weatherURL = URL(
            string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,relative_humidity_2m,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph"
        )!
        let (weatherData, weatherResponse) = try await URLSession.shared.data(from: weatherURL)
        guard (weatherResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw WeatherError.weatherLookupFailed
        }

        let weather = try JSONDecoder().decode(OpenMeteoResponse.self, from: weatherData)
        return Weather(
            temperatureF: weather.current.temperature,
            windMPH: weather.current.windSpeed,
            humidityPercent: weather.current.humidity,
            location: label
        )
    }
}

enum WeatherError: LocalizedError {
    case locationLookupFailed
    case noLocationMatch
    case weatherLookupFailed

    var errorDescription: String? {
        switch self {
        case .locationLookupFailed: return "Location lookup failed."
        case .noLocationMatch: return "No matching launch-site location was found."
        case .weatherLookupFailed: return "Weather lookup failed."
        }
    }
}

private struct GeoResponse: Decodable {
    var results: [GeoResult]?
}

private struct GeoResult: Decodable {
    var name: String
    var admin1: String?
    var country: String?
    var latitude: Double
    var longitude: Double
}

private struct OpenMeteoResponse: Decodable {
    var current: CurrentWeather
}

private struct CurrentWeather: Decodable {
    var temperature: Double
    var humidity: Double
    var windSpeed: Double

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case windSpeed = "wind_speed_10m"
    }
}
