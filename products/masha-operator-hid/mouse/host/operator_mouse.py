#!/usr/bin/env python3
"""Send one bounded relative mouse event to the HAKRCF405V2 bridge."""

import argparse
import sys

BUTTONS = {"none": 0, "left": 1, "right": 2, "middle": 4}


def parse_arguments():
    parser = argparse.ArgumentParser(description="Send one USB mouse event through UART4.")
    parser.add_argument("--port", required=True, help="USB-UART serial port, for example /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--dx", type=int, default=0, help="relative horizontal movement, -127..127")
    parser.add_argument("--dy", type=int, default=0, help="relative vertical movement, -127..127")
    parser.add_argument("--wheel", type=int, default=0, help="wheel ticks, -127..127")
    parser.add_argument("--button", choices=sorted(BUTTONS), default="none")
    return parser.parse_args()


def encode_signed(value):
    if value < -127 or value > 127:
        raise ValueError("movement and wheel values must be between -127 and 127")
    return value & 0xFF


def encode_mouse_frame(buttons, dx, dy, wheel):
    if buttons & ~0x07:
        raise ValueError("button mask must use only the three supported buttons")
    dx_byte = encode_signed(dx)
    dy_byte = encode_signed(dy)
    wheel_byte = encode_signed(wheel)
    if buttons == 0 and dx == 0 and dy == 0 and wheel == 0:
        raise ValueError("event must move, scroll, or press one mouse button")
    fields = (0xA6, buttons, dx_byte, dy_byte, wheel_byte)
    return bytes((*fields, fields[0] ^ fields[1] ^ fields[2] ^ fields[3] ^ fields[4]))


def send_event(args):
    buttons = BUTTONS[args.button]
    frame = encode_mouse_frame(buttons, args.dx, args.dy, args.wheel)
    try:
        import serial
    except ImportError as error:
        raise RuntimeError("pyserial is required: python3 -m pip install pyserial") from error

    try:
        with serial.Serial(args.port, args.baud, timeout=1.5, write_timeout=1.5) as port:
            port.reset_input_buffer()
            port.write(frame)
            port.flush()
            response = port.read(3)
    except (OSError, serial.SerialException) as error:
        raise RuntimeError(f"UART error on {args.port}: {error}") from error

    if response != b"ACK":
        detail = response.decode("ascii", errors="replace") or "no response"
        raise RuntimeError(f"controller did not acknowledge mouse event: {detail}")
    print("Mouse event acknowledged by flight controller.")


def main():
    args = parse_arguments()
    try:
        send_event(args)
    except (RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
