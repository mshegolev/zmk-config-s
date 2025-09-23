#!/bin/bash

# Запрос прав sudo в начале работы
if [ "$EUID" -ne 0 ]; then
	echo "$(date) - Запрашиваем root права..."
	exec sudo "$0" "$@"
fi

LEFT_FIRMWARE="/Users/m.v.shchegolev/Downloads/firmware (2)/sofle_left-nice_nano_v2-zmk.uf2"
RIGHT_FIRMWARE="/Users/m.v.shchegolev/Downloads/firmware (2)/sofle_right-nice_nano_v2-zmk.uf2"
MOUNT_DIR="/tmp/nicenano_mount"

flash_half() {
	local fw_file="$1"
	local half_name="$2"

	echo "$(date) - Для подключения 2 раза нажмите на кнопку reset Ожидаем подключения $half_name..."

	while true; do
		MOUNT_POINT=$(ls /Volumes | grep -iE "NICENANO" | head -n 1)
		if [ -n "$MOUNT_POINT" ]; then
			echo "$(date) - $half_name подключена: /Volumes/$MOUNT_POINT"

			DEVICE=$(df | grep "/Volumes/$MOUNT_POINT" | awk '{print $1}' | sed 's|/dev/||')
			if [[ -z "$DEVICE" ]]; then
				DEVICE="disk4"
				echo "$(date) - DEVICE не определен автоматически, используем /dev/$DEVICE"
			fi

			echo "$(date) - Отмонтируем /Volumes/$MOUNT_POINT..."
			diskutil unmount "/Volumes/$MOUNT_POINT" || echo "$(date) - Уже отмонтирована или ошибка"

			if [ ! -d "$MOUNT_DIR" ]; then
				echo "$(date) - Создаем директорию $MOUNT_DIR"
				mkdir -p "$MOUNT_DIR"
			fi

			echo "$(date) - Монтируем /dev/$DEVICE в $MOUNT_DIR..."
			mount -t msdos -o rw,auto,nobrowse "/dev/$DEVICE" "$MOUNT_DIR" || echo "$(date) - Ошибка монтирования, продолжаем"

			echo "$(date) - Копируем прошивку на $half_name..."
			cp "$fw_file" "$MOUNT_DIR/" && echo "$(date) - Прошивка $half_name успешно записана" || echo "$(date) - Ошибка копирования"

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

echo "$(date) - Начинаем автоматическую прошивку Sofle V2..."

flash_half "$LEFT_FIRMWARE" "левую половину"
flash_half "$RIGHT_FIRMWARE" "правую половину"

echo "$(date) - Прошивка завершена!"
