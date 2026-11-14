#!/usr/bin/env bash
set -Eeuo pipefail

# Печатает краткую подсказку по созданию отдельной отладочной копии boot.img.
usage() {
  cat <<'USAGE'
Использование:
  bash make_debug_copy.sh ИСХОДНЫЙ_BOOT.IMG НОВЫЙ_ОТЛАДОЧНЫЙ_BOOT.IMG

Создаёт новую копию и меняет только cmdline.txt внутри FAT-образа.
Выходной файл не должен существовать. Исходный образ не изменяется.
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

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

# Путь к исходному boot.img, который скрипт читает и не перезаписывает.
source_img=$1
# Новый путь для отдельного неподписанного отладочного кандидата.
output_img=$2

[[ -f "$source_img" && -r "$source_img" ]] || fail "исходный образ не найден или не читается: $source_img"
command -v mtype >/dev/null 2>&1 || fail "не найдена команда mtype из пакета mtools"
command -v mcopy >/dev/null 2>&1 || fail "не найдена команда mcopy из пакета mtools"
command -v python3 >/dev/null 2>&1 || fail "не найдена команда python3"

# Канонизированные пути помогают запретить запись поверх самого источника.
source_real=$(readlink -f -- "$source_img") || fail "не удалось определить исходный путь"
output_real=$(readlink -m -- "$output_img") || fail "не удалось определить путь результата"
[[ "$source_real" != "$output_real" ]] || fail "выходной путь совпадает с исходным образом"
[[ ! -e "$output_img" ]] || fail "выходной файл уже существует; выбери новый путь"

# Папка со скриптом, вычисленная без привязки к текущему каталогу запуска.
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || fail "не удалось определить папку скрипта"
# Корень проекта, внутри которого разрешено сохранять отладочный образ.
project_root=$(dirname -- "$script_dir")
# Канонический корень проекта для ограничения выходного пути.
project_real=$(readlink -f -- "$project_root") || fail "не удалось определить корень проекта"
case "$output_real" in
  "$project_real"/*) ;;
  *) fail "выходной образ должен находиться внутри проекта: $project_real" ;;
esac
# Постоянная рабочая папка проекта для сохранения промежуточных данных.
work_root="$script_dir/work"
mkdir -p -- "$work_root" || fail "не удалось создать рабочую папку проекта"
# Каталог с исходной строкой и подготовленным cmdline.txt; остаётся в проекте для аудита.
work_dir=$(mktemp -d "$work_root/debug-copy-XXXXXX") || fail "не удалось создать рабочий каталог проекта"
# Контрольная сумма исходника до копирования.
source_hash_before=$(sha256sum -- "$source_img" | awk '{print $1}')

info "Читаю cmdline.txt из $source_img"
mtype -i "$source_img" ::cmdline.txt > "$work_dir/cmdline.original" || fail "не удалось прочитать cmdline.txt"

# Формирует минимальную командную строку, которая останавливает загрузку в shell initramfs.
python3 - "$work_dir/cmdline.original" "$work_dir/cmdline.debug" <<'PY'
from pathlib import Path
import sys

# Пути к исходной и отладочной командным строкам, переданные вызывающим скриптом.
исходный_путь = Path(sys.argv[1])
отладочный_путь = Path(sys.argv[2])

try:
    исходная_строка = исходный_путь.read_bytes().decode("ascii").strip()
except (OSError, UnicodeDecodeError) as ошибка:
    print(f"ОШИБКА: cmdline.txt не удалось прочитать как ASCII: {ошибка}", file=sys.stderr)
    raise SystemExit(1)

if not исходная_строка:
    print("ОШИБКА: исходный cmdline.txt пуст", file=sys.stderr)
    raise SystemExit(1)

# Полностью заменяет Pi-специфичные аргументы на безопасную консоль initramfs.
новая_строка = "console=ttyAMA0 rdinit=/bin/sh loglevel=7\n"
try:
    отладочный_путь.write_text(новая_строка, encoding="ascii", newline="")
except OSError as ошибка:
    print(f"ОШИБКА: cmdline.txt не удалось сохранить: {ошибка}", file=sys.stderr)
    raise SystemExit(1)
PY

mkdir -p -- "$(dirname -- "$output_img")" || fail "не удалось создать каталог результата"
cp -- "$source_img" "$output_img" || fail "не удалось скопировать исходный образ"
mcopy -o -i "$output_img" "$work_dir/cmdline.debug" ::cmdline.txt || fail "не удалось заменить cmdline.txt в копии"

# Проверяет, что FAT-операция не поменяла первые 512 байт внутреннего boot.img.
python3 - "$source_img" "$output_img" <<'PY'
from pathlib import Path
import sys

# Пути к исходному FAT-образу и созданной копии.
исходник = Path(sys.argv[1])
копия = Path(sys.argv[2])

try:
    with исходник.open("rb") as файл:
        исходный_сектор = файл.read(512)
    with копия.open("rb") as файл:
        сектор_копии = файл.read(512)
except OSError as ошибка:
    print(f"ОШИБКА: не удалось проверить начальный сектор: {ошибка}", file=sys.stderr)
    raise SystemExit(1)

if len(исходный_сектор) != 512 or исходный_сектор != сектор_копии:
    print("ОШИБКА: первые 512 байт исходника и копии различаются", file=sys.stderr)
    raise SystemExit(1)
PY

# Повторно хеширует исходник, чтобы обнаружить случайную запись в него.
source_hash_after=$(sha256sum -- "$source_img" | awk '{print $1}')
[[ "$source_hash_before" == "$source_hash_after" ]] || fail "контрольная сумма исходника изменилась"

info "Отладочная копия создана: $output_img"
printf 'Исходный SHA-256: %s\n' "$source_hash_after"
printf 'Копия SHA-256:    %s\n' "$(sha256sum -- "$output_img" | awk '{print $1}')"
printf 'Новая cmdline:    '
mtype -i "$output_img" ::cmdline.txt || fail "не удалось повторно прочитать cmdline.txt из копии"
printf 'Временные данные: %s\n' "$work_dir"
printf '%s\n' 'Внимание: boot.sig не пересчитана; физическая загрузка этой копии не подтверждена.'
