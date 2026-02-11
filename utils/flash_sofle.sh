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
    echo "⚠️  Файл с паролем не найден: $PASS_FILE"
    echo ""
    echo -n "🔐 Введи пароль sudo: "
    read -s SUDO_PASS
    echo ""

    # Проверяем пароль
    if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
        echo "❌ Неверный пароль sudo"
        exit 1
    fi

    echo "✅ Пароль принят"
    echo ""
    echo -n "💾 Сохранить пароль в $PASS_FILE? (y/n): "
    read -n 1 SAVE_PASS
    echo ""

    if [ "$SAVE_PASS" = "y" ] || [ "$SAVE_PASS" = "Y" ]; then
        echo "$SUDO_PASS" > "$PASS_FILE"
        chmod 600 "$PASS_FILE"
        echo "✅ Пароль сохранен в $PASS_FILE"
    else
        echo "ℹ️  Пароль не сохранен (будет запрошен при следующем запуске)"
    fi
    echo ""
else
    SUDO_PASS=$(cat "$PASS_FILE")

    # Проверяем sudo пароль
    if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
        echo "❌ Неверный пароль sudo в файле: $PASS_FILE"
        echo ""
        echo -n "🔐 Введи новый пароль sudo: "
        read -s SUDO_PASS
        echo ""

        # Проверяем новый пароль
        if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
            echo "❌ Неверный пароль sudo"
            exit 1
        fi

        echo "✅ Пароль принят"
        echo "$SUDO_PASS" > "$PASS_FILE"
        chmod 600 "$PASS_FILE"
        echo "✅ Пароль обновлен в $PASS_FILE"
        echo ""
    else
        echo "✅ Пароль sudo проверен ($PASS_FILE)"
    fi
fi

# ===== HELP =====
show_help() {
    cat <<EOF
🚀 Sofle Flash Utility (из "$DOWNLOADS")

Использование:
  ./flash_sofle.sh [target] [--force]

target:
  check     - сравнить локальную и доступную версии
  download  - скачать последнюю прошивку (пропускает если уже скачана)
  update    - скачать и прошить обе половины (download + all)
  version   - показать версию скачанной прошивки
  all       - прошить обе половины (правую → левую)
  left      - только левую половину
  right     - только правую половину
  reset     - прошивка reset (очистка BT и настроек)
  btpairs   - показать список Bluetooth-пар (BT1..BT5)
  btclear   - очистить все BT-пары и сразу перепрошить обе половины

options:
  --force   - принудительное скачивание/отключение предупреждений

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
    echo ""

    # Проверяем, не скачана ли уже эта версия
    if [ -f "$VERSION_FILE" ]; then
        source "$VERSION_FILE"
        if [ "$commit" == "$COMMIT_SHA" ] && [ $FORCE_MODE -eq 0 ]; then
            echo "ℹ️  Эта версия уже скачана локально!"
            echo ""
            echo "💾 Локальная версия:"
            echo "   Version: ${tag:-"-"}"
            echo "   Commit:  $commit_short"
            echo "   Build:   $build_date"
            echo ""
            echo "✅ Прошивка актуальна, скачивание не требуется"
            echo ""
            echo "💡 Для принудительной загрузки используй: ./flash_sofle.sh download --force"
            return 0
        fi
    fi

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
download_date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
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
        echo "⏳ Жду диск NICENANO... (таймаут 60 сек)"
        echo "   (нажми Ctrl+C для отмены)"
        echo ""
    fi

    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        MOUNT_POINT=$(ls /Volumes 2>/dev/null | grep -iE "NICENANO" | head -n 1)
        if [ -n "$MOUNT_POINT" ]; then
            echo "$(date) - $half_name подключена: /Volumes/$MOUNT_POINT"

            DEVICE=$(df | grep "/Volumes/$MOUNT_POINT" | awk '{print $1}' | sed 's|/dev/||')
            [ -z "$DEVICE" ] && DEVICE="disk4"

            # Обновляем sudo timestamp
            echo "$SUDO_PASS" | sudo -S -v 2>/dev/null

            # Пробуем unmount с подробным выводом ошибок
            UNMOUNT_OUTPUT=$(echo "$SUDO_PASS" | sudo -S diskutil unmount "/Volumes/$MOUNT_POINT" 2>&1)
            if [ $? -ne 0 ]; then
                echo "❌ Ошибка при unmount: $UNMOUNT_OUTPUT"
                echo "💡 Попробуй вручную: sudo diskutil unmount /Volumes/$MOUNT_POINT"
                exit 1
            fi
            [ ! -d "$MOUNT_DIR" ] && mkdir -p "$MOUNT_DIR"

            # Пробуем mount с подробным выводом ошибок
            MOUNT_OUTPUT=$(echo "$SUDO_PASS" | sudo -S mount -t msdos -o rw,auto,nobrowse "/dev/$DEVICE" "$MOUNT_DIR" 2>&1)
            if [ $? -ne 0 ]; then
                echo "❌ Ошибка при монтировании: $MOUNT_OUTPUT"
                echo "💡 Попробуй вручную: sudo mount -t msdos /dev/$DEVICE $MOUNT_DIR"
                exit 1
            fi

            cp "$fw_file" "$MOUNT_DIR/" && echo "✅ $half_name успешно прошита!"
            echo "   Отключи USB от этой половины."
            echo "$SUDO_PASS" | sudo -S diskutil unmount "$MOUNT_DIR" 2>/dev/null || true

            # Ждем, пока диск действительно отключится
            echo ""
            echo "⏳ Жду отключения диска NICENANO..."
            while true; do
                MOUNT_CHECK=$(ls /Volumes 2>/dev/null | grep -iE "NICENANO" | head -n 1)
                if [ -z "$MOUNT_CHECK" ]; then
                    echo "✅ Диск отключен, можно продолжать"
                    echo ""
                    break
                fi
                sleep 1
            done

            # Показываем метод B на случай проблем
            echo "ℹ️  Если следующая половинка не подключается:"
            echo "   Попробуй МЕТОД B:"
            echo "   1. Отключи USB"
            echo "   2. УДЕРЖИВАЙ кнопку RESET"
            echo "   3. Подключи USB (продолжая держать RESET)"
            echo "   4. Отпусти RESET через 2-3 секунды"
            echo ""
            return 0
        fi

        # Обратный отсчет
        REMAINING=$((TIMEOUT - ELAPSED))
        printf "\r⏳ Осталось: %02d сек..." $REMAINING
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done

    # Таймаут истек
    echo ""
    echo ""
    echo "⏱️  Таймаут истек! Диск NICENANO не обнаружен."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 МЕТОД B: Альтернативный вход в bootloader"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Попробуй этот метод, если двойной reset не работает:"
    echo ""
    echo "   1. Отключи USB от клавиатуры"
    echo "   2. Найди кнопку RESET на контроллере"
    echo "   3. НАЖМИ и УДЕРЖИВАЙ кнопку RESET"
    echo "   4. Подключи USB (продолжая ДЕРЖАТЬ RESET!)"
    echo "   5. Держи RESET ещё 2-3 секунды после подключения"
    echo "   6. Отпусти RESET"
    echo "   7. Должен появиться диск NICENANO"
    echo ""
    echo "Альтернатива: замкни контакты RST и GND скрепкой дважды"
    echo ""
    exit 1
}

# ===== ПОМОЩЬ ПОСЛЕ ПРОШИВКИ =====
show_post_flash_help() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ ОБЕ ПОЛОВИНЫ ПРОШИТЫ!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📋 ШАГИ ДЛЯ ПОДКЛЮЧЕНИЯ:"
    echo ""
    echo "1️⃣  Подключи TRRS кабель между половинами"
    echo "   ⚠️  ВАЖНО: TRRS должен быть надежно вставлен с обеих сторон"
    echo ""
    echo "2️⃣  Подключи USB к ЛЕВОЙ половине"
    echo "   💡 Левая половина = центральная (central)"
    echo "   💡 Правая половина = периферийная (peripheral)"
    echo ""
    echo "3️⃣  Подожди 5-10 секунд для инициализации"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 ЕСЛИ ПРАВАЯ ПОЛОВИНА НЕ ВИДИТ ЛЕВУЮ:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "ВАРИАНТ 1: Проверь TRRS кабель"
    echo "   • Отключи USB"
    echo "   • Отключи TRRS кабель"
    echo "   • Подожди 5 секунд"
    echo "   • Подключи TRRS кабель заново (проверь, что вставлен до конца)"
    echo "   • Подключи USB к левой половине"
    echo ""
    echo "ВАРИАНТ 2: Hard reset обеих половин"
    echo "   • Отключи USB и TRRS"
    echo "   • Нажми кнопку RESET на правой половине"
    echo "   • Нажми кнопку RESET на левой половине"
    echo "   • Подключи TRRS кабель"
    echo "   • Подключи USB к левой половине"
    echo ""
    echo "ВАРИАНТ 3: Очистка BT-пар (если используешь Bluetooth)"
    echo "   • Выполни: ./flash_sofle.sh btclear"
    echo "   • Это очистит все BT-соединения и перепрошьет обе половины"
    echo ""
    echo "ВАРИАНТ 4: Проверь порядок прошивки"
    echo "   • ВАЖНО: сначала правая, потом левая!"
    echo "   • Если прошил в обратном порядке:"
    echo "     ./flash_sofle.sh right"
    echo "     ./flash_sofle.sh left"
    echo ""
    echo "ВАРИАНТ 5: Проверь физическое соединение"
    echo "   • TRRS кабель может быть неисправен - попробуй другой"
    echo "   • TRRS разъемы могут быть загрязнены - протри спиртом"
    echo "   • Проверь, что в TRRS разъёмах нет мусора/пыли"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 ДИАГНОСТИКА:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Проверить BT-пары:"
    echo "   ./flash_sofle.sh btpairs"
    echo ""
    echo "Очистить все BT-пары:"
    echo "   ./flash_sofle.sh btclear"
    echo ""
    echo "Проверить версию прошивки:"
    echo "   ./flash_sofle.sh version"
    echo ""
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
        show_post_flash_help
        ;;
    version)
        show_version
        ;;
    all)
        find_firmware
        flash_half "$RIGHT_FIRMWARE" "правую половину"
        flash_half "$LEFT_FIRMWARE" "левую половину"
        show_post_flash_help
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
