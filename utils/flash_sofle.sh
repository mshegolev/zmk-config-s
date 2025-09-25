#!/bin/bash
set -e

ZMK_DIR="/opt/develop/zmk"                  # ядро ZMK
CONF_DIR="/opt/develop/zmk-config-s/config" # твой конфиг
BUILD_DIR="$ZMK_DIR/build"                  # папка сборки
MOUNT_DIR="/tmp/nicenano_mount"
BUILD_YAML="/opt/develop/zmk-config-s/build.yaml"

DO_BUILD=1
DO_CLEAN=0
DO_VERBOSE=0
TARGET="all"

# ===== HELP =====
show_help() {
    cat <<EOF
🚀 Sofle Flash Utility

Использование:
  ./flash_sofle.sh [target] [options]

target:
  all       - собрать и прошить обе половины (поочерёдно)
  left      - только левую половину
  right     - только правую половину
  reset     - прошивка reset (очистка BT и настроек)

options:
  --no-build   - пропустить сборку, прошить уже собранное
  --clean      - очистить build/ перед сборкой (полная пересборка)
  --verbose    - подробные логи сборки
  -h, --help   - показать эту справку

Примеры:
  ./flash_sofle.sh all
  ./flash_sofle.sh left --clean --verbose
  ./flash_sofle.sh reset --no-build
EOF
}

# ===== Проверка окружения =====
check_env() {
    echo "$(date) - 🔍 Проверяем окружение..."

    if ! command -v west >/dev/null 2>&1; then
        echo "❌ west не найден!"
        echo "👉 Установи его: pip3 install --user west"
        exit 1
    fi

    if ! command -v arm-none-eabi-gcc >/dev/null 2>&1; then
        echo "❌ arm-none-eabi-gcc не найден!"
        echo "👉 Установи его: brew install arm-none-eabi-gcc"
        exit 1
    fi

    echo "$(date) - ✅ Всё в порядке (west и arm-none-eabi-gcc найдены)"
}

# ===== Вытаскиваем board и shields из build.yaml =====
parse_build_yaml() {
    BOARD=$(grep "board:" "$BUILD_YAML" | head -n1 | cut -d':' -f2 | xargs)
    SHIELDS=$(grep "shield:" "$BUILD_YAML" | cut -d':' -f2 | xargs)

    # Проверка board
    if [ -z "$BOARD" ]; then
        echo "❌ Ошибка: board не найден в $BUILD_YAML"
        echo "👉 Проверь, что в build.yaml есть строка вида:"
        echo "   - board: nice_nano_v2"
        exit 1
    fi

    # Проверка shields
    if [ -z "$SHIELDS" ]; then
        echo "❌ Ошибка: shields не найдены в $BUILD_YAML"
        echo "👉 Проверь, что в build.yaml есть строки вида:"
        echo "   shield: sofle_left"
        echo "   shield: sofle_right"
        exit 1
    fi

    echo "$(date) - Используем board: $BOARD"
    echo "$(date) - Используем shields: $SHIELDS"
}

# Пути к прошивкам
LEFT_FIRMWARE="$BUILD_DIR/left/zephyr/zmk.uf2"
RIGHT_FIRMWARE="$BUILD_DIR/right/zephyr/zmk.uf2"
RESET_FIRMWARE="$BUILD_DIR/reset/zephyr/zmk.uf2"

# ===== СБОРКА =====
build_all() {
    if [ "$DO_BUILD" -eq 0 ]; then
        echo "$(date) - ⏭️ Пропускаем сборку (режим --no-build)"
        return
    fi

    if [ "$DO_CLEAN" -eq 1 ]; then
        echo "$(date) - 🧹 Полностью очищаем build/..."
        rm -rf "$BUILD_DIR"
    fi

    echo "$(date) - 🛠️ Запускаем сборку прошивок..."

    local WEST="west"
    [ "$DO_VERBOSE" -eq 1 ] && WEST="west -v"

    pushd "$ZMK_DIR" >/dev/null

    $WEST build -d "$BUILD_DIR/left" -p -b "$BOARD" app -- -DSHIELD=sofle_left -DZMK_CONFIG=$CONF_DIR
    $WEST build -d "$BUILD_DIR/right" -p -b "$BOARD" app -- -DSHIELD=sofle_right -DZMK_CONFIG=$CONF_DIR
    $WEST build -d "$BUILD_DIR/reset" -p -b "$BOARD" app -- -DSHIELD=settings_reset -DZMK_CONFIG=$CONF_DIR

    popd >/dev/null

    echo "$(date) - ✅ Сборка завершена"
}

# ===== ПРОШИВКА =====
flash_half() {
    local fw_file="$1"
    local half_name="$2"

    if [ ! -f "$fw_file" ]; then
        echo "$(date) - ❌ Файл прошивки не найден: $fw_file"
        exit 1
    fi

    echo "$(date) - Для $half_name: нажми 2 раза reset и ждем подключение..."

    while true; do
        MOUNT_POINT=$(ls /Volumes | grep -iE "NICENANO" | head -n 1)
        if [ -n "$MOUNT_POINT" ]; then
            echo "$(date) - $half_name подключена: /Volumes/$MOUNT_POINT"

            DEVICE=$(df | grep "/Volumes/$MOUNT_POINT" | awk '{print $1}' | sed 's|/dev/||')
            [ -z "$DEVICE" ] && DEVICE="disk4" && echo "$(date) - DEVICE не определен, используем /dev/$DEVICE"

            echo "$(date) - Отмонтируем /Volumes/$MOUNT_POINT..."
            diskutil unmount "/Volumes/$MOUNT_POINT" || echo "$(date) - Уже отмонтирована или ошибка"

            [ ! -d "$MOUNT_DIR" ] && echo "$(date) - Создаем $MOUNT_DIR" && mkdir -p "$MOUNT_DIR"

            echo "$(date) - Монтируем /dev/$DEVICE в $MOUNT_DIR..."
            mount -t msdos -o rw,auto,nobrowse "/dev/$DEVICE" "$MOUNT_DIR" || echo "$(date) - Ошибка монтирования, продолжаем"

            echo "$(date) - Копируем $fw_file на $half_name..."
            cp "$fw_file" "$MOUNT_DIR/" && echo "$(date) - ✅ $half_name успешно прошита" || echo "$(date) - ❌ Ошибка копирования"

            echo "$(date) - Отмонтируем $MOUNT_DIR..."
            diskutil unmount "$MOUNT_DIR" || echo "$(date) - Уже отмонтирована или ошибка"

            break
        fi
        sleep 1
    done

    echo "$(date) - Ждем отключения $half_name..."
    while mount | grep "$MOUNT_DIR" >/dev/null || mount | grep "/Volumes/NICENANO" >/dev/null; do
        sleep 1
    done
    echo "$(date) - $half_name отсоединена"
}

# ===== ПАРСИНГ АРГУМЕНТОВ =====
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --no-build) DO_BUILD=0 ;;
        --clean) DO_CLEAN=1 ;;
        --verbose) DO_VERBOSE=1 ;;
        -h|--help) show_help; exit 0 ;;
        left|right|all|reset) TARGET="$arg" ;;
    esac
done

# ===== ОСНОВНОЙ БЛОК =====
echo "$(date) - 🚀 Автоматическая сборка и прошивка Sofle V2"

check_env
parse_build_yaml
build_all

case "$TARGET" in
    reset)
        flash_half "$RESET_FIRMWARE" "reset-прошивкой"
        ;;
    all)
        flash_half "$LEFT_FIRMWARE" "левую половину"
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        ;;
    left)
        flash_half "$LEFT_FIRMWARE" "левую половину"
        ;;
    right)
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        ;;
esac

echo "$(date) - 🎉 Готово!"
