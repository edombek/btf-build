# AGENTS.md — guidance for automated agents working in this repo

## Что это за репозиторий

Репозиторий содержит **один скрипт сборки** (`build_generic.sh`) прошивок
[Betaflight](https://github.com/betaflight/betaflight) и документацию к нему
(`README.md`). Это **не** исходники Betaflight: дерево Betaflight клонируется
скриптом в `betaflight/` во время работы и не хранится в git.

Цель проекта — воспроизводимая сборка прошивок Betaflight без ручной установки
тулчейна: компиляция выполняется внутри официального docker-образа
`betaflight/betaflight-build`.

## Структура

```
build_generic.sh   # единственный исполняемый скрипт — вся логика сборки
README.md          # инструкция для пользователя + полная таблица опций
AGENTS.md          # этот файл
# создаются во время работы и НЕ коммитятся (см. .gitignore):
betaflight/        # клон Betaflight (тег/ветка из -b)
.build/            # кэш API-опций + staging для кастомных config.h
dist/              # готовые .hex
```

## Как работает сборка (ключевые детали)

1. `ensure_sources` — `git clone --depth 1 --branch <BF_VERSION>` либо
   `fetch`+`checkout` существующего клона. Дефолт версии — `2026.6.2`.
2. `ensure_submodules` — инициализация **всех** submodule'ов репо
   (`git submodule update --init --recursive`) **последовательно на хосте**.
   ⚠️ Не переносите это в `make -j` внутри контейнера: параллельные
   `git submodule update --init` конфликтуют на lock-файле `.git/config`
   (`could not lock config file .git/config: File exists`), из-за чего сборка
   падает на чистом клоне. В `.gitmodules` 10 записей, но 8 платформенных SDK
   (esp-idf, pico-sdk, STM32H5/N6/C5, GD32H7, X32M7, APM32F4) помечены
   `update = none` и git их намеренно пропускает («Пропуск подмодуля …» в логе —
   это норма); реально инициализируются `src/config` (конфиги плат) и
   `libcanard` (+ вложенный `avr-can-lib`).
3. Выбор режима цели (`set -e` не должен ронять скрипт на пустых проверках —
   используйте `if`, а не `cmd && action` верхнего уровня):
   - `-t/--target <ИМЯ>` → `make TARGET=<ИМЯ>` — базовый MCU-таргет;
     имена берутся из `src/platform/*/target/*/target.mk` (`base_targets`);
   - `-c/--config <файл|URL|каталог>` → кастомный конфиг: `config.h` кладётся в
     `.build/configs/configs/<ИМЯ>/config.h`, каталог монтируется в контейнер как
     `/configs`, передаётся `-e BETAFLIGHT_CONFIG=/configs`. Имя конфига — из
     `-n`, иначе из имени каталога вокруг `config.h` / из URL. MCU выводится из
     `FC_TARGET_MCU` внутри `config.h` (это делает сам Makefile Betaflight);
   - иначе — стандартный конфиг из submodule `src/config`
     (`configs/<ИМЯ>/config.h` или `configs/<ПРОИЗВОДИТЕЛЬ>/<ИМЯ>/config.h`).
4. Опции мастер-сборки конвертируются в defines Make через python-блок, читающий
   JSON из `fetch_options` (`build.betaflight.com/api/options/<версия>`) —
   результат: `make [OPTIONS="..."] hex`.

### Обязательные семантические правила опций

- При задании любой опции добавляется `CLOUD_BUILD` (как в облачной сборке
  Betaflight) — иначе `common_pre.h` включает **все** фичи по умолчанию, и
  прошивка получается другой. Флаг `--plain` отключает `CLOUD_BUILD`.
- **Зонтичные defines:** `CLOUD_BUILD`-сборка обязана передавать `USE_SERIALRX`
  при любом `USE_SERIALRX_*` протоколе — иначе `common_post.h:261` делает
  `#undef` всех протоколов serial RX, и в прошивке нет UART-приёмника
  (в Configurator «Режим приёмника» показывает только MSP). Официальный
  build.betaflight.com авто-дополняет набор (проверено эхом `POST /api/builds`):
  `USE_SERIALRX_* → USE_SERIALRX`; `USE_TELEMETRY_* → USE_TELEMETRY`;
  `USE_RX_PPM → USE_PPM`; `USE_GPS → USE_ALTITUDE_HOLD + USE_GPS_PLUS_CODES +
  USE_POSITION_HOLD`; OSD-протоколы → `USE_OSD`. Скрипт воспроизводит это в
  нормализации `OPT_LIST` (строки `# авто: +...` в выводе).
- Радио-протоколы с `includesTelemetry: true` автоматически добавляют
  `USE_TELEMETRY` + конкретный `USE_TELEMETRY_*` (CRSF→CRSF, FPORT→SMARTPORT,
  GHOST→GHST, JETIEXBUS→JETIEXBUS).
- OSD-опции (`USE_OSD_SD` / `USE_OSD_HD` / `USE_FRSKYOSD`) должны тянуть
  `USE_OSD` в явном виде.
- Полные имена опций, define'ы и флаги `default`/`includesTelemetry` берутся
  **только** из ответа build API — не заводите собственный список «магических»
  имён; при расхождении выигрывает API.
- OSD `Digital` исключает аналоговый чип `MAX7456` — это поведение Makefile
  Betaflight, не дублировать в скрипте.
- Старые версии Betaflight (до 2025.12) не имеют API опций: `fetch_options`
  завершается с подсказкой использовать `-D USE_XXX`.

### Важные факты об окружении сборки

- Betaflight 2026.6.2 требует **ровно** `arm-none-eabi-gcc 13.3.1`
  (`GCC_REQUIRED_VERSION` в `mk/tools.mk`). Системный компилятор не подходит;
  тулчейн — внутри docker-образа (`TOOLS_DIR=/opt/betaflight/tools`).
  Не пытайтесь добавить проверку/установку тулчейна на хост.
- Контейнер запускается с `-u "$(id -u):$(id -g)"`, чтобы артефакты в `betaflight/obj`
  принадлежали пользователю. В образе уже настроен `safe.directory`.
- `-c` принимает и готовые каталоги-корни с layout `configs/...` (например
  пользовательский `BETAFLIGHT_CONFIG`) — не ломайте этот сценарий.
- Кастомные конфиги нужны, потому что не все платы есть в `betaflight/config`
  (например `MICOAIR743V2_EXTMAG` от MicoAir).
- Не передавать `-D USE_SDCARD_SDIO`: для STM32H743 его уже определяет
  платформенный `src/platform/STM32/target/STM32H743/target.h` при наличии
  `USE_SDCARD`, и `-Werror` даёт «redefined».
- В Betaflight 2026 нет `FEATURE_BLACKBOX` — запись включается параметром
  `blackbox_device` (дефолт из `DEFAULT_BLACKBOX_DEVICE` в конфиге платы).
  Таких флагов, как `USE_ELRSV4`, тоже нет: ELRS работает через
  `USE_SERIALRX_CRSF` (+ автоматический `USE_CRSF_V3`).
- При `USE_VTX` драйверы `USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP/TABLE`
  подключаются в `common_pre.h:337` — этот блок находится **вне** гейта
  `CLOUD_BUILD`, поэтому `-f VTX` достаточно (при наличии `VTX_DATA_PIN` в конфиге).
- Проверять «попала ли фича в прошивку» через `nm` по `.o` нельзя (LTO) —
  смотреть символы в `*.map` (например `sdcardSdio_isFunctional`). Для
  статических функций (например `crsfRxInit`) символа в map может не быть —
  LTO их интернирует/встраивает; смотреть **другие** символы фичи (для CRSF RX
  — `crsfDataReceive`, `crsfChannelData`; в `nm` финального `.elf`). Строки
  `LOAD .../<file>.o` в map — НЕ доказательство: файл, целиком выключенный
  `#ifdef`, тоже даёт LOAD-строку пустого объекта. `serialRxBytesWaiting` —
  общая функция `io/serial.c`, она есть всегда и про протоколы RX ничего не
  говорит. Тулчейн (`arm-none-eabi-nm/objdump`) — в docker-образе,
  `/opt/betaflight/tools/.../bin`, в PATH его нет.
- `USE_RX_MSP`/`USE_RX_MSP_OVERRIDE` определяются в `common_pre.h:366` вне
  гейта `CLOUD_BUILD` — MSP-RX (каналы по MSP от HDZero/Walksnail и т.п.)
  есть в любой сборке; отдельным флагом не включается. Блок дефолтов
  «всех фич» в common_pre.h — это `#if !defined(CLOUD_BUILD)` (строки 52–282),
  вне него — условные автозависимости (CRSF v3 и т.п.).

## Как проверять изменения

Перед коммитом:

```bash
bash -n build_generic.sh                     # синтаксис
./build_generic.sh --help >/dev/null         # справка
./build_generic.sh --list-options | head     # маппинг опций
./build_generic.sh --list-configs | head     # стандартные конфиги
./build_generic.sh --list-targets | head     # базовые таргеты
./build_generic.sh MICOAIR743V2EXTMAG        # негативный кейс: подсказки похожих имён
./build_generic.sh MICOAIR743V2 --radio CRSF --feat "Foo Bar"   # негативный кейс опции
./build_generic.sh -t STM32H743 --radio CRSF,MAVLINK --preview  # список радио + показ команды
```

Полная проверка (несколько минут, нужен docker и сеть):

```bash
# кастомный config.h (MicoAir743V2_EXTMAG)
./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
    --radio CRSF --osd Digital --motor DSHOT \
    -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"
# стандартный конфиг
./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT -f "GPS,VTX,LED Strip"
# базовый MCU-таргет
./build_generic.sh -t STM32H743 --motor DSHOT
```

Ожидаемый признак успеха: `Creating HEX ./obj/betaflight_<версия>_<цель>.hex`
и строка `==> Готово:`. MD5 hex **не** является признаком идентичности сборок:
Betaflight встраивает дату сборки в `version.o`, поэтому хеши различаются даже
при одинаковом наборе опций. Для проверки эквивалентности сравнивайте строку
`==> Опции:` и usage-строки из `map`-файла.

## Соглашения

- Bash: `set -euo pipefail`; `if`/`fi` вместо `cmd && action` верхнего уровня;
  `${arr[@]+"${arr[@]}"}` для пустых массивов; `[[ ]]` только для паттернов.
- Скрипт самодостаточен: один файл, без внешних зависимостей кроме
  `docker`/`git`/`curl`/`python3` на хосте. Не вводите сборку/установку пакетов.
- Сообщения пользователю и справка — на русском, имена флагов — английские.
- Логи сборки не перенаправлять в файл (кроме логов, уже принятых в скрипте) —
  пользователю нужен живой вывод `make`.
- Изменения опционных правил должны сопровождаться правкой таблиц в `README.md`
  (полный список опций генерируется из `--list-options`).

## Чего не делать

- Не коммитить `betaflight/`, `dist/`, `.build/`, `*.hex`, `*.elf`, `*.map`,
  cli-дампы Configurator (`*cli_backup*`) и любые прошивки.
- Не заменять docker-образ на установку тулчейна на хосте и не понижать/повышать
  версию GCC в обход образа.
- Не хранить секреты/токены; доступ к GitHub — через `gh`/SSH.
- Не переписывать скрипт под одну конкретную плату — приватные варианты вроде
  `build_micoair743v2_extmag.sh` не плодить: они воспроизводятся одной командой
  `build_generic.sh` (пример в README).

## Полезные внешние ссылки

- Build API опций: `https://build.betaflight.com/api/options/<версия>`
- Конфиги плат: https://github.com/betaflight/config
- Docker-образы тулчейна: https://github.com/betaflight/betaflight-build
- Система сборки Betaflight: `Makefile`, `mk/config.mk`, `mk/tools.mk`,
  `src/main/target/common_pre.h`, `src/main/msp/msp_build_info.h`
