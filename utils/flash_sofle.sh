#!/bin/bash
set -e

MOUNT_DIR="$HOME/nicenano_mount"
DOWNLOADS="$HOME/Downloads/zmk-firmware"
PASS_FILE="$HOME/pss_file"
REPO="mshegolev/zmk-config-s"
VERSION_FILE="$DOWNLOADS/.version"

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
  check     - сравнить локальную и доступную версии
  download  - скачать последнюю прошивку из GitHub Actions
  update    - скачать и прошить обе половины (download + all)
  version   - показать версию скачанной прошивки
  all       - прошить обе половины (правую → левую)
  left      - только левую половину
  right     - только правую половину
  reset     - прошивка reset (очистка BT и настроек)
  btpairs   - показать список Bluetooth-пар (BT1..BT5)
  btclear   - очистить все BT-пары и сразу перепрошить обе половины

options:
  --force   - отключить предупреждения (для автоматизации)

Требуется: gh (GitHub CLI) для команды download
EOF
}

# ===== ПРОВЕРКА GH CLI =====
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) не установлен"
        echo "   Установка: brew install gh"
        exit 1
    fi

    if ! gh auth status &> /dev/null; then
        echo "❌ Не авторизован в GitHub CLI"
        echo "   Выполни: gh auth login"
        exit 1
    fi
}

# ===== ПОЛУЧИТЬ ИНФО О ПОСЛЕДНЕМ БИЛДЕ =====
fetch_remote_version() {
    RUN_INFO=$(gh run list --repo "$REPO" --workflow build.yml --status success --limit 1 --json databaseId,headSha,createdAt,headBranch,displayTitle)
    REMOTE_RUN_ID=$(echo "$RUN_INFO" | jq -r '.[0].databaseId')
    REMOTE_COMMIT=$(echo "$RUN_INFO" | jq -r '.[0].headSha')
    REMOTE_COMMIT_SHORT="${REMOTE_COMMIT:0:7}"
    REMOTE_BUILD_DATE=$(echo "$RUN_INFO" | jq -r '.[0].createdAt')
    REMOTE_BRANCH=$(echo "$RUN_INFO" | jq -r '.[0].headBranch')
    REMOTE_COMMIT_MSG=$(echo "$RUN_INFO" | jq -r '.[0].displayTitle')

    if [ -z "$REMOTE_RUN_ID" ] || [ "$REMOTE_RUN_ID" == "null" ]; then
        echo "❌ Не найден успешный workflow run"
        exit 1
    fi

    # Получаем тег для коммита (если есть)
    REMOTE_TAG=$(gh api "repos/$REPO/tags" --jq ".[] | select(.commit.sha == \"$REMOTE_COMMIT\") | .name" 2>/dev/null | head -1)
    if [ -z "$REMOTE_TAG" ]; then
        REMOTE_TAG="-"
    fi
}

# ===== ПРОВЕРИТЬ ВЕРСИИ =====
check_versions() {
    check_gh_cli
    echo "🔍 Проверяю версии..."
    echo ""

    fetch_remote_version

    echo "☁️  Доступна для скачивания:"
    echo "   Version: $REMOTE_TAG"
    echo "   Commit:  $REMOTE_COMMIT_SHORT ($REMOTE_COMMIT_MSG)"
    echo "   Branch:  $REMOTE_BRANCH"
    echo "   Build:   $REMOTE_BUILD_DATE"
    echo ""

    if [ -f "$VERSION_FILE" ]; then
        source "$VERSION_FILE"
        echo "💾 Скачана локально:"
        echo "   Version: ${tag:-"-"}"
        echo "   Commit:  $commit_short ($commit_message)"
        echo "   Branch:  $branch"
        echo "   Build:   $build_date"
        echo ""

        if [ "$commit" == "$REMOTE_COMMIT" ]; then
            echo "✅ Локальная версия актуальна"
        else
            echo "⚠️  Доступна новая версия! Выполни: ./flash_sofle.sh download"
        fi
    else
        echo "💾 Локально: не скачано"
        echo ""
        echo "➡️  Выполни: ./flash_sofle.sh download"
    fi
}

# ===== СКАЧИВАНИЕ ПРОШИВКИ =====
download_firmware() {
    echo "$(date) - 📥 Скачивание последней прошивки из GitHub Actions..."

    check_gh_cli
    fetch_remote_version

    # Используем переменные из fetch_remote_version
    RUN_ID="$REMOTE_RUN_ID"
    COMMIT_SHA="$REMOTE_COMMIT"
    COMMIT_SHORT="$REMOTE_COMMIT_SHORT"
    BUILD_DATE="$REMOTE_BUILD_DATE"
    BRANCH="$REMOTE_BRANCH"
    COMMIT_MSG="$REMOTE_COMMIT_MSG"
    TAG="$REMOTE_TAG"

    if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
        echo "❌ Не найден успешный workflow run"
        exit 1
    fi

    echo "✅ Найден run: $RUN_ID"
    echo "   Version: $TAG"
    echo "   Commit:  $COMMIT_SHORT ($COMMIT_MSG)"
    echo "   Branch:  $BRANCH"
    echo "   Date:    $BUILD_DATE"

    # Очищаем старые прошивки
    rm -rf "$DOWNLOADS"
    mkdir -p "$DOWNLOADS"

    # Скачиваем все артефакты
    echo "📦 Скачиваем артефакты..."
    gh run download "$RUN_ID" --repo "$REPO" --dir "$DOWNLOADS"

    # Перемещаем .uf2 файлы из поддиректорий в корень
    find "$DOWNLOADS" -name "*.uf2" -exec mv {} "$DOWNLOADS/" \;
    # Удаляем пустые поддиректории
    find "$DOWNLOADS" -type d -empty -delete

    # Сохраняем информацию о версии (кавычки для значений с пробелами)
    cat > "$VERSION_FILE" <<EOF
run_id="$RUN_ID"
commit="$COMMIT_SHA"
commit_short="$COMMIT_SHORT"
branch="$BRANCH"
build_date="$BUILD_DATE"
commit_message="$COMMIT_MSG"
tag="$TAG"
download_date="$(date -Iseconds)"
EOF

    echo "✅ Прошивки скачаны в $DOWNLOADS:"
    ls -la "$DOWNLOADS"/*.uf2 2>/dev/null || echo "⚠️ UF2 файлы не найдены"
    echo ""
    show_version
}

# ===== ПОКАЗАТЬ ВЕРСИЮ =====
show_version() {
    if [ ! -f "$VERSION_FILE" ]; then
        echo "❌ Версия не найдена. Сначала выполни: ./flash_sofle.sh download"
        return 1
    fi

    source "$VERSION_FILE"
    echo "📋 Версия прошивки:"
    echo "   Version: ${tag:-"-"}"
    echo "   Commit:  $commit_short ($commit_message)"
    echo "   Branch:  $branch"
    echo "   Build:   $build_date"
    echo "   Run ID:  $run_id"
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

    # Показываем версию если доступна
    [ -f "$VERSION_FILE" ] && show_version && echo ""

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
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  ПРОШИВКА: $half_name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📋 Что нужно сделать:"
        echo "   1. Отключи TRRS кабель между половинками!"
        echo "   2. Отключи USB от обеих половин"
        echo "   3. Подключи USB только к: $half_name"
        echo "   4. Нажми 2 раза кнопку RESET на контроллере"
        echo "      (появится диск NICENANO)"
        echo ""
        echo "⏳ Жду диск NICENANO..."
        echo "   (нажми Ctrl+C для отмены)"
        echo ""
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

            cp "$fw_file" "$MOUNT_DIR/" && echo "✅ $half_name успешно прошита!"
            echo "   Отключи USB от этой половины."
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
    check)
        check_versions
        ;;
    download)
        download_firmware
        ;;
    update)
        download_firmware
        find_firmware
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        flash_half "$LEFT_FIRMWARE" "левую половину"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ ОБЕ ПОЛОВИНЫ ПРОШИТЫ!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📋 Финальные шаги:"
        echo "   1. Подключи TRRS кабель между половинами"
        echo "   2. Подключи USB к любой половине"
        echo "   3. Готово! Клавиатура должна работать"
        echo ""
        ;;
    version)
        show_version
        ;;
    all)
        find_firmware
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        flash_half "$LEFT_FIRMWARE" "левую половину"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✅ ОБЕ ПОЛОВИНЫ ПРОШИТЫ!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📋 Финальные шаги:"
        echo "   1. Подключи TRRS кабель между половинами"
        echo "   2. Подключи USB к любой половине"
        echo "   3. Готово! Клавиатура должна работать"
        echo ""
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
