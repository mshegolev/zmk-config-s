#!/usr/bin/env python3
"""
Sofle V2 Flash Utility
Автоматическая прошивка split клавиатуры Sofle
"""

import subprocess
import sys
import os
import time
import json
import getpass
from pathlib import Path
from datetime import datetime

# ===== Константы =====
HOME = Path.home()
MOUNT_DIR = HOME / "nicenano_mount"
DOWNLOADS = HOME / "Downloads" / "zmk-firmware"
PASS_FILE = HOME / "pss_file"
VERSION_FILE = DOWNLOADS / ".version.json"
REPO = "mshegolev/zmk-config-s"

# Цвета для терминала
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[0;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

# ===== Утилиты =====
def print_color(text, color=Colors.NC):
    """Печать текста с цветом"""
    print(f"{color}{text}{Colors.NC}")

def run_command(cmd, capture=True, check=True, input_data=None):
    """Выполнение команды с обработкой ошибок"""
    try:
        if capture:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                input=input_data
            )
            if check and result.returncode != 0:
                return None, result.stderr
            return result.stdout.strip(), result.stderr
        else:
            result = subprocess.run(cmd, shell=True, check=check)
            return result.returncode == 0, None
    except subprocess.CalledProcessError as e:
        return None, str(e)
    except Exception as e:
        return None, str(e)

def timestamp():
    """Текущая временная метка"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# ===== Управление паролем sudo =====
class SudoManager:
    def __init__(self):
        self.password = None

    def load_password(self):
        """Загрузка пароля из файла или запрос у пользователя"""
        if PASS_FILE.exists():
            self.password = PASS_FILE.read_text().strip()
            # Проверяем пароль
            if self._verify_password():
                print_color(f"✅ Пароль sudo проверен ({PASS_FILE})", Colors.GREEN)
                return True
            else:
                print_color(f"❌ Неверный пароль sudo в файле: {PASS_FILE}", Colors.RED)
                return self._prompt_password(update=True)
        else:
            print_color(f"⚠️  Файл с паролем не найден: {PASS_FILE}", Colors.YELLOW)
            return self._prompt_password(update=False)

    def _prompt_password(self, update=False):
        """Запрос пароля у пользователя"""
        prompt = "🔐 Введи новый пароль sudo: " if update else "🔐 Введи пароль sudo: "
        self.password = getpass.getpass(prompt)

        if not self._verify_password():
            print_color("❌ Неверный пароль sudo", Colors.RED)
            return False

        print_color("✅ Пароль принят", Colors.GREEN)

        if update:
            PASS_FILE.write_text(self.password)
            PASS_FILE.chmod(0o600)
            print_color(f"✅ Пароль обновлен в {PASS_FILE}", Colors.GREEN)
        else:
            save = input("💾 Сохранить пароль в файл? (y/n): ").strip().lower()
            if save in ['y', 'yes']:
                PASS_FILE.write_text(self.password)
                PASS_FILE.chmod(0o600)
                print_color(f"✅ Пароль сохранен в {PASS_FILE}", Colors.GREEN)
            else:
                print_color("ℹ️  Пароль не сохранен (будет запрошен при следующем запуске)", Colors.BLUE)

        return True

    def _verify_password(self):
        """Проверка пароля sudo"""
        result, _ = run_command(f"echo '{self.password}' | sudo -S -v", check=False)
        return result is not None

    def run_sudo(self, cmd):
        """Выполнение команды с sudo"""
        full_cmd = f"echo '{self.password}' | sudo -S {cmd}"
        return run_command(full_cmd, capture=True, check=False)

# ===== GitHub интеграция =====
class GitHubFirmware:
    @staticmethod
    def check_gh_cli():
        """Проверка наличия GitHub CLI"""
        result, _ = run_command("command -v gh", check=False)
        if not result:
            print_color("❌ GitHub CLI (gh) не установлен", Colors.RED)
            print_color("   Установка: brew install gh", Colors.BLUE)
            sys.exit(1)

        result, _ = run_command("gh auth status", check=False)
        if not result:
            print_color("❌ Не авторизован в GitHub CLI", Colors.RED)
            print_color("   Выполни: gh auth login", Colors.BLUE)
            sys.exit(1)

    @staticmethod
    def fetch_remote_version():
        """Получение информации о последней прошивке"""
        cmd = f'gh run list --repo {REPO} --workflow build.yml --status success --limit 1 --json databaseId,headSha,createdAt,headBranch,displayTitle'
        output, error = run_command(cmd)

        if not output:
            print_color("❌ Не найден успешный workflow run", Colors.RED)
            sys.exit(1)

        run_info = json.loads(output)[0]
        commit_sha = run_info['headSha']

        # Получаем тег для коммита
        tag_cmd = f'gh api repos/{REPO}/tags --jq ".[] | select(.commit.sha == \\"{commit_sha}\\") | .name"'
        tag, _ = run_command(tag_cmd, check=False)

        return {
            'run_id': run_info['databaseId'],
            'commit': commit_sha,
            'commit_short': commit_sha[:7],
            'branch': run_info['headBranch'],
            'build_date': run_info['createdAt'],
            'commit_message': run_info['displayTitle'],
            'tag': tag if tag else '-'
        }

    @staticmethod
    def download_firmware(force=False):
        """Скачивание прошивки из GitHub Actions"""
        print(f"{timestamp()} - 📥 Скачивание последней прошивки из GitHub Actions...")

        GitHubFirmware.check_gh_cli()
        remote = GitHubFirmware.fetch_remote_version()

        print_color("✅ Найден run: " + str(remote['run_id']), Colors.GREEN)
        print(f"   Version: {remote['tag']}")
        print(f"   Commit:  {remote['commit_short']} ({remote['commit_message']})")
        print(f"   Branch:  {remote['branch']}")
        print(f"   Date:    {remote['build_date']}")
        print()

        # Проверяем, не скачана ли уже эта версия
        if VERSION_FILE.exists() and not force:
            local = json.loads(VERSION_FILE.read_text())
            if local.get('commit') == remote['commit']:
                print_color("ℹ️  Эта версия уже скачана локально!", Colors.BLUE)
                print()
                print("💾 Локальная версия:")
                print(f"   Version: {local.get('tag', '-')}")
                print(f"   Commit:  {local['commit_short']}")
                print(f"   Build:   {local['build_date']}")
                print()
                print_color("✅ Прошивка актуальна, скачивание не требуется", Colors.GREEN)
                print()
                print("💡 Для принудительной загрузки используй: ./flash_sofle.py download --force")
                return

        # Очищаем и создаем директорию
        if DOWNLOADS.exists():
            run_command(f"rm -rf {DOWNLOADS}", check=False)
        DOWNLOADS.mkdir(parents=True, exist_ok=True)

        # Скачиваем артефакты
        print("📦 Скачиваем артефакты...")
        run_command(f'gh run download {remote["run_id"]} --repo {REPO} --dir {DOWNLOADS}')

        # Перемещаем .uf2 файлы
        for uf2 in DOWNLOADS.rglob("*.uf2"):
            if uf2.parent != DOWNLOADS:
                uf2.rename(DOWNLOADS / uf2.name)

        # Удаляем пустые директории
        for d in DOWNLOADS.iterdir():
            if d.is_dir() and not list(d.iterdir()):
                d.rmdir()

        # Сохраняем информацию о версии
        remote['download_date'] = datetime.now().isoformat()
        VERSION_FILE.write_text(json.dumps(remote, indent=2))

        print_color(f"✅ Прошивки скачаны в {DOWNLOADS}:", Colors.GREEN)
        for uf2 in sorted(DOWNLOADS.glob("*.uf2")):
            print(f"   {uf2.name}")
        print()

        GitHubFirmware.show_version()

    @staticmethod
    def show_version():
        """Показать текущую версию прошивки"""
        if not VERSION_FILE.exists():
            print_color("❌ Версия не найдена. Сначала выполни: ./flash_sofle.py download", Colors.RED)
            return False

        info = json.loads(VERSION_FILE.read_text())
        print("📋 Версия прошивки:")
        print(f"   Version: {info.get('tag', '-')}")
        print(f"   Commit:  {info['commit_short']} ({info['commit_message']})")
        print(f"   Branch:  {info['branch']}")
        print(f"   Build:   {info['build_date']}")
        print(f"   Run ID:  {info['run_id']}")
        return True

# ===== Прошивка =====
class Flasher:
    def __init__(self, sudo_mgr, force_mode=False):
        self.sudo = sudo_mgr
        self.force_mode = force_mode
        MOUNT_DIR.mkdir(parents=True, exist_ok=True)

    def find_firmware(self):
        """Поиск файлов прошивки"""
        files = {
            'left': list(DOWNLOADS.glob("sofle_left-*.uf2")),
            'right': list(DOWNLOADS.glob("sofle_right-*.uf2")),
            'reset': list(DOWNLOADS.glob("settings_reset-*.uf2"))
        }

        if not files['left'] or not files['right']:
            print_color(f"❌ Не найдены прошивки в {DOWNLOADS}", Colors.RED)
            sys.exit(1)

        firmware = {
            'left': str(files['left'][0]),
            'right': str(files['right'][0]),
            'reset': str(files['reset'][0]) if files['reset'] else None
        }

        # Показываем версию
        if VERSION_FILE.exists():
            GitHubFirmware.show_version()
            print()

        print_color("✅ Найдены прошивки:", Colors.GREEN)
        print(f"   Левая  = {firmware['left']}")
        print(f"   Правая = {firmware['right']}")
        if firmware['reset']:
            print(f"   Reset  = {firmware['reset']}")

        return firmware

    def flash_half(self, fw_file, half_name):
        """Прошивка одной половинки"""
        if not Path(fw_file).exists():
            print_color(f"❌ Файл прошивки не найден: {fw_file}", Colors.RED)
            sys.exit(1)

        if not self.force_mode:
            print()
            print("━" * 60)
            print_color(f"⚠️  ПРОШИВКА: {half_name}", Colors.YELLOW)
            print("━" * 60)
            print()
            print("📋 Что нужно сделать:")
            print("   1. Отключи TRRS кабель между половинками!")
            print("   2. Отключи USB от обеих половин")
            print("   3. Проверь переключатель питания:")
            print("      • Правая половинка: ON = вниз ⬇️")
            print("      • Левая половинка:  ON = вверх ⬆️")
            print(f"   4. Подключи USB только к: {half_name}")
            print("   5. Нажми 2 раза кнопку RESET на контроллере")
            print("      (появится диск NICENANO)")
            print()
            print("⏳ Жду диск NICENANO... (таймаут 60 сек)")
            print("   (нажми Ctrl+C для отмены)")
            print()

        # Ожидание подключения диска
        timeout = 60
        elapsed = 0

        while elapsed < timeout:
            # Проверяем наличие диска
            volumes = Path("/Volumes")
            if volumes.exists():
                for v in volumes.iterdir():
                    if "NICENANO" in v.name.upper():
                        mount_point = v
                        print(f"{timestamp()} - {half_name} подключена: {mount_point}")

                        # msdosfs.kext не грузится (Bad code signature), `mount -t msdos` не работает.
                        # Пишем прямо в том, который macOS примонтировала сама (без unmount/mount).
                        ok, cp_err = run_command(f"cp '{fw_file}' '{mount_point}/'", capture=False, check=False)
                        if ok:
                            print_color(f"✅ {half_name} успешно прошита!", Colors.GREEN)
                        elif not mount_point.exists():
                            # Bootloader перезагружается сразу после записи и мог отключить диск до конца cp
                            print_color(f"✅ {half_name} прошита (диск отключился сам — это нормально)", Colors.GREEN)
                        else:
                            print_color(f"❌ Не удалось скопировать прошивку в {mount_point}", Colors.RED)
                            sys.exit(1)
                        print(f"   Отключи USB от этой половины.")

                        # Синхронизируем и ждем завершения записи
                        print("⏳ Синхронизация данных...")
                        run_command("sync")
                        time.sleep(2)

                        print()
                        print_color("ℹ️  ВАЖНО: Контроллер перезагрузится автоматически", Colors.YELLOW)
                        print("   macOS может показать ошибку 'диск извлечен неправильно'")
                        print("   ✅ Это НОРМАЛЬНО - так работает bootloader!")
                        print("   ✅ Прошивка записана успешно, ошибку можно игнорировать")
                        print()

                        # Корректно извлекаем диск (eject)
                        run_command(f"diskutil eject '{mount_point}'", check=False)

                        # Ждем отключения диска
                        print()
                        print("⏳ Жду отключения диска NICENANO...")
                        while True:
                            found = False
                            if volumes.exists():
                                for v in volumes.iterdir():
                                    if "NICENANO" in v.name.upper():
                                        found = True
                                        break
                            if not found:
                                print_color("✅ Диск отключен, можно продолжать", Colors.GREEN)
                                print()
                                break
                            time.sleep(1)

                        # Показываем подсказку
                        print("ℹ️  Если следующая половинка не подключается:")
                        print("   Попробуй МЕТОД B:")
                        print("   1. Отключи USB")
                        print("   2. УДЕРЖИВАЙ кнопку RESET")
                        print("   3. Подключи USB (продолжая держать RESET)")
                        print("   4. Отпусти RESET через 2-3 секунды")
                        print()
                        return

            # Обратный отсчет
            remaining = timeout - elapsed
            print(f"\r⏳ Осталось: {remaining:02d} сек...", end='', flush=True)
            time.sleep(1)
            elapsed += 1

        # Таймаут истек
        print()
        print()
        print_color("⏱️  Таймаут истек! Диск NICENANO не обнаружен.", Colors.RED)
        print()
        print("━" * 60)
        print_color("💡 МЕТОД B: Альтернативный вход в bootloader", Colors.YELLOW)
        print("━" * 60)
        print()
        print("Попробуй этот метод, если двойной reset не работает:")
        print()
        print("   1. Отключи USB от клавиатуры")
        print("   2. Найди кнопку RESET на контроллере")
        print("   3. НАЖМИ и УДЕРЖИВАЙ кнопку RESET")
        print("   4. Подключи USB (продолжая ДЕРЖАТЬ RESET!)")
        print("   5. Держи RESET ещё 2-3 секунды после подключения")
        print("   6. Отпусти RESET")
        print("   7. Должен появиться диск NICENANO")
        print()
        print("Альтернатива: замкни контакты RST и GND скрепкой дважды")
        print()
        sys.exit(1)

    def clear_btpairs(self, firmware):
        """Очистка BT-пар и перепрошивка"""
        if not firmware['reset']:
            print_color(f"❌ Reset-прошивка не найдена в {DOWNLOADS}", Colors.RED)
            sys.exit(1)

        print(f"{timestamp()} - ⚠️ Сначала будет прошивка reset на ОБЕ половинки, все BT-пары удалятся!")
        print()

        print("━" * 60)
        print("📋 ШАГ 1/4: Reset правой половины")
        print("━" * 60)
        self.flash_half(firmware['reset'], "правую половину (reset)")

        print()
        print("━" * 60)
        print("📋 ШАГ 2/4: Reset левой половины")
        print("━" * 60)
        self.flash_half(firmware['reset'], "левую половину (reset)")

        print()
        print_color("✅ BT-пары очищены на обеих половинках", Colors.GREEN)
        print()
        print(f"{timestamp()} - 🔄 Прошиваем основную прошивку (правую → левую)...")
        print()

        print("━" * 60)
        print("📋 ШАГ 3/4: Основная прошивка правой половины")
        print("━" * 60)
        self.flash_half(firmware['right'], "правую половину")

        print()
        print("━" * 60)
        print("📋 ШАГ 4/4: Основная прошивка левой половины")
        print("━" * 60)
        self.flash_half(firmware['left'], "левую половину")

        print()
        print_color("✅ Обе половины перепрошиты (reset + основная прошивка)", Colors.GREEN)

        self.show_post_flash_help()

    def flash_all(self, firmware):
        """Прошивка обеих половин"""
        print("━" * 60)
        print("📋 Прошивка правой половины")
        print("━" * 60)
        self.flash_half(firmware['right'], "правую половину")

        print()
        print("━" * 60)
        print("📋 Прошивка левой половины")
        print("━" * 60)
        self.flash_half(firmware['left'], "левую половину")

        self.show_post_flash_help()

    def show_post_flash_help(self):
        """Инструкции после прошивки"""
        print()
        print("━" * 60)
        print_color("✅ ОБЕ ПОЛОВИНЫ ПРОШИТЫ!", Colors.GREEN)
        print("━" * 60)
        print()
        print("📋 ШАГИ ДЛЯ ПОДКЛЮЧЕНИЯ:")
        print()
        print("1️⃣  Проверь переключатели питания:")
        print("   • Правая половинка: ON = вниз ⬇️")
        print("   • Левая половинка:  ON = вверх ⬆️")
        print()
        print("2️⃣  Подключи TRRS кабель между половинами")
        print("   ⚠️  ВАЖНО: TRRS должен быть надежно вставлен с обеих сторон")
        print()
        print("3️⃣  Подключи USB к ЛЕВОЙ половине")
        print("   💡 Левая половина = центральная (central)")
        print("   💡 Правая половина = периферийная (peripheral)")
        print()
        print("4️⃣  Подожди 5-10 секунд для инициализации")
        print()
        print("━" * 60)
        print_color("🔧 ЕСЛИ ПРАВАЯ ПОЛОВИНА НЕ ВИДИТ ЛЕВУЮ:", Colors.YELLOW)
        print("━" * 60)
        print()
        print("ВАРИАНТ 1: Проверь TRRS кабель")
        print("   • Отключи USB")
        print("   • Отключи TRRS кабель")
        print("   • Подожди 5 секунд")
        print("   • Подключи TRRS кабель заново (проверь, что вставлен до конца)")
        print("   • Подключи USB к левой половине")
        print()
        print("ВАРИАНТ 2: Hard reset обеих половин")
        print("   • Отключи USB и TRRS")
        print("   • Нажми кнопку RESET на правой половине")
        print("   • Нажми кнопку RESET на левой половине")
        print("   • Подключи TRRS кабель")
        print("   • Подключи USB к левой половине")
        print()
        print("ВАРИАНТ 3: Очистка BT-пар (если используешь Bluetooth)")
        print("   • Выполни: ./flash_sofle.py btclear")
        print("   • Это очистит все BT-соединения и перепрошьет обе половины")
        print()
        print("ВАРИАНТ 4: Проверь порядок прошивки")
        print("   • ВАЖНО: сначала правая, потом левая!")
        print("   • Если прошил в обратном порядке:")
        print("     ./flash_sofle.py right")
        print("     ./flash_sofle.py left")
        print()
        print("ВАРИАНТ 5: Проверь физическое соединение")
        print("   • TRRS кабель может быть неисправен - попробуй другой")
        print("   • TRRS разъемы могут быть загрязнены - протри спиртом")
        print("   • Проверь, что в TRRS разъёмах нет мусора/пыли")
        print()
        print("━" * 60)
        print_color("💡 ДИАГНОСТИКА:", Colors.BLUE)
        print("━" * 60)
        print()
        print("Проверить версию прошивки:")
        print("   ./flash_sofle.py version")
        print()
        print("━" * 60)
        print_color("🔓 LOCK/UNLOCK КЛАВИАТУРЫ:", Colors.BLUE)
        print("━" * 60)
        print()
        print("Блокировка:   ЛЕВЫЙ Shift + Lower + Raise")
        print("Разблокировка: ПРАВЫЙ Shift + Lower + Raise")
        print()
        print("(Lower = левая нижняя кнопка большого пальца)")
        print("(Raise = правая нижняя кнопка большого пальца)")
        print()

# ===== Просмотр раскладки =====
class KeymapViewer:
    KEYMAP_FILE = Path(__file__).parent.parent / "config" / "sofle.keymap"

    @staticmethod
    def show_layout():
        """Показать раскладку клавиатуры"""
        if not KeymapViewer.KEYMAP_FILE.exists():
            print_color(f"❌ Файл конфигурации не найден: {KeymapViewer.KEYMAP_FILE}", Colors.RED)
            return

        content = KeymapViewer.KEYMAP_FILE.read_text()

        print_color("⌨️  РАСКЛАДКА КЛАВИАТУРЫ SOFLE", Colors.BLUE)
        print()

        # Показываем behaviors
        KeymapViewer._show_behaviors(content)

        # Показываем combos
        KeymapViewer._show_combos(content)

        # Показываем слои
        KeymapViewer._show_layers(content)

    @staticmethod
    def _show_behaviors(content):
        """Показать behaviors (hold-tap, tap-dance)"""
        print("━" * 80)
        print_color("🎛️  BEHAVIORS (Специальные поведения клавиш)", Colors.GREEN)
        print("━" * 80)
        print()

        behaviors = []

        # Hold-tap behaviors
        if "bspc_del:" in content:
            behaviors.append("• BSPC: tap=Backspace, hold=Delete")
        if "esc_tilde:" in content:
            behaviors.append("• ESC: tap=Escape, hold=Tilde (~)")

        # Tap-dance behaviors
        if "semi_colon:" in content:
            behaviors.append("• ; (semicolon): tap=;, double-tap=:")
        if "sqt_dqt:" in content:
            behaviors.append("• ' (quote): tap=', double-tap=\"")

        # Mod-morph behaviors
        if "lshift_grave:" in content:
            behaviors.append("• LSHIFT: обычно=Shift, с RSHIFT=` (grave)")
        if "rshift_tilde:" in content:
            behaviors.append("• RSHIFT: обычно=Shift, с LSHIFT=~ (tilde)")

        for behavior in behaviors:
            print(behavior)
        print()

    @staticmethod
    def _show_combos(content):
        """Показать combos (комбинации клавиш)"""
        print("━" * 80)
        print_color("🔀 COMBOS (Комбинации клавиш)", Colors.GREEN)
        print("━" * 80)
        print()

        combos = []

        if "combo_esc" in content:
            combos.append("• J + K → Escape (с задержкой 150мс)")
        if "combo_lock" in content:
            combos.append("• LSHIFT + Lower + Raise → Заблокировать клавиатуру 🔒")
        if "combo_unlock" in content:
            combos.append("• RSHIFT + Lower + Raise → Разблокировать клавиатуру 🔓")
        if "combo_delete_word" in content:
            combos.append("• ALT + BSPC → Удалить слово (Option+Backspace)")

        for combo in combos:
            print(combo)
        print()

    @staticmethod
    def _show_layers(content):
        """Показать слои клавиатуры"""
        print("━" * 80)
        print_color("📑 СЛОИ КЛАВИАТУРЫ", Colors.GREEN)
        print("━" * 80)
        print()

        layers = [
            {
                'name': 'default_layer',
                'title': '🔵 СЛОЙ 0: DEFAULT (Основной)',
                'description': 'Обычная раскладка QWERTY с модификаторами'
            },
            {
                'name': 'lower_layer',
                'title': '🟡 СЛОЙ 1: LOWER (Символы и навигация)',
                'description': 'F-клавиши, цифры, символы, стрелки'
            },
            {
                'name': 'raise_layer',
                'title': '🟢 СЛОЙ 2: RAISE (Bluetooth и мышь)',
                'description': 'Bluetooth профили, мышь, медиа-клавиши'
            },
            {
                'name': 'lock_layer',
                'title': '🔴 СЛОЙ 3: LOCK (Блокировка)',
                'description': 'Все клавиши заблокированы (только unlock комбо работает)'
            }
        ]

        for layer in layers:
            print_color(layer['title'], Colors.YELLOW)
            print(f"   {layer['description']}")

            # Пытаемся найти комментарии о слое
            layer_start = content.find(f"{layer['name']} {{")
            if layer_start != -1:
                # Ищем комментарии перед слоем
                lines_before = content[:layer_start].split('\n')[-20:]
                for line in lines_before:
                    if '//' in line and any(x in line.lower() for x in ['индексы', 'hold-tap', 'tap-dance', 'combo']):
                        comment = line.split('//')[-1].strip()
                        if comment and len(comment) > 10:
                            print(f"   ℹ️  {comment}")
            print()

        # Показываем как переключаться между слоями
        print("━" * 80)
        print_color("🔄 ПЕРЕКЛЮЧЕНИЕ СЛОЕВ", Colors.BLUE)
        print("━" * 80)
        print()
        print("• Lower (слой 1): удерживай левую нижнюю кнопку большого пальца")
        print("• Raise (слой 2): удерживай правую нижнюю кнопку большого пальца")
        print("• Lock (слой 3): LSHIFT + Lower + Raise (блокировка)")
        print("• Unlock: RSHIFT + Lower + Raise (разблокировка)")
        print()

# ===== CLI =====
def show_help():
    """Показать справку"""
    print("🚀 Sofle Flash Utility (Python)")
    print()
    print("Использование:")
    print("  ./flash_sofle.py [command] [--force]")
    print()
    print("Команды:")
    print("  download  - скачать последнюю прошивку (пропускает если уже скачана)")
    print("  version   - показать версию скачанной прошивки")
    print("  layout    - показать раскладку клавиатуры (все слои)")
    print("  all       - прошить обе половины (правую → левую)")
    print("  left      - только левую половину")
    print("  right     - только правую половину")
    print("  btclear   - очистить BT-пары и перепрошить обе половины")
    print()
    print("Опции:")
    print("  --force   - принудительное скачивание/отключение предупреждений")
    print()

def main():
    """Главная функция"""
    if len(sys.argv) < 2:
        show_help()
        sys.exit(0)

    command = sys.argv[1]
    force_mode = '--force' in sys.argv

    # Команды без sudo
    if command == "version":
        GitHubFirmware.show_version()
        return

    if command == "layout":
        KeymapViewer.show_layout()
        return

    if command == "download":
        sudo_mgr = SudoManager()
        if not sudo_mgr.load_password():
            sys.exit(1)
        GitHubFirmware.download_firmware(force=force_mode)
        return

    # Команды с прошивкой
    sudo_mgr = SudoManager()
    if not sudo_mgr.load_password():
        sys.exit(1)

    print(f"{timestamp()} - 🚀 Автоматическая прошивка Sofle V2")

    flasher = Flasher(sudo_mgr, force_mode)
    firmware = flasher.find_firmware()

    if command == "all":
        flasher.flash_all(firmware)
    elif command == "left":
        flasher.flash_half(firmware['left'], "левую половину")
    elif command == "right":
        flasher.flash_half(firmware['right'], "правую половину")
    elif command == "btclear":
        flasher.clear_btpairs(firmware)
    else:
        show_help()
        sys.exit(1)

    print(f"{timestamp()} - 🎉 Готово!")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
        print_color("\n⚠️  Прервано пользователем", Colors.YELLOW)
        sys.exit(1)
    except Exception as e:
        print_color(f"\n❌ Ошибка: {e}", Colors.RED)
        import traceback
        traceback.print_exc()
        sys.exit(1)
