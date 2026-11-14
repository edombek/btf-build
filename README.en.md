# Betaflight firmware builds (2026.6.2) for MicoAir743V2 and other boards

[Русский](README.md) | [English](README.en.md)

The script builds Betaflight firmwares inside the official toolchain docker
image [`betaflight/betaflight-build`](https://hub.docker.com/r/betaflight/betaflight-build)
(which contains exactly `arm-none-eabi-gcc 13.3.1`, required by the Betaflight
2026.6.2 build system). The host only needs **docker**, **git** and **curl**.

| Command | Purpose |
|---|---|
| `./build_generic.sh` | any target: standard board config, custom `config.h` (e.g. MicoAir743V2_EXTMAG) or a base MCU target + any options |

## Quick start

```bash
# MicoAir743V2_EXTMAG (custom MicoAir config), options from the firmware flasher screenshot:
./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
    --radio CRSF --osd Digital --motor DSHOT \
    -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"

# standard board config from betaflight/config:
./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT -f "GPS,VTX,LED Strip"

# base MCU target without a board config:
./build_generic.sh -t STM32H743
```

Result: `dist/betaflight_<version>_<target>.hex` (elf/map — in `betaflight/obj/`).

## How it works

1. `betaflight` is cloned/updated to the requested tag (`-b`, default `2026.6.2`);
   all submodules declared by the repo are initialized on the host
   (`git submodule update --init --recursive`; parallel init inside `make -j`
   races on the git lock file). Platform SDKs marked `update = none` in
   `.gitmodules` (esp-idf, pico-sdk, STM32H5/N6/C5, GD32H7, X32M7, APM32F4)
   are skipped by git by upstream design.
2. For a custom config, `config.h` is downloaded/copied into
   `.build/configs/configs/<NAME>/config.h` and passed to the build via
   `BETAFLIGHT_CONFIG` (in 2026.x board configs live in the separate repo
   [betaflight/config](https://github.com/betaflight/config); the
   `MICOAIR743V2_EXTMAG` target is not there — it is custom, from MicoAir).
3. The build runs in the container:
   `make -j CONFIG=<NAME>|TARGET=<NAME> [OPTIONS="..."] hex`.

## The universal script: `build_generic.sh`

```
./build_generic.sh [options] <config|target>
```

### Build target

| Variant | Example |
|---|---|
| Standard board config (from `betaflight/config`, ~650 boards) | `./build_generic.sh MATEKF405TE` — list: `--list-configs` |
| Custom `config.h` (file, URL or directory) | `-c path/to/config.h`, `-c <URL>`, `-c ./my_configs` (with `configs/<NAME>/config.h` layout); MCU comes from `FC_TARGET_MCU` in config.h |
| Base MCU target | `-t STM32H743` — list: `--list-targets` (33 targets: STM32F4/F7/G4/H7, AT32, APM32, RP2350, ESP32, etc.) |

### Choosing options (same as in the Configurator firmware flasher / build.betaflight.com)

| Parameter | Values |
|---|---|
| `--radio` | CRSF, FPORT, GHOST, IBUS, JETIEXBUS, MAVLINK, PPM, SBUS, SPEKTRUM, SRXL2, SUMD, SUMH, XBUS — several allowed comma-separated (`--radio CRSF,MAVLINK`) |
| `--telemetry` | FRSKY_HUB, HOTT, IBUS_EXTENDED, LTM, MAVLINK, SMARTPORT, SRXL, none (also a list; CRSF/GHOST/FPORT/JETIEXBUS enable telemetry automatically) |
| `--osd` | Analog, Digital, FrSky, none (several allowed) |
| `--motor` | BRUSHED, DSHOT, MULTISHOT, ONESHOT, PROSHOT, PWM |
| `-f, --feat` | the remaining options by their UI names, comma-separated or repeated flag |
| `-D, --define` | arbitrary define bypassing the API (e.g. `USE_EMFAT_TOOLS`) |
| `-v, --verbose` | print option mapping: `# name -> DEFINE`, `# auto: +DEFINE` (silent by default) |
| `--plain` | do not add `CLOUD_BUILD`: options are layered on top of "all by default" |
| `--list-options` | all options of the chosen BF version, live from the API |

Chosen options are translated into defines via the official API
`https://build.betaflight.com/api/options/<version>` and passed as
`make OPTIONS=...` with the `CLOUD_BUILD` prefix (this is how beta's cloud
builds work: exactly the chosen feature set ends up in the firmware; without
option flags you get a plain build with all features by default). Like the
official server, the script automatically adds the "umbrella" defines
(`USE_SERIALRX_*` → `USE_SERIALRX`, `USE_TELEMETRY_*` → `USE_TELEMETRY`,
`USE_RX_PPM` → `USE_PPM`, `USE_GPS` → `USE_ALTITUDE_HOLD/USE_GPS_PLUS_CODES/USE_POSITION_HOLD`,
OSD → `USE_OSD`) — without them some options never reach the firmware (see the
"ELRS / receiver channels" section). For `--radio CRSF/GHOST/FPORT/JETIEXBUS`
telemetry is added automatically (the "Automatically included" row in the UI).

### Other parameters

| Parameter | Description |
|---|---|
| `-b, --bf-version` | Betaflight tag/branch (default `2026.6.2`) |
| `-i, --image` | toolchain docker image (default `betaflight/betaflight-build:arm`; for an image of a specific branch build your own: `git clone https://github.com/betaflight/betaflight-build && cd betaflight-build && ./build-image.sh -r 2026.6.2 arm`) |
| `-n, --name` | custom config name (default: from the `config.h` directory/URL name) |
| `--preview`, `--dry-run` | print the full `docker … make …` command instead of building (checks target and options first) |

**Radio Protocol**

| Option (UI) | define | Note |
|---|---|---|
| CRSF | `USE_SERIALRX_CRSF` | default, telemetry enabled automatically |
| FPORT | `USE_SERIALRX_FPORT` | telemetry enabled automatically |
| GHOST | `USE_SERIALRX_GHST` | telemetry enabled automatically |
| IBUS | `USE_SERIALRX_IBUS` |  |
| JETIEXBUS | `USE_SERIALRX_JETIEXBUS` | telemetry enabled automatically |
| MAVLINK | `USE_SERIALRX_MAVLINK` |  |
| PPM | `USE_RX_PPM` |  |
| SBUS | `USE_SERIALRX_SBUS` |  |
| SPEKTRUM | `USE_SERIALRX_SPEKTRUM` |  |
| SRXL2 | `USE_SERIALRX_SRXL2` |  |
| SUMD | `USE_SERIALRX_SUMD` |  |
| SUMH | `USE_SERIALRX_SUMH` |  |
| XBUS | `USE_SERIALRX_XBUS` |  |

**Telemetry Protocol**

| Option (UI) | define | Note |
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

| Option (UI) | define | Note |
|---|---|---|
| Acro Trainer | `USE_ACRO_TRAINER` | default |
| AKK (SA FIX) | `USE_AKK_SMARTAUDIO` |  |
| Altitude Hold | `USE_ALTITUDE_HOLD` |  |
| Batt. Continue | `USE_BATTERY_CONTINUE` |  |
| Cam. Control | `USE_CAMERA_CONTROL` |  |
| Chirp | `USE_CHIRP` |  |
| Dashboard | `USE_DASHBOARD` |  |
| EMFAT (AutoRun, Icon) | `USE_EMFAT_TOOLS` |  |
| ESC Serial (SK) inc. 4way | `USE_ESCSERIAL_SIMONK` |  |
| Flight Plan | `USE_FLIGHT_PLAN` |  |
| GPS | `USE_GPS` | default |
| LED Strip | `USE_LED_STRIP` | default |
| LED Strip (64) | `USE_LED_STRIP_64` |  |
| Magnetometers | `USE_MAG` |  |
| Optical Flow | `USE_OPTICALFLOW` | default |
| OSD (Analog) | `USE_OSD_SD` | default |
| OSD (Digital) | `USE_OSD_HD` | default |
| OSD (FrSky) | `USE_FRSKYOSD` |  |
| Pin IO | `USE_PINIO` | default |
| Position Hold | `USE_POSITION_HOLD` |  |
| Race Pro | `USE_RACE_PRO` |  |
| Range Finder | `USE_RANGEFINDER` | default |
| Soft Serial | `USE_SOFTSERIAL` |  |
| Servos | `USE_SERVOS` |  |
| VTX | `USE_VTX` | default |
| Wing | `USE_WING` |  |

**Motor Protocol**

| Option (UI) | define | Note |
|---|---|---|
| BRUSHED | `USE_BRUSHED` |  |
| DSHOT | `USE_DSHOT` | default |
| MULTISHOT | `USE_MULTISHOT` |  |
| ONESHOT | `USE_ONESHOT` |  |
| PROSHOT | `USE_PROSHOT` |  |
| PWM | `USE_PWM_OUTPUT` |  |

### Full set of defines

Besides the options listed in the tables (they are the firmware-master
options), any internal Betaflight defines can be passed to `make` via `-D` —
e.g. `USE_USB_CDC_HID`, `USE_RANGEFINDER`, `USE_OPTICALFLOW`, `USE_SOFTSERIAL`,
`USE_DSHOT_BITBANG`, etc. (see `src/main/target/common_pre.h` / `common_post.h`).

## Who adds which flags

Defines in the `make OPTIONS=...` command come from several places; the
Betaflight headers then auto-define and "sweep" more on their own:

| Source | When | What it adds |
|---|---|---|
| Configurator (firmware flasher) | cloud build | only the selected values (`USE_SERIALRX_CRSF`, …) + `CLOUD_BUILD` (or `CORE_BUILD`); no umbrellas or telemetry — `src/composables/useCloudBuild.ts` |
| build.betaflight.com server | `POST /api/builds` | `USE_SERIALRX_* → USE_SERIALRX`; `USE_TELEMETRY_* → USE_TELEMETRY`; `USE_RX_PPM → USE_PPM`; `USE_GPS → USE_ALTITUDE_HOLD + USE_GPS_PLUS_CODES + USE_POSITION_HOLD` (verified via the request echo) |
| `build_generic.sh` | always | `CLOUD_BUILD` (unless `--plain`); API defines for your `--radio/--telemetry/--osd/--motor/-f`; the same auto-completions as the server, plus `USE_OSD` for OSD protocols, plus `USE_TELEMETRY + USE_TELEMETRY_MAVLINK` for `USE_SERIALRX_MAVLINK` |
| Betaflight Makefile | at build time | `OPTIONS="X Y"` → global `-DX -DY` (`Makefile:375`, `mk/preprocess.mk:16`); `CORE_BUILD` — minimal feature set |
| `common_pre.h` | at compile time | without `CLOUD_BUILD` — all-feature defaults (block `:104–319`); regardless of mode: `USE_RX_MSP/USE_RX_MSP_OVERRIDE/USE_RX_RSSI_DBM/USE_RX_RSNR/USE_RX_LINK_UPLINK_POWER` (`:408–412`); chains: `USE_VTX → USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP/TABLE` (`:337`), `USE_SERIALRX_CRSF → USE_CRSF_V3` (+CMS telemetry/link statistics with CRSF telemetry, `:481`), `USE_SERIALRX_MAVLINK → USE_TELEMETRY_MAVLINK` (`:494`), `USE_TELEMETRY_SRXL → USE_SERIALRX_SPEKTRUM + Spektrum VTX control` (`:395`), `USE_GPS+USE_OSD → USE_CMS_GPS_RESCUE_MENU` |
| `common_post.h` | "sweep" | orphan defines are removed: without `USE_SERIALRX` — all `USE_SERIALRX_*` (`:340`), without `USE_TELEMETRY` — all `USE_TELEMETRY_*` (`:354`), without `USE_SERIALRX_CRSF` — `USE_TELEMETRY_CRSF/USE_CRSF_V3` (`:393`); FPORT/IBUS_EXTENDED/JETIEXBUS on the contrary re-add their `USE_TELEMETRY + USE_TELEMETRY_*` (`:368–392`) |
| platform `src/platform/*/target/*/target.h` | per MCU | MCU drivers: STM32H743 — `USE_I2C/USE_SPI/USE_ADC/USE_BEEPER/USE_ESCSERIAL…`, and `USE_SDCARD → USE_SDCARD_SPI + USE_SDCARD_SDIO + ENABLE_SDIO_INIT` (`:71–81`) |
| board `config.h` (betaflight/config or custom) | per board | `USE_SDCARD`, SDIO/UART/I2C pins, `DEFAULT_BLACKBOX_DEVICE`, `VTX_DATA_PIN`, SPI-ELRS pins, etc. |

Practical consequences: `-D` from `OPTIONS` must not duplicate what `target.h`
already defines (`-Werror: redefined`); a "missing" feature usually means a
missing umbrella (`USE_SERIALRX`/`USE_TELEMETRY`) — `common_post.h` swept it out.

## MICOAIR743V2_EXTMAG firmware options (screenshot)

| UI parameter | Define |
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

Notes:

- OSD Digital excludes the analog OSD chip MAX7456 from the firmware (OSD goes
  over MSP DisplayPort — UART2 in the board config). For analog OSD add
  `--osd Analog` or `-f "OSD (Analog)"`.
- GPS (UART3 in the board config) is not in the screenshot set; add it with
  `-f GPS` (GPS Rescue is pulled in automatically).

## MicoAir743V2 FAQ: SD card, VTX, ELRS

### SD card / BlackBox

- The SD card driver is **already in** the firmware: the platform
  `src/platform/STM32/target/STM32H743/target.h` automatically defines
  `USE_SDCARD_SDIO`/`USE_SDCARD_SPI` when the board config has `USE_SDCARD`
  (it does). Passing `-D USE_SDCARD_SDIO` is not needed — it fails with
  `-Werror: "USE_SDCARD_SDIO" redefined`. Verify presence in the firmware:
  `grep sdcardSdio_isFunctional betaflight/obj/main/*.map`.
- Betaflight 2026 **no longer has** the `feature blackbox` switch — logging is
  enabled by the `blackbox_device` parameter (already `sdcard` by default in
  the MicoAir config). If the card "does not work": flash with full chip erase,
  then in the CLI `sdcard_info` (the card should show up),
  `show blackbox_device`, `save`.

### VTX control over UART (SmartAudio/Tramp)

The MicoAir743V2 configs (EXTMAG and INTMAG) have **no VTX control pins**
(`VTX_DATA_PIN`/`VTX_ENABLE_PIN` are undefined). The board targets digital
(HDZero) systems where the VTX is controlled over MSP/DisplayPort — i.e.
"MSP only" is correct for this board and no flags change that.

If an analog VTX with SmartAudio is physically wired to a timer pin of the
board, add `#define VTX_DATA_PIN <pin>` to your `config.h` and build with
`-f VTX`: with `USE_VTX` the `USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP`
drivers are attached automatically (`common_pre.h:337`, outside the
`CLOUD_BUILD` gate).

### ELRS / receiver (RX) channels

Betaflight 2026.6.2 has no flags like `USE_ELRSV4` — neither in the build API
nor in the sources. An external ELRS receiver (any version, including 4.x)
wired to a UART speaks the CRSF protocol: `--radio CRSF`.

**Important `CLOUD_BUILD` nuance:** `USE_SERIALRX_CRSF` alone is not enough —
the umbrella define `USE_SERIALRX` is also required, otherwise `common_post.h:340`
disables all `USE_SERIALRX_*` protocols and the firmware ends up with no UART
receiver at all (the "Receiver mode" tab then shows MSP only). The official
build.betaflight.com adds such auto-defines itself (verified via the
`POST /api/builds` echo) and the script reproduces its rules:

| Selected | Script adds automatically |
|---|---|
| any `USE_SERIALRX_*` (CRSF, SBUS, FPORT, SRXL2, ...) | `USE_SERIALRX` |
| any `USE_TELEMETRY_*` | `USE_TELEMETRY` |
| `USE_SERIALRX_MAVLINK` | `USE_SERIALRX + USE_TELEMETRY + USE_TELEMETRY_MAVLINK` |
| `USE_RX_PPM` | `USE_PPM` |
| `USE_GPS` | `USE_ALTITUDE_HOLD`, `USE_GPS_PLUS_CODES`, `USE_POSITION_HOLD` |
| OSD `USE_OSD_SD/HD` / `USE_FRSKYOSD` | `USE_OSD` |

(with `-v` the additions show up as `# auto: +USE_SERIALRX`; `USE_CRSF_V3` is
enabled by the Makefile itself — `common_pre.h:481`). For the **MAVLINK** radio
the script adds `USE_TELEMETRY + USE_TELEMETRY_MAVLINK` a bit beyond the
official server: per sources "SERIALRX_MAVLINK provider can not work without
TELEMETRY_MAVLINK" (`common_pre.h:494` auto-defines it), but without the
`USE_TELEMETRY` umbrella `common_post.h:354` wipes that define out — so the
script passes both explicitly (in a cloud build the same result comes from the
`common_pre.h` auto-define when telemetry is already enabled by another
protocol). To verify UART-RX in the built firmware:
`arm-none-eabi-nm obj/main/*.elf | grep -i crsf` — expect `crsfDataReceive`,
`crsfChannelData`, etc. Firmwares built before this rule was added contained
no CRSF receiver — reflash.

In the "Ports" tab the receiver UART must have the **Serial RX** function
(receiver TX → board RX); in the "Receiver" tab the protocol is **CRSF**; the
`RX_SERIAL` feature is enabled by default (`DEFAULT_RX_FEATURE`, `feature.h:31`).

If channels are delivered over MSP (e.g. a digital video system receiver —
HDZero/Walksnail), it uses `USE_RX_MSP` + `USE_RX_MSP_OVERRIDE` — they are
defined in `common_pre.h:408` **outside the `CLOUD_BUILD` gate**, i.e. present
in every build; nothing extra to compile. In the CLI: `feature RX_MSP`.

The `USE_RX_EXPRESSLRS` flag exists only for boards with an onboard SPI ELRS
module and requires extra pins (`RX_EXPRESSLRS_SPI_RESET_PIN`,
`RX_EXPRESSLRS_SPI_BUSY_PIN`, `RX_SPI_CS`, ...) in the board config —
MicoAir743V2 has no onboard receiver.

## Verified builds (Betaflight 2026.6.2)

| Target | Result |
|---|---|
| `MICOAIR743V2_EXTMAG` (custom MicoAir config, screenshot options) | hex 1.2 MB, FLASH ~430 KB (24 %), RAM 15.3 % — the elf confirms CRSF-RX (`crsfDataReceive`), telemetry, OSD HD, DSHOT, alt-hold, chirp, dashboard, pinio, ledstrip; no GPS, no MAX7456 |
| `MICOAIR743V2` (standard config + GPS, VTX; GPS auto-pulls alt-hold/poshold) | FLASH1 490 KB (26.7 %) |
| `-t STM32H743 --motor DSHOT` (CLOUD_BUILD, minimal) | FLASH1 276 KB |

## Flashing the built firmware

1. Connect the FC in DFU (hold BOOT0 while powering up) or via Configurator.
2. **Betaflight Configurator 10.13+**: Firmware Flasher → "Load firmware (hex)"
   → file from `dist/` → Flash ("Full chip erase" when changing versions).

   From the command line:
   ```bash
   arm-none-eabi-objcopy -I ihex -O binary dist/<file>.hex firmware.bin
   st-flash --reset write firmware.bin 0x08000000
   ```

## Troubleshooting

- `build API does not know version ...` — old releases (4.5 etc.) have no
  options API: use `-D USE_XXX` manually.
- No GitHub access — put `config.h` locally and pass `-c path`; the betaflight
  repository can be replaced with a mirror (`BF_REPO` in the script).
- Files in `betaflight/obj/` are owned by your user (the container runs with
  `-u $(id -u):$(id -g)`).
