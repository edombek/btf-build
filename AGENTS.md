# AGENTS.md — guidance for automated agents working in this repo

## What this repository is

This repository contains **one build script** (`build_generic.sh`) for
[Betaflight](https://github.com/betaflight/betaflight) firmware and its
documentation (`README.md` in Russian, `README.en.md` in English). These are
**not** Betaflight sources: the Betaflight tree is cloned by the script into
`betaflight/` at run time and is not kept in git.

The goal of the project is reproducible Betaflight firmware builds without any
manually installed toolchain: compilation happens inside the official docker
image `betaflight/betaflight-build`.

## Layout

```
build_generic.sh   # the only executable script — all build logic
README.md          # user docs (Russian) + full option tables
README.en.md       # user docs (English), cross-linked with README.md
AGENTS.md          # this file (English only)
# created at run time and NOT committed (see .gitignore):
betaflight/        # Betaflight clone (tag/branch from -b)
.build/            # build API options cache + custom config.h staging
dist/              # finished .hex files
```

## How the build works (key details)

1. `ensure_sources` — `git clone --depth 1 --branch <BF_VERSION>`, or
   `fetch` + `checkout` for an existing clone. Default version: `2026.6.2`.
2. `ensure_submodules` — initializes **all** repo submodules
   (`git submodule update --init --recursive`) **sequentially on the host**.
   ⚠️ Do not move this into `make -j` inside the container: concurrent
   `git submodule update --init` calls race on the `.git/config` lock file
   (`could not lock config file .git/config: File exists`), which makes the
   build fail on a fresh clone. `.gitmodules` has 10 entries, but 8 platform
   SDKs (esp-idf, pico-sdk, STM32H5/N6/C5, GD32H7, X32M7, APM32F4) are marked
   `update = none` and git deliberately skips them ("Skipping sub-module …"
   in the log is normal); what actually initializes is `src/config` (board
   configs) and `libcanard` (+ nested `avr-can-lib`).
3. Target mode selection (`set -e` must not kill the script on empty checks —
   use `if`, never top-level `cmd && action`):
   - `-t/--target <NAME>` → `make TARGET=<NAME>` — base MCU target; names come
     from `src/platform/*/target/*/target.mk` (`base_targets`);
   - `-c/--config <file|URL|dir>` → custom config: `config.h` is placed into
     `.build/configs/configs/<NAME>/config.h`, the directory is mounted into
     the container as `/configs` and passed via `-e BETAFLIGHT_CONFIG=/configs`.
     Config name comes from `-n`, otherwise from the directory wrapping
     `config.h` / from the URL. The MCU is derived from `FC_TARGET_MCU` inside
     `config.h` (the Betaflight Makefile does this);
   - otherwise — standard config from the `src/config` submodule
     (`configs/<NAME>/config.h` or `configs/<MANUFACTURER>/<NAME>/config.h`).
4. Firmware-master options are converted into make defines by the python block
   reading the JSON from `fetch_options` (`build.betaflight.com/api/options/<version>`)
   — result: `make [OPTIONS="..."] hex`.

### Mandatory option semantics

- Whenever any option is given, `CLOUD_BUILD` is prepended (same as Betaflight
  cloud builds) — otherwise `common_pre.h` enables **all** features by default
  and the firmware is different. `--plain` disables `CLOUD_BUILD`.
- **Umbrella defines:** a `CLOUD_BUILD` build must pass `USE_SERIALRX` for any
  `USE_SERIALRX_*` protocol — otherwise `common_post.h:340` `#undef`s every
  serial RX protocol and the firmware has no UART receiver (the Configurator
  "Receiver mode" tab then offers MSP only). The official build.betaflight.com
  server auto-completes the set (verified via `POST /api/builds` echo):
  `USE_SERIALRX_* → USE_SERIALRX`; `USE_TELEMETRY_* → USE_TELEMETRY`;
  `USE_RX_PPM → USE_PPM`; `USE_GPS → USE_ALTITUDE_HOLD + USE_GPS_PLUS_CODES +
  USE_POSITION_HOLD`; OSD protocols → `USE_OSD`. The script reproduces this in
  the `OPT_LIST` normalization (`# auto: +...` lines, printed with `-v`).
  The script additionally sends `USE_TELEMETRY + USE_TELEMETRY_MAVLINK` for
  `USE_SERIALRX_MAVLINK` (the build server does not): per sources
  "SERIALRX_MAVLINK provider can not work without TELEMETRY_MAVLINK"
  (`common_pre.h:494` auto-defines it), but `common_post.h:354` sweeps it out
  when the `USE_TELEMETRY` umbrella is absent. Keep the `USE_SERIALRX_MAVLINK`
  case branch **before** the generic `USE_SERIALRX_*` one in the expansion
  loop, and remember it must add `USE_SERIALRX` as well.
- Radio protocols with `includesTelemetry: true` automatically add
  `USE_TELEMETRY` + the concrete `USE_TELEMETRY_*` (CRSF→CRSF, FPORT→SMARTPORT,
  GHOST→GHST, JETIEXBUS→JETIEXBUS).
- OSD options (`USE_OSD_SD` / `USE_OSD_HD` / `USE_FRSKYOSD`) must pull
  `USE_OSD` explicitly.
- Full option names, defines and the `default`/`includesTelemetry` flags come
  **only** from the build API response — never keep a private list of "magic"
  names; when they differ, the API wins.
- OSD `Digital` excludes the analog `MAX7456` chip — that is Betaflight Makefile
  behavior, do not duplicate it in the script.
- Old Betaflight versions (before 2025.12) have no options API: `fetch_options`
  exits with a hint to use `-D USE_XXX`.
- `--radio/--telemetry/--osd/--motor` accept comma-separated lists (they fill
  `RADIOS/TELEMETRIES/OSDS/MOTORS` arrays; each element becomes a separate
  `MAP_SEL` token, dedup happens in the python block).

### Important facts about the build environment

- Betaflight 2026.6.2 requires **exactly** `arm-none-eabi-gcc 13.3.1`
  (`GCC_REQUIRED_VERSION` in `mk/tools.mk`). The host compiler won't do; the
  toolchain lives inside the docker image (`TOOLS_DIR=/opt/betaflight/tools`).
  Do not add host toolchain detection/installation.
- Binutils (`arm-none-eabi-nm/objdump/size`) are inside the image but **not in
  PATH** — use the full path `/opt/betaflight/tools/arm-gnu-toolchain-13.3.rel1-x86_64-arm-none-eabi/bin/…`.
- The container runs with `-u "$(id -u):$(id -g)"` so that artifacts under
  `betaflight/obj` belong to the user. The image already configures
  `safe.directory`.
- `-c` also accepts ready-made root directories with `configs/...` layout (e.g.
  a user's own `BETAFLIGHT_CONFIG`) — do not break that scenario.
- Custom configs exist because not every board is in `betaflight/config`
  (e.g. MicoAir's `MICOAIR743V2_EXTMAG`).
- Never pass `-D USE_SDCARD_SDIO`: for STM32H743 the platform
  `src/platform/STM32/target/STM32H743/target.h` (:71–81) already defines it
  when `USE_SDCARD` is set, and `-Werror` fails with "redefined".
- Betaflight 2026 has no `FEATURE_BLACKBOX` — logging is enabled by the
  `blackbox_device` parameter (default from `DEFAULT_BLACKBOX_DEVICE` in the
  board config). There are also no flags like `USE_ELRSV4`: ELRS works via
  `USE_SERIALRX_CRSF` (+ automatic `USE_CRSF_V3`, `common_pre.h:481`).
- With `USE_VTX` the drivers `USE_VTX_COMMON/CONTROL/SMARTAUDIO/TRAMP/MSP/TABLE`
  are attached at `common_pre.h:337` — that block is **outside** the
  `CLOUD_BUILD` gate, so `-f VTX` is enough (provided `VTX_DATA_PIN` in the config).
- Verifying "did the feature make it into the firmware" via `nm` on `.o` files
  does not work (LTO) — look at symbols in the `*.map` / final `.elf`
  (e.g. `sdcardSdio_isFunctional`). Static functions (e.g. `crsfRxInit`) may
  have no symbol at all — LTO internalizes/inlines them; look for **other**
  symbols of the feature (for CRSF RX: `crsfDataReceive`, `crsfChannelData`).
  `LOAD .../<file>.o` lines in the map are NOT proof: a file entirely disabled
  by `#ifdef` still produces a LOAD line for its empty object.
  `serialRxBytesWaiting` is a generic `io/serial.c` function, always present,
  it says nothing about RX protocols.
- `USE_RX_MSP`/`USE_RX_MSP_OVERRIDE` (+ RSSI_DBM/RSNR/link quality) are defined
  at `common_pre.h:408–412` **outside** the `CLOUD_BUILD` gate — MSP-RX (RC
  channels over MSP from HDZero/Walksnail etc.) is in every build, no flag
  needed. The "all features by default" block in `common_pre.h` is
  `#if !defined(CLOUD_BUILD)` (lines 104–319); outside it there are only
  conditional auto-dependencies (CRSF v3 and friends).
- `common_post.h` sweeps orphan defines: without `USE_SERIALRX` all
  `USE_SERIALRX_*` (:340), without `USE_TELEMETRY` all `USE_TELEMETRY_*`
  (:354), without `USE_SERIALRX_CRSF` — CRSF telemetry/`USE_CRSF_V3` (:393);
  FPORT/IBUS_EXTENDED/JETIEXBUS re-add their telemetry (:368–392), ELRS forces
  CRSF telemetry (:773–776).

## How to verify changes

Before committing:

```bash
bash -n build_generic.sh                     # syntax
./build_generic.sh --help >/dev/null         # usage
./build_generic.sh --list-options | head     # options mapping
./build_generic.sh --list-configs | head     # standard board configs
./build_generic.sh --list-targets | head     # base MCU targets
./build_generic.sh MICOAIR743V2EXTMAG        # negative case: similar-name hints
./build_generic.sh MICOAIR743V2 --radio CRSF --feat "Foo Bar"   # negative option case
./build_generic.sh -t STM32H743 --radio CRSF,MAVLINK --preview  # radio list + command preview
./build_generic.sh -t STM32H743 --radio MAVLINK -v --preview    # MAVLINK auto-telemetry defines + mapping notes
```

Full check (a few minutes, needs docker and network):

```bash
# custom config.h (MicoAir743V2_EXTMAG)
./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
    --radio CRSF --osd Digital --motor DSHOT \
    -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"
# standard board config
./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT -f "GPS,VTX,LED Strip"
# base MCU target
./build_generic.sh -t STM32H743 --motor DSHOT
```

Expected success markers: `Creating HEX ./obj/betaflight_<version>_<target>.hex`
and the `==> Done:` line. The hex MD5 is **not** an identity check: Betaflight
embeds the build date into `version.o`, so hashes differ even for the same set
of options. To check equivalence compare the `==> Options:` line and usage
lines from the `map` file.

## Conventions

- Bash: `set -euo pipefail`; `if`/`fi` instead of top-level `cmd && action`;
  `${arr[@]+"${arr[@]}"}` for possibly-empty arrays; `[[ ]]` only for patterns.
- The script is self-contained: one file, no external dependencies beyond
  `docker`/`git`/`curl`/`python3` on the host. Do not introduce package builds
  or installations.
- Script user-facing text (usage, errors, log lines) is **English**.
  Documentation is bilingual: `README.md` (Russian) + `README.en.md` (English),
  cross-linked at the top of both; `AGENTS.md` is English only. When you change
  user-visible behavior, update both READMEs.
- Do not redirect build logs to a file (except logs already adopted in the
  script) — the user needs live `make` output.
- Changes to option rules must be accompanied by updates to the tables in both
  READMEs (the full option list is generated from `--list-options`).

## What not to do

- Do not commit `betaflight/`, `dist/`, `.build/`, `*.hex`, `*.elf`, `*.map`,
  Configurator CLI dumps (`*cli_backup*`) or any firmware.
- Do not replace the docker image with a host toolchain install, and do not
  bump/downgrade the GCC version bypassing the image.
- Do not store secrets/tokens; GitHub access goes through `gh`/SSH.
- Do not rewrite the script around one specific board — do not spawn private
  variants like `build_micoair743v2_extmag.sh`: they are reproduced with a
  single `build_generic.sh` command (example in the READMEs).

## Useful external references

- Build API options: `https://build.betaflight.com/api/options/<version>`
  (builds: `POST https://build.betaflight.com/api/builds`, the echo shows the
  server-side auto-defines)
- Board configs: https://github.com/betaflight/config
- Toolchain docker images: https://github.com/betaflight/betaflight-build
- Betaflight build system: `Makefile`, `mk/config.mk`, `mk/tools.mk`,
  `src/main/target/common_pre.h`, `src/main/target/common_post.h`,
  `src/main/msp/msp_build_info.h`
