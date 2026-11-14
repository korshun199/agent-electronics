# Полное чтение Flash полётного контроллера BEASTFPVF722

Дата подготовки: 2026-11-12.

## Цель и подтверждённая память

В конфиге `/home/work/firmware/RAsBERY_DRON.txt` указан Betaflight target `BEASTFPVF722`. Страница производителя для этого стека указывает MCU `STM32F722RET6`; ST указывает для этой модели 512 Кбайт встроенной Flash.

Значит, полный образ основной пользовательской Flash читается из диапазона:

- начало: `0x08000000`;
- размер: `0x80000` байт = `524288` байт;
- конец диапазона не включительно: `0x08080000`.

Это образ основной Flash MCU. Он не включает ROM системного загрузчика, OTP, option bytes или прошивку отдельного ESC.

## Выбранный способ

У STM32F722 есть встроенный USB DFU-загрузчик. Его можно открыть кнопкой `BOOT` при подключении USB, затем прочитать память штатным STM32CubeProgrammer. Текущий USB-интерфейс FC в среде Codex виден как CDC (`0483:5740`), но `/dev/bus/usb` и устройство `ttyACM` недоступны процессу; `dfu-util` не может открыть libusb. ST-Link в этой среде не обнаружен (`st-info --probe`: 0 программаторов). Поэтому фактическое чтение нужно выполнить через STM32CubeProgrammer на компьютере, где контроллер подключён.

## Порядок чтения

1. Снять пропеллеры, отключить LiPo и другое внешнее питание FC/ESC. Отсоединить FC от Raspberry Pi, чтобы чтение не прерывало работу Pi и не было двух источников питания. Для чтения оставить только USB от компьютера.
2. Подключить FC в режим DFU: удерживать именно подписанную кнопку `BOOT` во время подключения USB и отпустить после подключения. Не замыкать неизвестные площадки и не менять перемычки.
3. В диспетчере устройств или списке USB проверить, что устройство стало `STM32 BOOTLOADER` / `0483:DF11`. Обычное появление `Betaflight STM32F7x2` / `0483:5740` означает штатный CDC-интерфейс, а не DFU. Если DFU не появился — остановиться, не экспериментировать с контактами.
4. В STM32CubeProgrammer выбрать интерфейс `USB` и подключиться. До чтения убедиться, что утилита распознала STM32F722. Вкладку Option Bytes можно только просмотреть; ничего в ней не менять.
5. Считать диапазон `0x08000000`, размер `0x80000`, сохранить как бинарный файл:
   `/home/work/tmp/BEASTFPVF722_STM32F722RET6_flash_20261112.bin`

   Если используется CLI STM32CubeProgrammer, эквивалентная команда чтения:

   ```text
   STM32_Programmer_CLI -c port=USB1 --upload 0x08000000 524288 "/home/work/tmp/BEASTFPVF722_STM32F722RET6_flash_20261112.bin"
   ```

   `--upload` — команда чтения во внешний файл. Не использовать команды записи, стирания или снятия защиты: `-w`, `-d`, `-e`, `-rdu` / `--readunprotect`.

6. Проверить размер и посчитать SHA-256:

   ```bash
   stat -c '%s bytes' /home/work/tmp/BEASTFPVF722_STM32F722RET6_flash_20261112.bin
   sha256sum /home/work/tmp/BEASTFPVF722_STM32F722RET6_flash_20261112.bin
   ```

   Принимать файл как полный дамп только если размер ровно `524288` байт и операция чтения завершилась без ошибки.
7. Отключить USB, снова подключить FC без удержания `BOOT` и проверить, что он вернулся к обычному USB-режиму. Это подтверждает только возврат USB-интерфейса, не готовность к полёту.

## Если чтение запрещено

Если CubeProgrammer сообщает о read protection/RDP или не читает диапазон, остановиться и сохранить точный текст ошибки. Не нажимать `Read Unprotect`, не выполнять `-rdu` и не менять Option Bytes: снятие RDP уровня 1 у STM32 стирает пользовательскую Flash. Такой результат не является основанием для обхода защиты.

## Полученный файл и проверка

Владелец предоставил `/home/work/tmp/RASPBERRY_DRON.bin` (2026-11-12). Проверено:

- размер: `524288` байт;
- SHA-256: `37fd659bd21d285c75fc8c6570ae566de0cb55122426967b45911d0f5cd702ed`;
- образ распознаётся как ARM Cortex-M и содержит `BEASTFPVF722`, `Betaflight` и `4.5.1`;
- вектор reset `0x08056241` находится внутри пользовательской Flash;
- последний диапазон `0x08070000..0x0807FFFF` заполнен `0xFF`.

Эти признаки согласуются с полным 512-КиБ образом нужного полётника. Лог STM32CubeProgrammer и способ получения файла не приложены, поэтому точный адрес исходного чтения и принадлежность бинарника конкретной плате не подтверждены независимой записью подключения.

- Размер файла и SHA-256 уже проверены; статус и лог операции чтения отдельно не сохранились.
- Исходный дамп хранить в `/home/work/tmp`, не добавлять в Git: это индивидуальная копия прошивки конкретного устройства.

## Извлечённая сохранённая конфигурация

Дамп разобран только чтением по формату Betaflight 4.5.1. Найдено:

- заголовок EEPROM-структуры в смещении `0x4000` (адрес `0x08004000`), версия `0xB1`, маркер `0xBE`;
- 81 последовательная запись parameter group; структура заканчивается в смещении `0x4FEC`;
- CRC-16/CCITT всего блока сходится с контрольным значением Betaflight `0x1D0F`;
- остаток диапазона `0x4FEC..0x7FFF` заполнен `0xFF`;
- запись `PG_SERIAL_CONFIG` (PGN 13, версия 1) находится в смещении `0x484C`, размер записи 118 байт, из них 112 байт данных.

Первые семь стандартных портов в этой записи декодируются и совпадают с предоставленным CLI-экспортом:

- USB VCP: MSP, 115200 бод;
- UART1: Serial RX;
- UART2 и UART3: без функций;
- UART4: VTX Tramp;
- UART5: MSP, 500000 бод;
- UART6: без функций;
- `serial_update_rate_hz`: 1000.

Следовательно, сохранённая во Flash конфигурация подтверждает назначение UART5 для MSP на 500000 бод, а UART1 — для последовательного приёмника. Это независимое подтверждение настроек из самого бинарного дампа; оно не доказывает, что Pi физически подключён к UART5, и не является захватом обмена.

Структуру EEPROM и CRC сверяли по исходникам Betaflight 4.5.1. Полный дамп и его SHA-256 уже проверены; лог CubeProgrammer и статус завершения чтения отдельно не сохранились. Исходный дамп хранить в `/home/work/tmp`, не добавлять в Git: это индивидуальная копия прошивки конкретного устройства.

## Источники

- [Страница производителя BEASTFPV F722 BLS 65A: MCU и target](https://beastfpv.ru/product/beastfpv-f722-bls-65a-fcesc-stack/)
- [ST: STM32F722RE, память Flash до 512 Кбайт](https://www.st.com/en/microcontrollers-microprocessors/stm32f722re.html)
- [ST AN2606: системный загрузчик STM32F722/F723, USB DFU](https://www.st.com/resource/en/application_note/an2606-stm32microcontroller-system-memory-boot-mode-stmicroelectronics.pdf)
- [ST AN3156: USB DFU и чтение памяти; чтение запрещено при активной защите](https://www.st.com/resource/en/application_note/an3156-how-to-use-usb-dfu-protocol-in-bootloader-on-stm32-mcus-stmicroelectronics.pdf)
- [ST AN5156: RDP; снятие защиты переводом с уровня 1 на уровень 0 уничтожает защищённое содержимое Flash](https://www.st.com/content/st_com/en/technical-documents/an5156-introduction-to-security-for-stm32-mcus-stmicroelectronics.html)
- [STM32CubeProgrammer CLI: команда `--upload`](https://dev.st.com/stm32cube-docs/prog/2.23.0/en/docs/markup/CubeProg_Command_Lines.html)
- [Betaflight: вход в DFU кнопкой BOOT](https://github.com/betaflight/betaflight.com/blob/master/docs/wiki/guides/current/USB-Flashing.md)
- [Betaflight 4.5.1: формат сохранённой конфигурации и CRC](https://raw.githubusercontent.com/betaflight/betaflight/4.5.1/src/main/config/config_eeprom.c)
- [Betaflight 4.5.1: идентификатор PG_SERIAL_CONFIG](https://raw.githubusercontent.com/betaflight/betaflight/4.5.1/src/main/pg/pg_ids.h)
- [Betaflight 4.5.1: структура serialConfig и portConfigs](https://raw.githubusercontent.com/betaflight/betaflight/4.5.1/src/main/io/serial.h)
- [Betaflight 4.5.1: enum baud rates, идентификаторы портов и reset values](https://raw.githubusercontent.com/betaflight/betaflight/4.5.1/src/main/io/serial.c)

## Граница проверки

Документация, размер/хеш файла и внутренние признаки прошивки проверены. Историю подключения и команду, которыми был прочитан файл, подтвердить нельзя: в среде Codex нет доступного USB device node и не обнаружен ST-Link. Состояние RDP отдельно не установлено. Запись, стирание и снятие защиты не выполнялись.
