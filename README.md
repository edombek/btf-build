# Сборка прошивок Betaflight (2026.6.2) для MicoAir743V2 и других плат

[Русский](README.md) | [English](README.en.md)

Скрипт собирает прошивки Betaflight в официальном docker-образе тулчейна
[`betaflight/betaflight-build`](https://hub.docker.com/r/betaflight/betaflight-build)
(внутри — ровно `arm-none-eabi-gcc 13.3.1`, требуемый системой сборки Betaflight 2026.6.2).
На хосте нужны только **docker**, **git** и **curl**.

| Команда | Назначение |
|---|---|
| `./build_generic.sh` | любая цель: стандартный конфиг платы, кастомный `config.h` (например MicoAir743V2_EXTMAG) или базовый MCU-таргет + любые опции |

## Быстрый старт

```bash
# MicoAir743V2_EXTMAG (custom config от MicoAir), опции со скриншота мастера прошивки:
./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
    --radio CRSF --osd Digital --motor DSHOT \
    -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"

# стандартный конфиг платы из betaflight/config:
./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT -f "GPS,VTX,LED Strip"

# базовый MCU-таргет без конфига платы:
./build_generic.sh -t STM32H743
```

Результат: `dist/betaflight_<версия>_<цель>.hex` (elf/map — в `betaflight/obj/`).

## Как это работает

1. Клонируется/обновляется `betaflight` на нужный тег (`-b`, по умолчанию `2026.6.2`);
   submodule'ы инициализируются на хосте все, объявленные в репо
   (`git submodule update --init --recursive`; параллельная инициализация внутри
   `make -j` конфликтует на lock-файле git). Платформенные SDK, помеченные в
   `.gitmodules` как `update = none` (esp-idf, pico-sdk, STM32H5/N6/C5, GD32H7,
   X32M7, APM32F4), git пропускает — так задумано upstream.
2. Для кастомного конфига `config.h` скачивается/копируется в
   `.build/configs/configs/<ИМЯ>/config.h` и передаётся в сборку через
   `BETAFLIGHT_CONFIG` (в 2026.x конфиги плат живут в отдельном репо
   [betaflight/config](https://github.com/betaflight/config); таргета
   `MICOAIR743V2_EXTMAG` там нет — он кастомный от MicoAir).
3. Сборка выполняется в контейнере:
   `make -j CONFIG=<ИМЯ>|TARGET=<ИМЯ> [OPTIONS="..."] hex`.

## Универсальный скрипт: `build_generic.sh`

```
./build_generic.sh [параметры] <конфиг|таргет>
```

### Цель сборки

| Вариант | Пример |
|---|---|
| Стандартный конфиг платы (из `betaflight/config`, ~650 плат) | `./build_generic.sh MATEKF405TE` — список: `--list-configs` |
| Кастомный `config.h` (файл, URL или каталог) | `-c path/to/config.h`, `-c <URL>`, `-c ./my_configs` (с layout `configs/<ИМЯ>/config.h`); MCU берётся из `FC_TARGET_MCU` в config.h |
| Базовый MCU-таргет | `-t STM32H743` — список: `--list-targets` (33 таргета: STM32F4/F7/G4/H7, AT32, APM32, RP2350, ESP32 и т.д.) |

### Выбор опций (как в мастере прошивки Configurator / build.betaflight.com)

| Параметр | Значения |
|---|---|
| `--radio` | CRSF, FPORT, GHOST, IBUS, JETIEXBUS, MAVLINK, PPM, SBUS, SPEKTRUM, SRXL2, SUMD, SUMH, XBUS — можно несколько через запятую (`--radio CRSF,MAVLINK`) |
| `--telemetry` | FRSKY_HUB, HOTT, IBUS_EXTENDED, LTM, MAVLINK, SMARTPORT, SRXL, none (также списком; CRSF/GHOST/FPORT/JETIEXBUS включают телеметрию автоматически) |
| `--osd` | Analog, Digital, FrSky, none (можно несколько) |
| `--motor` | BRUSHED, DSHOT, MULTISHOT, ONESHOT, PROSHOT, PWM |
| `-f, --feat` | остальные опции именами из UI, через запятую или параметром повторно |
| `-D, --define` | произвольный define мимо API (например `USE_EMFAT_TOOLS`) |
| `-v, --verbose` | печатать расшифровку опций: `# имя -> DEFINE`, `# auto: +DEFINE` (по умолчанию молчит) |
| `--plain` | не добавлять `CLOUD_BUILD`: опции накладываются поверх «всех по умолчанию» |
| `--list-options` | все опции выбранной версии BF живьём из API |

Выбранные опции транслируются в defines по официальному API
`https://build.betaflight.com/api/options/<версия>` и передаются в `make OPTIONS=...`
с префиксом `CLOUD_BUILD` (так же работает облачная сборка беты: в прошивку попадает
ровно выбранный набор; без флагов опций собирается plain-сборка со всеми фичами по умолчанию).
Скрипт так же, как официальный сервер, автоматически добавляет «зонтичные» defines
(`USE_SERIALRX_*` → `USE_SERIALRX`, `USE_TELEMETRY_*` → `USE_TELEMETRY`,
`USE_RX_PPM` → `USE_PPM`, `USE_GPS` → `USE_ALTITUDE_HOLD/USE_GPS_PLUS_CODES/USE_POSITION_HOLD`,
OSD → `USE_OSD`) — без них часть опций не попадает в прошивку (см. раздел
«ELRS / управляющие каналы приёмника»).
Для `--radio CRSF/GHOST/FPORT/JETIEXBUS` телеметрия добавляется автоматически
(строка «Automatically included» в UI).

### Прочие параметры

| Параметр | Описание |
|---|---|
| `-b, --bf-version` | тег/ветка Betaflight (дефолт `2026.6.2`) |
| `-i, --image` | docker-образ тулчейна (дефолт `betaflight/betaflight-build:arm`; если нужен образ конкретной ветки — собрать самому: `git clone https://github.com/betaflight/betaflight-build && cd betaflight-build && ./build-image.sh -r 2026.6.2 arm`) |
| `-n, --name` | имя кастомного конфига (по умолчанию из имени каталога/URL `config.h`) |
| `--preview`, `--dry-run` | показать полную команду `docker … make …` вместо запуска сборки (проверка цели и опций) |

**Radio Protocol**

| Опция (UI) | define | Примечание |
|---|---|---|
| CRSF | `USE_SERIALRX_CRSF` | по умолчанию, телеметрия включается автоматически |
| FPORT | `USE_SERIALRX_FPORT` | телеметрия включается автоматически |
| GHOST | `USE_SERIALRX_GHST` | телеметрия включается автоматически |
| IBUS | `USE_SERIALRX_IBUS` |  |
| JETIEXBUS | `USE_SERIALRX_JETIEXBUS` | телеметрия включается автоматически |
| MAVLINK | `USE_SERIALRX_MAVLINK` |  |
| PPM | `USE_RX_PPM` |  |
| SBUS | `USE_SERIALRX_SBUS` |  |
| SPEKTRUM | `USE_SERIALRX_SPEKTRUM` |  |
| SRXL2 | `USE_SERIALRX_SRXL2` |  |
| SUMD | `USE_SERIALRX_SUMD` |  |
| SUMH | `USE_SERIALRX_SUMH` |  |
| XBUS | `USE_SERIALRX_XBUS` |  |

**Telemetry Protocol**

| Опция (UI) | define | Примечание |
|---|---|---|
| [None] | `—` |  |
| FRSKY_HUB | `USE_TELEMETRY_FRSKY_HUB` |  |
| HOTT | `USE_TELEMETRY_HOTT` |  |
| IBUS EXTENDED | `USE_TELEMETRY_IBUS_EXTENDED` |  |
| LTM | `USE_TELEMETRY_LTM` |  |
| MAVLINK | `USE_TELEMETRY_MAVLINK` |  |
| SMARTPORT | `USE_TELEMETRY_SMARTPORT` |  |
| SRXL | `USE_TELEMETRY_SRXL` |  |

**General Options**

| Опция (UI) | define | Примечание |
|---|---|---|
| Acro Trainer | `USE_ACRO_TRAINER` | по умолчанию |
| AKK (SA FIX) | `USE_AKK_SMARTAUDIO` |  |
| Altitude Hold | `USE_ALTITUDE_HOLD` |  |
| Batt. Continue | `USE_BATTERY_CONTINUE` |  |
| Cam. Control | `USE_CAMERA_CONTROL` |  |
| Chirp | `USE_CHIRP` |  |
| Dashboard | `USE_DASHBOARD` |  |
| EMFAT (AutoRun, Icon) | `USE_EMFAT_TOOLS` |  |
| ESC Serial (SK) inc. 4way | `USE_ESCSERIAL_SIMONK` |  |
| Flight Plan | `USE_FLIGHT_PLAN` |  |
| GPS | `USE_GPS` | по умолчанию |
| LED Strip | `USE_LED_STRIP` | по умолчанию |
| LED Strip (64) | `USE_LED_STRIP_64` |  |
| Magnetometers | `USE_MAG` |  |
| Optical Flow | `USE_OPTICALFLOW` | по умолчанию |
| OSD (Analog) | `USE_OSD_SD` | по умолчанию |
| OSD (Digital) | `USE_OSD_HD` | по умолчанию |
| OSD (FrSky) | `USE_FRSKYOSD` |  |
| Pin IO | `USE_PINIO` | по умолчанию |
| Position Hold | `USE_POSITION_HOLD` |  |
| Race Pro | `USE_RACE_PRO` |  |
| Range Finder | `USE_RANGEFINDER` | по умолчанию |
| Soft Serial | `USE_SOFTSERIAL` |  |
| Servos | `USE_SERVOS` |  |
| VTX | `USE_VTX` | по умолчанию |
| Wing | `USE_WING` |  |

**Motor Protocol**

| Опция (UI) | define | Примечание |
|---|---|---|
| BRUSHED | `USE_BRUSHED` |  |
| DSHOT | `USE_DSHOT` | по умолчанию |
| MULTISHOT | `USE_MULTISHOT` |  |
| ONESHOT | `USE_ONESHOT` |  |
| PROSHOT | `USE_PROSHOT` |  |
| PWM | `USE_PWM_OUTPUT` |  |

### Полный набор defines

Кроме перечисленных в таблицах (это опции мастера прошивки) в `make` можно передать
любые внутренние defines Betaflight через `-D` — например `USE_USB_CDC_HID`,
`USE_RANGEFINDER`, `USE_OPTICALFLOW`, `USE_SOFTSERIAL`, `USE_DSHOT_BITBANG` и т.д.
(см. `src/main/target/common_pre.h` / `common_post.h`).

## Кто какие флаги добавляет

Defines в команду `make OPTIONS=...` приходят из нескольких мест; заголовки
Betaflight затем сами доопределяют и «вычищают» лишнее:

| Источник | Когда | Что добавляет |
|---|---|---|
| Configurator (мастер прошивки) | облачная сборка | только выбранные значения (`USE_SERIALRX_CRSF`, …) + `CLOUD_BUILD` (или `CORE_BUILD`); никаких зонтиков и телеметрий — `src/composables/useCloudBuild.ts` |
| сервер build.betaflight.com | `POST /api/builds` | `USE_SERIALRX_* → USE_SERIALRX`; `USE_TELEMETRY_* → USE_TELEMETRY`; `USE_RX_PPM → USE_PPM`; `USE_GPS → USE_ALTITUDE_HOLD + USE_GPS_PLUS_CODES + USE_POSITION_HOLD` (проверено по эху запроса) |
| `build_generic.sh` | всегда | `CLOUD_BUILD` (если не `--plain`); defines из API по вашим `--radio/--telemetry/--osd/--motor/-f`; те же авто-дополнения, что и сервер, + `USE_OSD` для OSD-протоколов + `USE_TELEMETRY + USE_TELEMETRY_MAVLINK` для `USE_SERIALRX_MAVLINK` |
| Makefile Betaflight | при сборке | `OPTIONS="X Y"` → глобальные `-DX -DY` (`Makefile:375`, `mk/preprocess.mk:16`); `CORE_BUILD` — минимальный набор фич |
| `common_pre.h` | при компиляции | без `CLOUD_BUILD` — дефолты всех фич (блок `:72–282`); вне зависимости от режима: `USE_RX_MSP/USE_RX_MSP_OVERRIDE/USE_RX_RSSI_DBM/USE_RX_RSNR/USE_RX_LINK_UPLINK_POWER` (`:408–412`); цепочки: `USE_VTX → USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP/TABLE` (`:337`), `USE_SERIALRX_CRSF → USE_CRSF_V3` (+CMS-телеметрия/линк-статистика при CRSF-телеметрии, `:481`), `USE_SERIALRX_MAVLINK → USE_TELEMETRY_MAVLINK` (`:494`), `USE_TELEMETRY_SRXL → USE_SERIALRX_SPEKTRUM + управление VTX Spektrum` (`:395` for USE_TELEMETRY_SRXL), `USE_GPS+USE_OSD → USE_CMS_GPS_RESCUE_MENU` |
| `common_post.h` | «уборка» | сиротливые defines удаляются: без `USE_SERIALRX` — все `USE_SERIALRX_*` (`:340`), без `USE_TELEMETRY` — все `USE_TELEMETRY_*` (`:355`), без `USE_SERIALRX_CRSF` — `USE_TELEMETRY_CRSF/USE_CRSF_V3` (`:393`); FPORT/IBUS_EXTENDED/JETIEXBUS, напротив, сами возвращают себе `USE_TELEMETRY + USE_TELEMETRY_*` (`:368–392`) |
| платформенный `src/platform/*/target/*/target.h` | на каждый MCU | драйверы MCU: STM32H743 — `USE_I2C/USE_SPI/USE_ADC/USE_BEEPER/USE_ESCSERIAL…`, а `USE_SDCARD → USE_SDCARD_SPI + USE_SDCARD_SDIO + ENABLE_SDIO_INIT` (`:71–81`) |
| `config.h` платы (betaflight/config или кастомный) | на каждую плату | `USE_SDCARD`, пины SDIO/UART/I2C, `DEFAULT_BLACKBOX_DEVICE`, `VTX_DATA_PIN`, пины SPI-ELRS и т.п. |

Практические следствия: `-D` из `OPTIONS` не должен дублировать то, что уже
определяет `target.h` (будет `-Werror: redefined`); «пропавшая» фича чаще всего
означает отсутствие зонтика (`USE_SERIALRX`/`USE_TELEMETRY`) — `common_post.h`
её вычистил.

## Опции прошивки MICOAIR743V2_EXTMAG (скриншот)

| Параметр в UI | Define |
|---|---|
| Radio Protocol: CRSF | `USE_SERIALRX_CRSF` |
| Telemetry: Automatically included | `USE_TELEMETRY` + `USE_TELEMETRY_CRSF` |
| OSD Protocol: Digital | `USE_OSD` + `USE_OSD_HD` |
| Motor Protocol: DSHOT | `USE_DSHOT` |
| Altitude Hold | `USE_ALTITUDE_HOLD` |
| Batt. Continue | `USE_BATTERY_CONTINUE` |
| Dashboard | `USE_DASHBOARD` |
| LED Strip | `USE_LED_STRIP` |
| Pin IO | `USE_PINIO` |
| Chirp | `USE_CHIRP` |

Замечания:

- OSD Digital исключает аналоговый OSD-чип MAX7456 из прошивки (OSD идёт по
  MSP DisplayPort — UART2 в конфиге платы). Для аналогового OSD добавьте `--osd Analog`
  или `-f "OSD (Analog)"`.
- GPS (UART3 в конфиге платы) в набор со скриншота не входит; добавляется `-f GPS`
  (GPS Rescue подтягивается автоматически).

## Частые вопросы по MicoAir743V2: SD-карта, VTX, ELRS

### SD-карта / BlackBox

- Драйвер SD-карты **уже включён** в прошивку: платформенный
  `src/platform/STM32/target/STM32H743/target.h` автоматически определяет
  `USE_SDCARD_SDIO`/`USE_SDCARD_SPI` при наличии `USE_SDCARD` в конфиге платы
  (он там есть). Передавать `-D USE_SDCARD_SDIO` не нужно — будет ошибка
  `-Werror: "USE_SDCARD_SDIO" redefined`. Проверить наличие в прошивке:
  `grep sdcardSdio_isFunctional betaflight/obj/main/*.map`.
- В Betaflight 2026 больше **нет** переключателя `feature blackbox` — запись
  включается параметром `blackbox_device` (в конфиге MicoAir по умолчанию уже
  `sdcard`). Если карта «не работает»: прошивка с Full chip erase, затем в CLI
  `sdcard_info` (должна видеться карта), `show blackbox_device`, `save`.

### Управление VTX по UART (SmartAudio/Tramp)

В конфигах MicoAir743V2 (EXTMAG и INTMAG) **нет выводов управления VTX**
(`VTX_DATA_PIN`/`VTX_ENABLE_PIN` не определены). Плата рассчитана на цифровые
(HDZero) системы, где VTX управляется по MSP/DisplayPort — то есть «только MSP»
для этой платы корректно и флагами не лечится.

Если аналоговый VTX с SmartAudio физически подключён к таймерному выводу платы,
добавьте в свой `config.h` строку `#define VTX_DATA_PIN <пин>` и собирайте
с `-f VTX`: при `USE_VTX` драйверы `USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP`
подключаются автоматически (`common_pre.h:337`, вне гейта `CLOUD_BUILD`).

### ELRS / управляющие каналы приёмника (RX)

Флагов вида `USE_ELRSV4` в Betaflight 2026.6.2 нет — ни в build API, ни в
исходниках. Внешний ELRS-приёмник (любой версии, включая 4.x), подключённый
к UART, — это протокол CRSF: `--radio CRSF`.

**Важный нюанс `CLOUD_BUILD`:** одного `USE_SERIALRX_CRSF` недостаточно —
нужен ещё «зонтичный» define `USE_SERIALRX`, иначе `common_post.h:340`
отключает все `USE_SERIALRX_*` протоколы и в прошивке не оказывается никакого
UART-приёмника (во вкладке «Режим приёмника» доступен только MSP). Официальный
build.betaflight.com добавляет такие авто-defines сам (проверено по эху
`POST /api/builds`), и скрипт повторяет его правила:

| Выбрано | Скрипт добавляет автоматически |
|---|---|
| любой `USE_SERIALRX_*` (CRSF, SBUS, FPORT, SRXL2, ...) | `USE_SERIALRX` |
| любой `USE_TELEMETRY_*` | `USE_TELEMETRY` |
| `USE_SERIALRX_MAVLINK` | `USE_SERIALRX + USE_TELEMETRY + USE_TELEMETRY_MAVLINK` |
| `USE_RX_PPM` | `USE_PPM` |
| `USE_GPS` | `USE_ALTITUDE_HOLD`, `USE_GPS_PLUS_CODES`, `USE_POSITION_HOLD` |
| OSD `USE_OSD_SD/HD` / `USE_FRSKYOSD` | `USE_OSD` |

(добавки видны с `-v` в выводе как `# auto: +USE_SERIALRX`; `USE_CRSF_V3` включает
сам Makefile — `common_pre.h:481`). Для радио **MAVLINK** скрипт добавляет
`USE_TELEMETRY + USE_TELEMETRY_MAVLINK` чуть больше официального сервера: по
исходникам «SERIALRX_MAVLINK provider can not work without TELEMETRY_MAVLINK»
(`common_pre.h:494` авто-определяет его), но без «зонтика» `USE_TELEMETRY`
`common_post.h:354` этот define стирает — поэтому скрипт передаёт оба явно
(в облачной сборке тот же результат даёт авто-define из `common_pre.h`, если
телеметрия уже включена другим протоколом). Пропроверить UART-RX в готовой прошивке:
`arm-none-eabi-nm obj/main/*.elf | grep -i crsf` — должны быть `crsfDataReceive`,
`crsfChannelData` и т.п. Прошивки, собранные до добавления этого правила,
CRSF-приёмник не содержали — перешейте заново.

В «Портах» на UART приёмника должна стоять функция **Serial RX** (TX
приёмника → RX платы), во вкладке «Приёмник» протокол — **CRSF**; фича
`RX_SERIAL` включена по умолчанию (`DEFAULT_RX_FEATURE`, `feature.h:31`).

Если каналы передаются по MSP (например приёмник цифровой видеосистемы
HDZero/Walksnail), используется `USE_RX_MSP` + `USE_RX_MSP_OVERRIDE` — они
определяются в `common_pre.h:408` **вне гейта `CLOUD_BUILD`**, т.е. присутствуют
в прошивке всегда; дополнительно ничего собирать не нужно. В CLI —
`feature RX_MSP`.

Флаг `USE_RX_EXPRESSLRS` существует только для плат со встроенным SPI-модулем
ELRS и требует дополнительные пины (`RX_EXPRESSLRS_SPI_RESET_PIN`,
`RX_EXPRESSLRS_SPI_BUSY_PIN`, `RX_SPI_CS`, ...) в конфиге платы — в
MicoAir743V2 встроенного приёмника нет.

## Проверенные сборки (Betaflight 2026.6.2)

| Цель | Результат |
|---|---|
| `MICOAIR743V2_EXTMAG` (кастомный конфиг MicoAir, опции со скриншота) | hex 1,2 МБ, FLASH ~430 КБ (24 %), RAM 15,3 % — в elf подтверждены CRSF-RX (`crsfDataReceive`), телеметрия, OSD HD, DSHOT, alt-hold, chirp, dashboard, pinio, ledstrip; нет GPS и MAX7456 |
| `MICOAIR743V2` (стандартный конфиг + GPS, VTX; GPS авто-тянет alt-hold/poshold) | FLASH1 490 КБ (26,7 %) |
| `-t STM32H743 --motor DSHOT` (CLOUD_BUILD, минимум) | FLASH1 276 КБ |

## Прошивка готовой прошивки

1. Подключите FC в DFU (удерживая BOOT0 подать питание) или через Configurator.
2. **Betaflight Configurator 10.13+**: Firmware Flasher → «Load firmware (hex)» → файл
   из `dist/` → Flash (можно «Full chip erase» при смене версии).

   Из командной строки:
   ```bash
   arm-none-eabi-objcopy -I ihex -O binary dist/<файл>.hex firmware.bin
   st-flash --reset write firmware.bin 0x08000000
   ```

## Возможные проблемы

- `build API не знает версию ...` — у старых версий (4.5 и т.п.) нет API опций:
  используйте `-D USE_XXX` вручную.
- Нет доступа к GitHub — положите `config.h` локально и укажите `-c путь`;
  репозиторий betaflight можно заменить зеркалом (`BF_REPO` в скрипте).
- Файлы в `betaflight/obj/` принадлежат вашему пользователю (контейнер запускается
  с `-u $(id -u):$(id -g)`).
