# Sofle ZMK — Functions Manual (English)

> Written as a walkthrough for learning every feature on this keymap, function by function.
> All GLIP/Confluence/JIRA external messages in English — learn the product in English.

---

## 0. Orientation

- **60 keys, 5 layers.** This manual is the memory of that layout: read it once to plan, print it near the desk to memorize, re-read it to un-stick.
- The keyboard is a *split* Sofle V2 (left + right halves). Both halves are independent over BLE/TRRS; the config builds both.

---

## 1. The Layers Matrix

| Layer | What it is | How to reach | Purpose |
|-------|-----------|--------------|---------|
| 0 | Default | always on | typing, QWERTY |
| 1 | Lower | hold `MO1` | F-keys, symbols, arrows, HOME/END |
| 2 | Raise | hold `MO2` | Bluetooth, output, mouse, media |
| 3 | Lock | combo `LCTRL+RCTRL` 2s | nothing (lock) |
| 4 | Macro | combo `MO1+MO2` | record/play macros |

Notes:

- `MO1` and `MO2` are *momentary*: press and hold to enter, release to return.
- Layer 4 is *toggled*: one press in, second press out.
- Layers stack above Default; the highest active layer wins.

---

## 2. Home-Row Mods (Layer 0)

The home row doubles as modifiers. Tap = letter, **hold** = modifier.

| Key | Tap | Hold (mod) |
|-----|-----|-----------|
| A | `a` | GUI (Cmd) |
| S | `s` | ALT (Option) |
| D | `d` | CTRL |
| F | `f` | SHIFT |
| J | `j` | SHIFT |
| K | `k` | CTRL |
| L | `l` | ALT (Option) |
| ; | `;` | GUI; tap-tap `:` |
| ' | `'` | tap-tap `"` |

**Practice**: press and hold `F` while typing `d` → you get *Shift+d* (capital D). Release `F`, tap `f` again → lower-case f.

**Timing**: hold `D` and tap `C` quickly for Ctrl-C; everything releases cleanly.

---

## 3. Key Behavior Details (Layer 0)

### ESC / grave
- **Tap** → Esc. **Hold** → \` (grave / backtick).

### Backspace
- **Tap** → Backspace.

### Shift morphs (bottom row)
- Press `⇧` alone → Shift.
- Press `⇧` while the *other* shift is held → the pair outputs \` (left) or `~` (right).

### Combo ALT + Backspace
- Press `ALT` and `BSPC` together → **delete previous word** (Option+Backspace on macOS).

### Combo j → k → j = Esc (planned)
- *In the next version:* typing `j`, `k`, `j` as a normal sequence (no modifiers) emits **Escape**.
- Currently enabled: the `J+K` simultaneous combo is removed — J and K are plain letters.

---

## 4. Layer 1 (Lower) — F-keys, symbols, arrows

Access: **hold `MO1`** (left thumb key 53).

| Group | Keys |
|-------|------|
| F-keys | `F1`–`F12` (top row) |
| Numbers | `1`–`5` → top row under row 1; `6-0` hidden on right |
| Symbols | `! @ # $ %` on row 2, `= - +` on row 3, `[ ] ( )` etc. |
| Navigation | `HOME`, `PGDN`, arrows `← ↓ ↑ →` |
| Misc | `PRSC` (print screen) on right thumb |

Notes:

- On layer 1 the number rows are mirrored: left top = `F1`–`F5`, right top = `F6`–`F11`, and `F12` (pos 23).
- `HOME`/`PGDN` are handy for line jumps in terminal.

---

## 5. Layer 2 (Raise) — Bluetooth, output, mouse, media

Access: **hold `MO2`** (right thumb key 56).

| Group | Keys |
|-------|------|
| Bluetooth | `BT0`–`BT4` (top row left: profiles 0-4) |
| Output | `OUT_USB` / `OUT_BLE` / `OUT_TOG` (top row right) |
| Bluetooth clear | `BTCLR` (pos 11) |
| Insert / screenshot / menu | `INS`, `PSCRN`, `K_CMENU` (row 1) |
| Scroll | `SCRL` arrows (row 1) |
| Mouse | `M←`, `M↓`, `M↑`, `M→`, rows 2-3, mouse click `LCLK`/`RCLK` |
| Media | `MUTE`, `V-`, `V+` (row 3) |
| Symbols | `- + = _` (row 2) |

Notes:

- Mouse movement multiplies 3× when `SHIFT` is held.
- Use `OUT_TOG` to toggle between USB and BLE on the fly.
- `BT0`–`BT4` select the Bluetooth profile; `BTCLR` clears all pairings (useful on resets).

---

## 6. Layer 3 (Lock)

Access: hold `LCTRL` + `RCTRL` (thumb corners, pos 50 + 59) for **2 seconds**.

Result: every key is `&none` — the keyboard sends nothing.

Unlock: the only rising edge is `ESC`+`MINUS` (pos 0 + 11) for 2s → back to Default.

---

## 7. Layer 4 (Macro) — record and play

Access: **press `MO1` + `MO2` together** (toggle into layer 4). Same combo toggles it off.

| Key | Action |
|-----|--------|
| A | REC slot 0 |
| S | REC slot 1 |
| D | STOP |
| F | CANCEL |
| J | PLAY slot 0 |
| K | PLAY slot 1 |
| L | CLEAR slot 0 |
| ; | CLEAR slot 1 |

Flow for a `git commit` script:

1. `MO1+MO2` → layer 4 on.
2. Tap `A` → recording slot 0.
3. `MO1+MO2` → back to typing, then type `git commit -am "message"`.
4. `MO1+MO2` → layer 4 on again, tap `D` → stop + save.
5. Tap `J` → replay slot 0 anywhere on any layer.

Rules:

- Recording starts automatically when active; tap `A`/`S` again while recording = stop + save.
- Keys recorded: keyboard, consumer/media. **Not recorded**: pointing, layers, Bluetooth, reset.
- A new REC on a slot clears that slot first.
- `PLAY` while recording = stop + save (does not start another playback).
- `CANCEL` aborts and restores the previous macro of the slot (if any).

---

## 8. Combos (summary table)

| Combo | Result |
|-------|--------|
| `ALT + BSPC` | delete previous word |
| `LCTRL + RCTRL` (2s) | lock |
| `ESC + MINUS` (2s, from lock) | unlock |
| `MO1 + MO2` | toggle macro layer (4) |

---

## 9. What does NOT depend on the app

- All features live in firmware (ZMK), so they work in **any** editor, terminal, browser, or OS.
- macOS binds (Cmd, Option, Globe) are baked into the layout.

---

## 10. Quick reference — memorize this

```
Layer 0  A=GUI S=ALT D=CTRL F=SHIFT | J=SHIFT K=CTRL L=ALT ;=GUI
Esc      tap Esc  hold ~ (grave)
BSPC     tap BS
ALT+BSPC → delete word

Layer 1  hold MO1:  F-keys, numbers, arrows, HOME/PGDN
Layer 2  hold MO2:  BT profiles, USB/BLE toggle, mouse, media
Layer 3  LCTRL+RCTRL 2s → lock;  ESC+MINUS 2s → unlock
Layer 4  MO1+MO2    → REC A/S, STOP D, CANCEL F, PLAY J/K, CLEAR L/;
```