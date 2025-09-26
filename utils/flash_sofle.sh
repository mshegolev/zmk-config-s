#!/bin/bash
set -e

MOUNT_DIR="$HOME/nicenano_mount"
DOWNLOADS="$HOME/Downloads/firmware (2)"
PASS_FILE="$HOME/pss_file"

FORCE_MODE=0

# ===== Обработка аргументов =====
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--force" ]; then
        FORCE_MODE=1
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]}"

# ===== Читаем пароль =====
if [ ! -f "$PASS_FILE" ]; then
    echo "❌ Файл с паролем не найден: $PASS_FILE"
    exit 1
fi
SUDO_PASS=$(cat "$PASS_FILE")

# ===== HELP =====
show_help() {
    cat <<EOF
🚀 Sofle Flash Utility (из "$DOWNLOADS")

Использование:
  ./flash_sofle.sh [target] [--force]

target:
  all       - прошить обе половины (правую → левую)
  left      - только левую половину
  right     - только правую половину
  reset     - прошивка reset (очистка BT и настроек)
  btpairs   - показать список Bluetooth-пар (BT1..BT5)
  btclear   - очистить все BT-пары и сразу перепрошить обе половины

options:
  --force   - отключить предупреждения (для автоматизации)
EOF
}

# ===== Поиск последних файлов .uf2 =====
find_firmware() {
    LEFT_FIRMWARE=$(ls -t "$DOWNLOADS"/sofle_left-*.uf2 2>/dev/null | head -n1)
    RIGHT_FIRMWARE=$(ls -t "$DOWNLOADS"/sofle_right-*.uf2 2>/dev/null | head -n1)
    RESET_FIRMWARE=$(ls -t "$DOWNLOADS"/settings_reset-*.uf2 2>/dev/null | head -n1)

    if [ -z "$LEFT_FIRMWARE" ] || [ -z "$RIGHT_FIRMWARE" ]; then
        echo "❌ Не найдены прошивки в $DOWNLOADS"
        exit 1
    fi

    echo "✅ Найдены прошивки:"
    echo "   Левая  = $LEFT_FIRMWARE"
    echo "   Правая = $RIGHT_FIRMWARE"
    [ -n "$RESET_FIRMWARE" ] && echo "   Reset  = $RESET_FIRMWARE"
}

# ===== ПРОШИВКА =====
flash_half() {
    local fw_file="$1"
    local half_name="$2"

    if [ ! -f "$fw_file" ]; then
        echo "❌ Файл прошивки не найден: $fw_file"
        exit 1
    fi

    if [ $FORCE_MODE -eq 0 ]; then
        echo "⚠️  Перед прошивкой $half_name отключи обе половины клавиатуры!"
        echo "   Подключи по USB только $half_name и нажми 2 раза reset."
        sleep 2
    fi

    while true; do
        MOUNT_POINT=$(ls /Volumes | grep -iE "NICENANO" | head -n 1)
        if [ -n "$MOUNT_POINT" ]; then
            echo "$(date) - $half_name подключена: /Volumes/$MOUNT_POINT"

            DEVICE=$(df | grep "/Volumes/$MOUNT_POINT" | awk '{print $1}' | sed 's|/dev/||')
            [ -z "$DEVICE" ] && DEVICE="disk4"

            echo "$SUDO_PASS" | sudo -S diskutil unmount "/Volumes/$MOUNT_POINT" || true
            [ ! -d "$MOUNT_DIR" ] && mkdir -p "$MOUNT_DIR"

            echo "$SUDO_PASS" | sudo -S mount -t msdos -o rw,auto,nobrowse "/dev/$DEVICE" "$MOUNT_DIR" || {
                echo "❌ Ошибка монтирования"
                exit 1
            }

            cp "$fw_file" "$MOUNT_DIR/" && echo "✅ $half_name успешно прошита"
            echo "$SUDO_PASS" | sudo -S diskutil unmount "$MOUNT_DIR" || true
            break
        fi
        sleep 1
    done
}

# ===== ПАРСИНГ BT-ПАР =====
show_btpairs() {
    echo "$(date) - 🔍 Сканируем BT-пары..."

    PORT=$(ls /dev/tty.usbmodem* 2>/dev/null | head -n1)
    if [ -z "$PORT" ]; then
        echo "❌ Не найден USB-порт для nice!nano"
        exit 1
    fi
    echo "✅ Найден порт: $PORT"

    echo "👉 Читаем последние 50 строк лога ZMK..."
    LOG=$(timeout 5 cat "$PORT" 2>/dev/null | tail -n 50)

    echo "---- 🔗 Найденные BT-профили ----"
    echo "$LOG" | grep "Active BLE profile" | sed -E 's/.*Active BLE profile ([0-9]+): (.*)/BT\1 → \2/'
    echo "--------------------------------"
}

# ===== ОЧИСТКА BT-ПАР + авто-перепрошивка =====
clear_btpairs() {
    find_firmware
    if [ -z "$RESET_FIRMWARE" ]; then
        echo "❌ Reset-прошивка не найдена в $DOWNLOADS"
        exit 1
    fi
    echo "$(date) - ⚠️ Сначала будет прошивка reset, все BT-пары удалятся!"
    flash_half "$RESET_FIRMWARE" "reset-прошивкой"
    echo "✅ Все BT-пары очищены"

    echo "$(date) - 🔄 Перепрошиваем обе половины (правую → левую)..."
    flash_half "$RIGHT_FIRMWARE" "правую половину"
    flash_half "$LEFT_FIRMWARE" "левую половину"
    echo "✅ Обе половины перепрошиты"
}

# ===== ОСНОВНОЙ БЛОК =====
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

TARGET="$1"

echo "$(date) - 🚀 Автоматическая прошивка Sofle V2"

case "$TARGET" in
    all)
        find_firmware
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        flash_half "$LEFT_FIRMWARE" "левую половину"
        ;;
    left)
        find_firmware
        flash_half "$LEFT_FIRMWARE" "левую половину"
        ;;
    right)
        find_firmware
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        ;;
    reset)
        find_firmware
        if [ -n "$RESET_FIRMWARE" ]; then
            flash_half "$RESET_FIRMWARE" "reset-прошивкой"
        else
            echo "❌ Reset-прошивка не найдена"
            exit 1
        fi
        ;;
    btpairs)
        show_btpairs
        ;;
    btclear)
        clear_btpairs
        ;;
    *)
        show_help
        ;;
esac

echo "$(date) - 🎉 Готово!"
