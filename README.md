# Sofle V2 ZMK Firmware

A split keyboard firmware configuration for Sofle V2 using ZMK. Two halves (`left`/`right`), flashed via GitHub Actions, used across two macOS machines (one USB, one Bluetooth).

## Overview

* **Board:** nice!nano v2 × 2 (left + right)
* **Shield:** Sofle V2 split keyboard (60 keys, no encoders)
* **Connectivity:** USB + Bluetooth (up to 4 BT profiles, output switching USB/BLE/TOG)
* **Layouts:** 4 typing layers (default / lower / raise / macro) + lock
* **Visual editor:** [open config in Keymap Editor](https://nickcoutsos.github.io/keymap-editor/?repo=mshegolev/zmk-config-s)

## Layer Map

| Layer | Access | Purpose |
|-------|--------|---------|
| 0 Default | always active | QWERTY + home-row mods |
| 1 Lower | hold `MO1` (left thumb, pos 53) | F-keys, numbers, symbols, arrows |
| 2 Raise | hold `MO2` (right thumb, pos 56) | Bluetooth, output, mouse, media |
| 3 Lock | combo `LCTRL+RCTRL` hold 2s | all keys disabled |
| 4 Macro | combo `MO1+MO2` toggle | runtime macro record / play |

Quick reference:

* `LCTRL+RCTRL` (hold 2s) → **Lock**. `ESC+MINUS` (hold 2s) → **Unlock**.
* `MO1` = layer 1 while held (left thumb), `MO2` = layer 2 while held (right thumb).
* Position 58 = `GLOBE` (macOS Fn key). Bottom thumb row: CTRL · ALT · GUI · MO1 · SPC · SPC · MO2 · ENT · GLOBE · RCTRL.

## Default Layer — Home-Row Mods

The home row doubles as modifiers. Tap types the letter, hold presses the modifier.

| Key | Tap | Hold |
|-----|-----|------|
| A (pos 25) | `a` | GUI (Cmd) |
| S (pos 26) | `s` | ALT (Option) |
| D (pos 27) | `d` | CTRL |
| F (pos 28) | `f` | SHIFT |
| H (pos 30) | `h` | — |
| J (pos 31) | `j` | SHIFT |
| K (pos 32) | `k` | CTRL |
| L (pos 33) | `l` | ALT (Option) |
| ; (pos 34) | `;` | GUI (Cmd); tap-tap `:` |
| ' (pos 35) | `'` | —; tap-tap `"` |

Other behaviors on the default layer:

* **ESC** (pos 0) — tap = Esc, hold = `` ` `` (grave).
* **BACKSPACE** (pos 23) — Backspace only (hold-tap DEL is defined but not bound).
* **Shift morphs** — bottom-row shifts: `lshift_grave` (pos 36) = LSHIFT, but if RSHIFT is held too → `` ` ``. `rshift_tilde` (pos 49) = RSHIFT, but if LSHIFT is held too → `~`.
* **Combo `ALT+BSPC`** — delete previous word (Option+Backspace on macOS).

## Lower Layer (1) — hold MO1

| Group | Keys |
|-------|------|
| F-keys | `F1`–`F12` (top row + pos 23) |
| Numbers | `1`–`8` (row 1) |
| Symbols | `` ` `` (pos 0), `! @ # $` (row 2), `= - +` (row 3), `[ ] ( ) \ ; :` (row 3) |
| Nav | `HOME` (pos 28), `PGDN` (pos 29), arrows `← ↓ ↑ →` (pos 30–33) |
| Misc | `PRSC` (print screen, pos 59) |

## Raise Layer (2) — hold MO2

| Group | Keys |
|-------|------|
| Bluetooth | `BT0`–`BT4` (pos 1–5) |
| Output | `OUT_USB` (pos 6), `OUT_BLE` (pos 7), `OUT_TOG` (pos 8) |
| BT clear | `BTCLR` (pos 11) |
| Utilities | `INS` (pos 13), `PSCRN` (pos 14), `K_CMENU` (pos 15, context menu) |
| Scroll | `SCRL` arrows (pos 18–21) |
| Mouse | `M← M↓ M↑ M→` (pos 30–33, Shift = 3× speed), `LCLK` (pos 44), `RCLK` (pos 45) |
| Media | `MUTE` (pos 37), `VOL-` (pos 38), `VOL+` (pos 39) |
| Symbols | `- + = _` (pos 25–28) |

## Lock Layer (3)

Access: hold `LCTRL` + `RCTRL` (pos 50 + 59) for 2 seconds. All keys disabled. Unlock: `ESC` + `MINUS` (pos 0 + 11) for 2 seconds.

## Macro Layer (4) — toggle MO1+MO2

Access: press `MO1` + `MO2` together (toggle). Same combo toggles it off.

Record a sequence on the fly, then replay it on any layer.

| Key | Action |
|-----|--------|
| A (pos 25) | REC slot 0 |
| S (pos 26) | REC slot 1 |
| D (pos 27) | STOP |
| F (pos 28) | CANCEL |
| J (pos 31) | PLAY slot 0 |
| K (pos 32) | PLAY slot 1 |
| L (pos 33) | CLEAR slot 0 |
| ; (pos 34) | CLEAR slot 1 |

Workflow:
1. `MO1+MO2` → macro layer on.
2. Tap `A` → recording into slot 0.
3. `MO1+MO2` (or `D`) → stop; back to typing.
4. `MO1+MO2` → macro layer on again.
5. Tap `J` → slot 0 replays.

## Planned (next version)

* **jkj Escape** — `j→k→j` sequence via `zmk-sequences`.

## Flashing Instructions

1. Generate UF2 files using GitHub Actions from the [keymap editor](https://nickcoutsos.github.io/keymap-editor/?repo=mshegolev/zmk-config-s).
2. Download firmware to your downloads directory (e.g. `firmware_1`).
3. Set the download directory path in `utils/flash_sofle.sh`.
4. Connect the left keyboard to your MacBook via USB-C.
5. Run the script and follow the steps:
   - Double-click the reset button.
   - Wait for the upgrade to complete.
   - Switch to the right keyboard and repeat.
6. After flashing both halves, power-cycle the keyboard.

## Configuration Resources

* [ZMK keymap editor](https://nickcoutsos.github.io/keymap-editor/?repo=mshegolev/zmk-config-s) — visual editor, see all layers
* [ZMK docs](https://zmk.dev/docs)
* [Sofle manual (Russian)](https://habr.com/ru/articles/703022/)
* [Typing practice](https://www.keybr.com/) / [monkeytype](https://monkeytype.com)

## Important Notes

* Always disconnect USB before connecting/disconnecting the TRRS cable.
* Be gentle with the USB ports on the microcontrollers.
* This is a DIY keyboard prototype, not a polished product.