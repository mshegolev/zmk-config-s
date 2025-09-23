# Sofle V2 ZMK Firmware

A split keyboard firmware configuration for Sofle V2 using ZMK.

## Configuration Resources

* [Configuration Page](https://nickcoutsos.github.io/keymap-editor/)
* [Manual (Russian)](https://habr.com/ru/articles/703022/)
* [Typing Practice Tools](https://www.keybr.com/) (https://monkeytype.com)

## Flashing Instructions

1. Generate UF2 files using GitHub Actions from the [configuration page](https://nickcoutsos.github.io/keymap-editor/)
2. Download firmware to your downloads directory (e.g., `firmware_1`)
3. Set the download directory path in the `utils/flash_sofle.sh` script
4. Connect the left keyboard to your MacBook via USB-C
5. Run the script and follow these steps:
   - Double-click the reset button
   - Wait for the upgrade to complete
   - Switch to the right keyboard and repeat
6. After flashing both halves, power cycle the keyboard and you're ready to type

## Important Notes

* Always disconnect USB before connecting/disconnecting TRRS cable
* Be gentle with USB ports on your microcontrollers
* This is a DIY keyboard prototype, not a polished product
