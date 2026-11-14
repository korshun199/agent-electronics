#!/usr/bin/env python3
"""Погода с бесплатного Open-Meteo. Ключ не нужен."""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request

GEO_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"


def fail(message):
    """Печатает ошибку и завершает программу."""
    print(f"Ошибка: {message}", file=sys.stderr)
    return 1


def fetch_json(url):
    """Запрашивает JSON и проверяет ответ сервера."""
    request = urllib.request.Request(url, headers={"User-Agent": "weather-desk/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            status = getattr(response, "status", 200)
            if status != 200:
                raise RuntimeError(f"сервер ответил {status}")
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        raise RuntimeError(f"нет связи: {error.reason}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"ответ не JSON: {error}") from error


def find_place(name):
    """Ищет место по названию и возвращает первую найденную точку."""
    query = urllib.parse.urlencode(
        {"name": name, "count": 1, "language": "ru", "format": "json"}
    )
    data = fetch_json(f"{GEO_URL}?{query}")
    results = data.get("results") or []
    if not results:
        raise RuntimeError(f"место не найдено: {name}")
    return results[0]


def fetch_weather(place):
    """Берёт текущую погоду для найденных координат."""
    query = urllib.parse.urlencode(
        {
            "latitude": place["latitude"],
            "longitude": place["longitude"],
            "current": "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m",
            "timezone": "auto",
        }
    )
    data = fetch_json(f"{FORECAST_URL}?{query}")
    current = data.get("current")
    if not current:
        raise RuntimeError("в ответе нет текущей погоды")
    return current


def describe_code(code):
    """Коротко описывает код погоды WMO."""
    names = {
        0: "ясно",
        1: "преимущественно ясно",
        2: "переменная облачность",
        3: "пасмурно",
        45: "туман",
        48: "туман с изморозью",
        51: "морось",
        61: "дождь",
        71: "снег",
        80: "ливень",
        95: "гроза",
    }
    return names.get(code, f"код {code}")


def main():
    """Читает город из аргумента и печатает погоду."""
    if len(sys.argv) != 2:
        print("Использование: python3 weather.py <город>")
        return 1
    try:
        place = find_place(sys.argv[1])
        weather = fetch_weather(place)
    except RuntimeError as error:
        return fail(str(error))
    city = place.get("name", sys.argv[1])
    country = place.get("country", "")
    print(f"{city}, {country}")
    print(f"Температура: {weather.get('temperature_2m')} °C")
    print(f"Влажность: {weather.get('relative_humidity_2m')} %")
    print(f"Ветер: {weather.get('wind_speed_10m')} км/ч")
    print(f"Сейчас: {describe_code(weather.get('weather_code'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
