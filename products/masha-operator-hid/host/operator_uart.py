#!/usr/bin/env python3
"""Посылает одну разрешённую клавишу полётнику по UART4."""

import argparse
import sys


# Соответствие коротких имён клавиш кодам HID Keyboard/Keypad.
KEYS = {
    **{letter: 0x04 + index for index, letter in enumerate("abcdefghijklmnopqrstuvwxyz")},
    "1": 0x1E,
    "2": 0x1F,
    "3": 0x20,
    "4": 0x21,
    "5": 0x22,
    "6": 0x23,
    "7": 0x24,
    "8": 0x25,
    "9": 0x26,
    "0": 0x27,
    "enter": 0x28,
    "esc": 0x29,
    "backspace": 0x2A,
    "tab": 0x2B,
    "space": 0x2C,
    "minus": 0x2D,
    "equal": 0x2E,
    "leftbracket": 0x2F,
    "rightbracket": 0x30,
    "backslash": 0x31,
    "semicolon": 0x33,
    "apostrophe": 0x34,
    "grave": 0x35,
    "comma": 0x36,
    "dot": 0x37,
    "slash": 0x38,
}

# Битовые позиции модификаторов в стандартном отчёте USB-клавиатуры.
MODIFIERS = {"ctrl": 0x01, "shift": 0x02, "alt": 0x04}


def parse_arguments():
    """Разбирает порт, одну клавишу и необязательные модификаторы."""
    parser = argparse.ArgumentParser(
        description="Однократное нажатие USB-клавиши через UART4 полётника."
    )
    parser.add_argument("--port", required=True, help="USB-UART порт, например /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200, help="скорость UART, по умолчанию 115200")
    parser.add_argument("key", choices=sorted(KEYS), help="имя клавиши, например a, enter или space")
    parser.add_argument("--ctrl", action="store_true", help="добавить Ctrl")
    parser.add_argument("--shift", action="store_true", help="добавить Shift")
    parser.add_argument("--alt", action="store_true", help="добавить Alt")
    return parser.parse_args()


def send_keypress(args):
    """Передаёт кадр с XOR-проверкой и требует ACK от прошивки."""
    try:
        import serial
    except ImportError as error:
        raise RuntimeError("Не найден pyserial. Установи: python3 -m pip install pyserial") from error

    modifier = (
        (MODIFIERS["ctrl"] if args.ctrl else 0)
        | (MODIFIERS["shift"] if args.shift else 0)
        | (MODIFIERS["alt"] if args.alt else 0)
    )
    usage = KEYS[args.key]
    magic = 0xA5
    frame = bytes((magic, modifier, usage, magic ^ modifier ^ usage))

    try:
        with serial.Serial(args.port, args.baud, timeout=1.5, write_timeout=1.5) as port:
            port.reset_input_buffer()
            port.write(frame)
            port.flush()
            response = port.read(3)
    except (OSError, serial.SerialException) as error:
        raise RuntimeError(f"Ошибка UART {args.port}: {error}") from error

    if response != b"ACK":
        detail = response.decode("ascii", errors="replace") or "нет ответа"
        raise RuntimeError(f"Полётник не подтвердил клавишу: {detail}")

    print(f"Клавиша {args.key!r} отправлена и принята полётником.")


def main():
    """Возвращает код завершения с коротким сообщением об ошибке."""
    args = parse_arguments()
    try:
        send_keypress(args)
    except RuntimeError as error:
        print(f"Ошибка: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
