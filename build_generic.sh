#!/usr/bin/env bash
#
# build_generic.sh — универсальная сборка прошивок Betaflight в официальном
# docker-образе тулчейна (betaflight/betaflight-build).
#
# Поддерживает:
#   * стандартные конфиги плат из betaflight/config (MATEKF405TE, MICOAIR743V2, ...)
#   * кастомные конфиги: config.h файлом, URL или каталогом с configs/<ИМЯ>/config.h
#     (например MicoAir743V2_EXTMAG из https://github.com/micoair/MicoAir743v2)
#   * базовые MCU-таргеты без конфига платы (STM32H743, STM32F405, ...)
#
# Опции задаются «человеческими» именами как в мастере прошивки Configurator
# (--radio/--telemetry/--osd/--motor/--feat) и транслируются в defines по
# официальному API https://build.betaflight.com/api/options/<version>
#
set -euo pipefail

DEFAULT_BF_VERSION="2026.6.2"
BF_VERSION="$DEFAULT_BF_VERSION"
BF_REPO="https://github.com/betaflight/betaflight"
IMAGE="betaflight/betaflight-build:arm"
BUILD_API="https://build.betaflight.com"

usage() {
cat <<'EOF'
Использование:
  ./build_generic.sh [параметры] <конфиг|таргет>

Цель сборки:
  <ИМЯ>                    стандартный конфиг платы из betaflight/config
                           (MATEKF405TE, MICOAIR743V2, ...); см. --list-configs.
                           Со --config — имя кастомного конфига.
  -t, --target <ИМЯ>       базовый MCU-таргет без конфига платы (STM32H743,
                           STM32F405, AT32F435G, ...); см. --list-targets
  -c, --config <Файл|URL|Каталог>
                           кастомный config.h: файл, URL на него, каталог config.h
                           или каталог-корень с layouts configs/<ИМЯ>/config.h.
                           MCU берётся из FC_TARGET_MCU внутри config.h.
  -n, --name <ИМЯ>         имя кастомного конфига (по умолчанию — имя каталога
                           вокруг config.h или имя из URL)

Параметры:
  -b, --bf-version <ВЕР>   версия Betaflight: тег/ветка (дефолт: 2026.6.2)
  -i, --image <ОБРАЗ>      docker-образ тулчейна (дефолт: betaflight/betaflight-build:arm)
  --radio <ПРОТОКОЛ>       CRSF | FPORT | GHOST | IBUS | JETIEXBUS | MAVLINK | PPM |
                           SBUS | SPEKTRUM | SRXL2 | SUMD | SUMH | XBUS
  --telemetry <ПРОТОКОЛ>   FRSKY_HUB | HOTT | IBUS_EXTENDED | LTM | MAVLINK |
                           SMARTPORT | SRXL | none
                           (CRSF/GHOST/FPORT/JETIEXBUS включают телеметрию сами)
  --osd <ТИП>              Analog | Digital | FrSky | none
  --motor <ПРОТОКОЛ>       BRUSHED | DSHOT | MULTISHOT | ONESHOT | PROSHOT | PWM
  -f, --feat <СПИСОК>      доп. опции (через запятую или параметром повторно), имена
                           как в UI мастера: "Altitude Hold", "Batt. Continue",
                           "Dashboard", "LED Strip", "Pin IO", "Chirp", GPS, VTX...
                           Полный список всех возможных: --list-options
  -D, --define <DEFINE>    произвольный define, минуя API (повторяемо),
                           напр. USE_EMFAT_TOOLS, USE_USB_CDC_HID
  --plain                  не добавлять CLOUD_BUILD: выбранные опции накладываются
                           поверх «всех по умолчанию» (plain-режим make)
  --list-options           полный список всех опций выбранной версии BF (из API)
  --list-configs           список стандартных конфигов плат
  --list-targets           список базовых MCU-таргетов
  -h, --help               эта справка

Примеры:
  # стандартный конфиг MicoAir743V2 из betaflight/config
  ./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT \
      -f "GPS,VTX,LED Strip"

  # кастомный config.h MicoAir — версия с внешним магнитометром (MICOAIR743V2_EXTMAG)
  ./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
      --radio CRSF --osd Digital --motor DSHOT \
      -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"

  # базовый таргет STM32H743 (все фичи по умолчанию, без конфига платы)
  ./build_generic.sh -t STM32H743

Результат: dist/betaflight_<версия>_<цель>.hex (elf/map — в betaflight/obj/)
EOF
}

# ------------------------------ разбор аргументов -----------------------------
declare -a FEATS=() DEFINES=()
CONFIG_SRC="" NAME_ARG="" TARGET_ARG=""
RADIO="" TELEMETRY="" OSD="" MOTOR=""
TARGET_MODE=0 PLAIN=0 LIST_OPTS=0 LIST_CFG=0 LIST_TGT=0

while (($#)); do
    case "$1" in
        -b|--bf-version) BF_VERSION="$2"; shift 2;;
        -i|--image)      IMAGE="$2"; shift 2;;
        -c|--config)     CONFIG_SRC="$2"; shift 2;;
        -n|--name)       NAME_ARG="$2"; shift 2;;
        -t|--target)     TARGET_ARG="$2"; shift 2;;
        -f|--feat)       IFS=',' read -ra _p <<<"$2"; FEATS+=("${_p[@]}"); shift 2;;
        -D|--define)     DEFINES+=("$2"); shift 2;;
        --radio)         RADIO="$2"; shift 2;;
        --telemetry)     TELEMETRY="$2"; shift 2;;
        --osd)           OSD="$2"; shift 2;;
        --motor)         MOTOR="$2"; shift 2;;
        --plain)         PLAIN=1; shift;;
        --list-options)  LIST_OPTS=1; shift;;
        --list-configs)  LIST_CFG=1; shift;;
        --list-targets)  LIST_TGT=1; shift;;
        -h|--help)       usage; exit 0;;
        -*)              echo "Неизвестный параметр: $1" >&2; usage >&2; exit 1;;
        *)               NAME_ARG="$1"; shift;;
    esac
done

cd "$(dirname "$0")"
mkdir -p .build
OPT_JSON=".build/options-${BF_VERSION}.json"

fetch_options() {
    if [ ! -s "$OPT_JSON" ]; then
        curl -fsSL --retry 3 -o "$OPT_JSON" "$BUILD_API/api/options/${BF_VERSION}" \
            || { rm -f "$OPT_JSON"
                 echo "Ошибка: build API не знает версию '${BF_VERSION}'. Опции задавайте через -D USE_XXX" >&2
                 exit 1; }
    fi
}

ensure_sources() {
    if [ -d betaflight/.git ]; then
        git -C betaflight fetch -q --depth 1 origin "refs/tags/${BF_VERSION}:refs/tags/${BF_VERSION}" 2>/dev/null || \
            git -C betaflight fetch -q --depth 1 origin "refs/heads/${BF_VERSION}:refs/remotes/origin/${BF_VERSION}" || true
        git -C betaflight checkout -q "$BF_VERSION" 2>/dev/null || \
            git -C betaflight checkout -q "refs/remotes/origin/${BF_VERSION}"
    else
        git clone -q --depth 1 --branch "$BF_VERSION" "$BF_REPO" betaflight
    fi
}

ensure_submodules() {
    # последовательно: параллельные git submodule update конфликтуют на .git/config
    git -C betaflight submodule update --init -- src/config lib/modules/dronecan/libcanard
}

base_targets() {
    find betaflight/src/platform/*/target -mindepth 2 -maxdepth 2 -name target.mk \
        | awk -F/ '{print $(NF-1)}' | sort -u
}

# ------------------------------- list-режимы ----------------------------------
if ((LIST_OPTS)); then
    fetch_options
    python3 - "$OPT_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for sec, title in (("radioProtocols", "Radio Protocol"),
                   ("telemetryProtocols", "Telemetry Protocol"),
                   ("generalOptions", "General Options"),
                   ("motorProtocols", "Motor Protocol")):
    print(f"\n== {title} ==")
    for it in d[sec]:
        flags = []
        if it.get("default"): flags.append("default")
        if it.get("includesTelemetry"): flags.append("+telemetry")
        name = it["name"]
        if it.get("group") and it.get("groupedName"):
            name = f"{it['group']} [{it['groupedName']}]"
        print(f"  {name:28s} {it['value'] or '(нет)':26s} {', '.join(flags)}")
PY
    exit 0
fi

if ((LIST_CFG)); then
    ensure_sources; ensure_submodules
    find betaflight/src/config/configs -mindepth 2 -maxdepth 3 -name config.h \
        | awk -F/ '{print $(NF-1)}' | sort
    exit 0
fi

if ((LIST_TGT)); then
    ensure_sources
    base_targets
    exit 0
fi

# --------------------------- выбор режима сборки ------------------------------
if [ -n "$TARGET_ARG" ]; then
    TARGET_MODE=1
    NAME_ARG="$TARGET_ARG"
fi

CUSTOM_ROOT=""   # каталог, передаваемый в контейнер как BETAFLIGHT_CONFIG
BUILD_NAME="$NAME_ARG"

if [ -n "$CONFIG_SRC" ]; then
    if [ -z "$BUILD_NAME" ]; then
        src="${CONFIG_SRC%/}"; src="${src%%\?*}"
        case "$src" in
            */config.h) BUILD_NAME="$(basename "$(dirname "$src")")";;
            *)          BUILD_NAME="$(basename "$src")";;
        esac
    fi
    if [ -d "$CONFIG_SRC" ] && [ -d "$CONFIG_SRC/configs" ]; then
        # готовый каталог CONFIG_DIR: configs/<ИМЯ>/config.h или configs/<MFR>/<ИМЯ>/config.h
        CUSTOM_ROOT="$(realpath "$CONFIG_SRC")"
        cfgs="$(find "$CUSTOM_ROOT/configs" -mindepth 2 -maxdepth 3 -name config.h)"
        if [ -z "$cfgs" ]; then
            echo "Ошибка: в '$CUSTOM_ROOT/configs' нет ни одного config.h" >&2; exit 1
        fi
        if [ "$(echo "$cfgs" | wc -l)" -eq 1 ] && [ -z "$NAME_ARG" ]; then
            BUILD_NAME="$(basename "$(dirname "$cfgs")")"
        fi
    else
        file=""
        if [ -d "$CONFIG_SRC" ] && [ -f "$CONFIG_SRC/config.h" ]; then
            file="$CONFIG_SRC/config.h"
        elif [ -f "$CONFIG_SRC" ]; then
            file="$CONFIG_SRC"
        elif [[ "$CONFIG_SRC" != http* ]]; then
            echo "Ошибка: config.h не найден: $CONFIG_SRC" >&2; exit 1
        fi
        CUSTOM_ROOT="$(pwd)/.build/configs"
        mkdir -p "$CUSTOM_ROOT/configs/$BUILD_NAME"
        if [ -n "$file" ]; then
            cp "$file" "$CUSTOM_ROOT/configs/$BUILD_NAME/config.h"
        else
            curl -fL --retry 3 -o "$CUSTOM_ROOT/configs/$BUILD_NAME/config.h" "$CONFIG_SRC"
        fi
    fi
elif [ -z "$BUILD_NAME" ]; then
    usage >&2
    exit 1
fi

if ((TARGET_MODE)); then
    if [ -n "$CONFIG_SRC" ]; then
        echo "Ошибка: --target не сочетается с --config" >&2; exit 1
    fi
    ensure_sources
    if ! base_targets | grep -qx "$BUILD_NAME"; then
        echo "Ошибка: '$BUILD_NAME' нет среди базовых таргетов. Похожие:" >&2
        base_targets | grep -i -- "$(echo "$BUILD_NAME" | cut -c1-6)" | head -10 >&2 || true
        exit 1
    fi
    MAKE_VARIANT=("TARGET=$BUILD_NAME")
elif [ -n "$CUSTOM_ROOT" ]; then
    MAKE_VARIANT=("CONFIG=$BUILD_NAME")
else
    ensure_sources
    ensure_submodules
    found="$(find betaflight/src/config/configs -mindepth 2 -maxdepth 3 -type d \
                 -name "$BUILD_NAME" -exec test -e '{}/config.h' ';' -print -quit)"
    if [ -z "$found" ]; then
        echo "Ошибка: конфиг '$BUILD_NAME' не найден в betaflight/config. Похожие:" >&2
        find betaflight/src/config/configs -mindepth 2 -maxdepth 3 -name config.h \
            | awk -F/ '{print $(NF-1)}' | grep -i -- "$(echo "$BUILD_NAME" | cut -c1-6)" | head -10 >&2 || true
        echo "(кастомный конфиг — параметр -c/--config)" >&2
        exit 1
    fi
    MAKE_VARIANT=("CONFIG=$BUILD_NAME")
fi

# ------------------------- опции -> defines (через API) -----------------------
declare -a MAP_SEL=()
if [ -n "$RADIO" ]; then MAP_SEL+=("radio	$RADIO"); fi
if [ -n "$TELEMETRY" ]; then MAP_SEL+=("telemetry	$TELEMETRY"); fi
if [ -n "$OSD" ]; then MAP_SEL+=("osd	$OSD"); fi
if [ -n "$MOTOR" ]; then MAP_SEL+=("motor	$MOTOR"); fi
for f in "${FEATS[@]+"${FEATS[@]}"}"; do MAP_SEL+=("general	$f"); done
# не роняем скрипт из-за set -e, если последний [ -n ] был пустым
HAVE_OPTS=0
if ((${#MAP_SEL[@]} || ${#DEFINES[@]})); then HAVE_OPTS=1; fi

OPTIONS=""
if ((HAVE_OPTS)); then
    fetch_options
    DEFS="$(python3 - "$OPT_JSON" "${MAP_SEL[@]+"${MAP_SEL[@]}"}" <<'PY'
import json, sys

path = sys.argv[1]
tokens = [t.split("\t", 1) for t in sys.argv[2:]]
d = json.load(open(path))
sections = [("radio", d["radioProtocols"]),
            ("telemetry", d["telemetryProtocols"]),
            ("general", d["generalOptions"]),
            ("motor", d["motorProtocols"])]

# телеметрия, автоматически включаемая вместе с радио-протоколом
radio_telemetry = {"USE_SERIALRX_CRSF": "USE_TELEMETRY_CRSF",
                   "USE_SERIALRX_FPORT": "USE_TELEMETRY_SMARTPORT",
                   "USE_SERIALRX_GHST": "USE_TELEMETRY_GHST",
                   "USE_SERIALRX_JETIEXBUS": "USE_TELEMETRY_JETIEXBUS"}

def lookup(sec_wanted, tok):
    t = tok.strip().lower()
    cands = []
    for sec, items in sections:
        for it in items:
            if not it.get("value"):
                continue
            is_osd = it.get("group") == "OSD"
            if sec_wanted != "general":
                if sec_wanted == "osd" and not is_osd:
                    continue
                if sec_wanted != "osd" and sec != sec_wanted:
                    continue
            name = it["name"].lower()
            grouped = (it.get("groupedName") or "").lower()
            val = it["value"].lower()
            if t == name or t == val or (grouped and t == grouped):
                cands.append((sec, it))
    if not cands:
        return None
    if len(cands) > 1:
        strict = [c for c in cands
                  if c[1]["name"].lower() == t or c[1]["value"].lower() == t]
        if len(strict) == 1:
            cands = strict
    if len(cands) > 1:
        print("Неоднозначно: '%s': %s" % (tok, "; ".join(
            f"{c[1]['name']}={c[1]['value']}" for c in cands)), file=sys.stderr)
        sys.exit(2)
    return cands[0]

defines, notes = [], []
for sec_wanted, tok in tokens:
    if tok.strip().lower() in ("none", "нет", ""):
        continue
    hit = lookup(sec_wanted, tok)
    if hit is None:
        print(f"Неизвестная опция: '{tok}' (секция {sec_wanted}). "
              f"Полный список: --list-options", file=sys.stderr)
        sys.exit(2)
    sec, it = hit
    defines.append(it["value"])
    notes.append(f"{it['name']} -> {it['value']}")
    if it["value"] in ("USE_OSD_SD", "USE_OSD_HD", "USE_FRSKYOSD"):
        defines.append("USE_OSD")
    if sec == "radio" and it.get("includesTelemetry"):
        defines.append("USE_TELEMETRY")
        extra = radio_telemetry.get(it["value"])
        if extra:
            defines.append(extra)
            notes.append(f"авто-телеметрия: {it['name']} -> {extra}")
    if sec == "telemetry" and it["value"]:
        defines.append("USE_TELEMETRY")

seen, out = set(), []
for x in defines:
    if x not in seen:
        seen.add(x)
        out.append(x)
for n in notes:
    print("  # " + n, file=sys.stderr)
print(" ".join(out))
PY
)"
    declare -a OPT_LIST=()
    if [ "$PLAIN" -eq 0 ]; then OPT_LIST+=("CLOUD_BUILD"); fi
    read -ra _d <<<"$DEFS"
    OPT_LIST+=("${_d[@]}")
    for u in "${DEFINES[@]+"${DEFINES[@]}"}"; do OPT_LIST+=("$u"); done
    OPTIONS="${OPT_LIST[*]}"
fi

# ------------------------------ сборка (docker) -------------------------------
ensure_sources
ensure_submodules

DOCKER_ARGS=(run --rm -u "$(id -u):$(id -g)" -v "$(pwd)/betaflight":/src)
if [ -n "$CUSTOM_ROOT" ]; then
    DOCKER_ARGS+=(-v "$CUSTOM_ROOT":/configs -e "BETAFLIGHT_CONFIG=/configs")
fi
MAKE_ARGS=(-j)
if [ -n "$OPTIONS" ]; then MAKE_ARGS+=("OPTIONS=$OPTIONS"); fi
MAKE_ARGS+=("${MAKE_VARIANT[@]}" hex)

echo "==> Цель: ${MAKE_VARIANT[*]}"
if [ -n "$OPTIONS" ]; then echo "==> Опции: $OPTIONS"; fi
STAMP="$(mktemp)"
trap 'rm -f "$STAMP"' EXIT
docker "${DOCKER_ARGS[@]}" "$IMAGE" make "${MAKE_ARGS[@]}"

# ------------------------------ результат -------------------------------------
mkdir -p dist
new_hexes="$(find betaflight/obj -maxdepth 1 -name '*.hex' -newer "$STAMP")"
if [ -n "$new_hexes" ]; then
    echo "$new_hexes" | while read -r h; do cp -v "$h" dist/; done
    echo "==> Готово: $(echo "$new_hexes" | head -1)"
else
    echo "Внимание: новых .hex в betaflight/obj/ не найдено" >&2
fi
