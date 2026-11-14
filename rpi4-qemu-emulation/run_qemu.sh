#!/usr/bin/env bash
set -Eeuo pipefail

# Печатает краткую подсказку по запуску ядра и initramfs из boot.img в QEMU.
usage() {
  cat <<'USAGE'
Использование:
  bash run_qemu.sh ОТЛАДОЧНЫЙ_BOOT.IMG

QEMU запускает ядро и initramfs напрямую на машине virt, без диска, сети и
USB passthrough. Остановка QEMU: Ctrl+C в терминале.
USAGE
}

# Завершает работу с понятной диагностикой.
fail() {
  printf '\033[31mОШИБКА:\033[0m %s\n' "$1" >&2
  exit 1
}

# Выводит информационное сообщение зелёным цветом.
info() {
  printf '\033[32m%s\033[0m\n' "$1"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

# FAT-образ с отладочной командной строкой; открывается только для чтения.
boot_img=$1
[[ -f "$boot_img" && -r "$boot_img" ]] || fail "образ не найден или не читается: $boot_img"

# Исполняемые программы, нужные для чтения FAT-образа, распаковки и эмуляции.
for required_tool in mcopy mtype gzip qemu-system-aarch64 sha256sum; do
  command -v "$required_tool" >/dev/null 2>&1 || fail "не найдена команда: $required_tool"
done

# Папка со скриптом, вычисленная без привязки к текущему каталогу запуска.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || fail "не удалось определить папку скрипта"
# Постоянная рабочая папка проекта для сохранения извлечённых файлов и журналов.
work_root="$script_dir/work"
mkdir -p -- "$work_root" || fail "не удалось создать рабочую папку проекта"
# Каталог запуска QEMU, который сохраняется в проекте после остановки эмулятора.
work_dir=$(mktemp -d "$work_root/qemu-run-XXXXXX") || fail "не удалось создать рабочий каталог проекта"
# Файлы, извлечённые из boot.img; исходный образ не меняется.
kernel_gz="$work_dir/kernel8.img"
kernel_image="$work_dir/kernel8.Image"
initramfs_copy="$work_dir/initramfs8"
# Командная строка, которую скрипт передаст ядру в QEMU.
cmdline_file="$work_dir/cmdline.txt"
# Журнал QEMU с диагностикой ошибок гостевых устройств.
qemu_log="$work_dir/qemu.log"
# Журнал байтов serial-консоли, одновременно отображаемых в терминале.
serial_log="$work_dir/serial.log"

info "Извлекаю ядро и initramfs из копии: $boot_img"
mcopy -i "$boot_img" ::KERNEL8.IMG "$kernel_gz" || fail "не удалось извлечь kernel8.img"
mcopy -i "$boot_img" ::INITRAMFS8 "$initramfs_copy" || fail "не удалось извлечь initramfs8"
mtype -i "$boot_img" ::cmdline.txt > "$cmdline_file" || fail "не удалось прочитать cmdline.txt"

# Проверяет, что кандидат настроен на serial-консоль и shell initramfs.
grep -q 'console=ttyAMA0' "$cmdline_file" || fail "в cmdline.txt нет console=ttyAMA0"
grep -q 'rdinit=/bin/sh' "$cmdline_file" || fail "в cmdline.txt нет rdinit=/bin/sh"

# Распаковывает gzip-ядро в отдельный файл; исходный FAT-образ остаётся неизменным.
if gzip -t -- "$kernel_gz" >/dev/null 2>&1; then
  gzip -dc -- "$kernel_gz" > "$kernel_image" || fail "не удалось распаковать kernel8.img"
else
  cp -- "$kernel_gz" "$kernel_image" || fail "не удалось подготовить kernel8.Image"
fi

# Убирает переводы строк, чтобы QEMU получил одну строку аргументов ядра.
cmdline=$(tr -d '\r\n' < "$cmdline_file")
info "Ядро:     $(sha256sum -- "$kernel_image" | awk '{print $1}')"
info "Initramfs: $(sha256sum -- "$initramfs_copy" | awk '{print $1}')"
info "Cmdline:  $cmdline"
info "Временные данные и журнал: $work_dir"
info "Serial-журнал: $serial_log"
info "Запускаю generic QEMU virt; готовый prompt shell в этой модели не подтверждает загрузку Raspberry Pi 4."

# Запускает только виртуальный CPU, RAM, serial и initramfs; блочный диск, сеть и USB не подключаются.
set +e
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 2048 \
  -kernel "$kernel_image" \
  -initrd "$initramfs_copy" \
  -append "$cmdline" \
  -display none \
  -chardev "stdio,id=serial0,logfile=$serial_log,logappend=on" \
  -serial chardev:serial0 \
  -monitor none \
  -no-reboot \
  -snapshot \
  -nic none \
  -d guest_errors \
  -D "$qemu_log"
# Сохраняет код завершения QEMU, включая остановку владельцем через Ctrl+C.
qemu_status=$?
set -e

printf 'QEMU завершился с кодом %s; журнал: %s\n' "$qemu_status" "$qemu_log"
exit "$qemu_status"
