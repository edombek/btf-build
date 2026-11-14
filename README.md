# Сборка прошивок Betaflight (2026.6.2) для MicoAir743V2 и других плат

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
   submodule'ы (`src/config` с конфигами плат, `libcanard`) инициализируются на хосте
   последовательно (параллельная инициализация внутри `make -j` конфликтует на lock-файле git).
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
| `--radio` | CRSF, FPORT, GHOST, IBUS, JETIEXBUS, MAVLINK, PPM, SBUS, SPEKTRUM, SRXL2, SUMD, SUMH, XBUS |
| `--telemetry` | FRSKY_HUB, HOTT, IBUS_EXTENDED, LTM, MAVLINK, SMARTPORT, SRXL, none (CRSF/GHOST/FPORT/JETIEXBUS включают телеметрию автоматически) |
| `--osd` | Analog, Digital, FrSky, none |
| `--motor` | BRUSHED, DSHOT, MULTISHOT, ONESHOT, PROSHOT, PWM |
| `-f, --feat` | остальные опции именами из UI, через запятую или параметром повторно |
| `-D, --define` | произвольный define мимо API (например `USE_EMFAT_TOOLS`) |
| `--plain` | не добавлять `CLOUD_BUILD`: опции накладываются поверх «всех по умолчанию» |
| `--list-options` | все опции выбранной версии BF живьём из API |

Выбранные опции транслируются в defines по официальному API
`https://build.betaflight.com/api/options/<версия>` и передаются в `make OPTIONS=...`
с префиксом `CLOUD_BUILD` (так же работает облачная сборка беты: в прошивку попадает
ровно выбранный набор; без флагов опций собирается plain-сборка со всеми фичами по умолчанию).
Для `--radio CRSF/GHOST/FPORT/JETIEXBUS` телеметрия добавляется автоматически
(строка «Automatically included» в UI).

### Прочие параметры

| Параметр | Описание |
|---|---|
| `-b, --bf-version` | тег/ветка Betaflight (дефолт `2026.6.2`) |
| `-i, --image` | docker-образ тулчейна (дефолт `betaflight/betaflight-build:arm`; если нужен образ конкретной ветки — собрать самому: `git clone https://github.com/betaflight/betaflight-build && cd betaflight-build && ./build-image.sh -r 2026.6.2 arm`) |
| `-n, --name` | имя кастомного конфига (по умолчанию из имени каталога/URL `config.h`) |

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

## Проверенные сборки (Betaflight 2026.6.2)

| Цель | Результат |
|---|---|
| `MICOAIR743V2_EXTMAG` (кастомный конфиг MicoAir, опции со скриншота) | hex 1,2 МБ, FLASH1 421 КБ (23,3 %), RAM 15,3 % — в map подтверждены CRSF+телеметрия, OSD HD, DSHOT, alt-hold, chirp, dashboard, pinio, ledstrip; нет GPS и MAX7456 |
| `MICOAIR743V2` (стандартный конфиг + GPS, VTX) | FLASH1 467 КБ (25,4 %) |
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
