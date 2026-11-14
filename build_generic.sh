#!/usr/bin/env bash
#
# build_generic.sh — universal Betaflight firmware build inside the official
# toolchain docker image (betaflight/betaflight-build).
#
# Supports:
#   * standard board configs from betaflight/config (MATEKF405TE, MICOAIR743V2, ...)
#   * custom configs: config.h as a file, URL or a directory with configs/<NAME>/config.h
#     (e.g. MicoAir743V2_EXTMAG from https://github.com/micoair/MicoAir743v2)
#   * base MCU targets without a board config (STM32H743, STM32F405, ...)
#
# Options use the human names from the Configurator firmware flasher
# (--radio/--telemetry/--osd/--motor/--feat) and are translated into make
# defines via the official API https://build.betaflight.com/api/options/<version>
#
set -euo pipefail

DEFAULT_BF_VERSION="2026.6.2"
BF_VERSION="$DEFAULT_BF_VERSION"
BF_REPO="https://github.com/betaflight/betaflight"
IMAGE="betaflight/betaflight-build:arm"
BUILD_API="https://build.betaflight.com"

usage() {
cat <<'EOF'
Usage:
  ./build_generic.sh [options] <config|target>

Build target:
  <NAME>                   standard board config from betaflight/config
                           (MATEKF405TE, MICOAIR743V2, ...); see --list-configs.
                           With --config — the custom config name.
  -t, --target <NAME>      base MCU target without a board config (STM32H743,
                           STM32F405, AT32F435G, ...); see --list-targets
  -c, --config <File|URL|Dir>
                           custom config.h: a file, its URL, a directory holding
                           config.h or a root directory with configs/<NAME>/config.h
                           layouts. MCU comes from FC_TARGET_MCU inside config.h.
  -n, --name <NAME>        custom config name (default: the directory name around
                           config.h, or the name taken from the URL)

Options:
  -b, --bf-version <VER>   Betaflight version: tag/branch (default: 2026.6.2)
  -i, --image <IMAGE>      toolchain docker image (default: betaflight/betaflight-build:arm)
  --radio <LIST>           CRSF | FPORT | GHOST | IBUS | JETIEXBUS | MAVLINK | PPM |
                           SBUS | SPEKTRUM | SRXL2 | SUMD | SUMH | XBUS;
                           several allowed, comma-separated: --radio CRSF,MAVLINK
  --telemetry <LIST>       FRSKY_HUB | HOTT | IBUS_EXTENDED | LTM | MAVLINK |
                           SMARTPORT | SRXL | none (list, same as --radio)
                           (CRSF/GHOST/FPORT/JETIEXBUS enable telemetry themselves)
  --osd <LIST>             Analog | Digital | FrSky | none (several allowed)
  --motor <LIST>           BRUSHED | DSHOT | MULTISHOT | ONESHOT | PROSHOT | PWM
  -f, --feat <LIST>        extra options (comma-separated or repeated flag), names
                           as in the UI: "Altitude Hold", "Batt. Continue",
                           "Dashboard", "LED Strip", "Pin IO", "Chirp", GPS, VTX...
                           Full list of all available: --list-options
  -D, --define <DEFINE>    arbitrary define, bypassing the API (repeatable),
                           e.g. USE_EMFAT_TOOLS, USE_USB_CDC_HID
  -v, --verbose            print the option mapping notes (# name -> DEFINE,
                           # auto: +DEFINE)
  --plain                  do not add CLOUD_BUILD: chosen options are layered on
                           top of the "all features by default" (plain make build)
  --no-auto                experts only: no auto-completion at all (no USE_SERIALRX /
                           USE_TELEMETRY umbrellas, no radio-included telemetry, no
                           GPS/Flight Plan/EMFAT/4way additions) and --radio,
                           --telemetry, --osd, --motor are rejected — you list every
                           define yourself with -f / -D
  --preview, --dry-run     print the docker/make command instead of building
  --list-options           full list of all options of the chosen BF version (from API)
  --list-configs           list of standard board configs
  --list-targets           list of base MCU targets
  -h, --help               this help

Examples:
  # standard MicoAir743V2 board config from betaflight/config
  ./build_generic.sh MICOAIR743V2 --radio CRSF --osd Digital --motor DSHOT \
      -f "GPS,VTX,LED Strip"

  # custom MicoAir config.h — external-magnetometer variant (MICOAIR743V2_EXTMAG)
  ./build_generic.sh -c https://raw.githubusercontent.com/micoair/MicoAir743v2/main/Firmware/Betaflight/target/MICOAIR743V2_EXTMAG/config.h \
      --radio CRSF --osd Digital --motor DSHOT \
      -f "Altitude Hold,Batt. Continue,Dashboard,LED Strip,Pin IO,Chirp"

  # base STM32H743 target (all default features, no board config)
  ./build_generic.sh -t STM32H743

  # several radio protocols in one firmware + show the command instead of building
  ./build_generic.sh -t STM32H743 --radio CRSF,MAVLINK --motor DSHOT --preview

Result: dist/betaflight_<version>_<target>.hex (elf/map — in betaflight/obj/)
EOF
}

# split a comma-separated list keeping commas inside parentheses intact
# (the option "EMFAT (AutoRun, Icon)" contains a comma in its UI name)
split_list() {
    _SPLIT=()
    local s="$1" cur="" depth=0 i c t
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        if [ "$c" = "(" ]; then depth=$((depth + 1))
        elif [ "$c" = ")" ] && ((depth > 0)); then depth=$((depth - 1))
        elif [ "$c" = "," ] && ((depth == 0)); then
            _SPLIT+=("$cur")
            cur=""
            continue
        fi
        cur+="$c"
    done
    _SPLIT+=("$cur")
    for t in "${!_SPLIT[@]}"; do
        c="${_SPLIT[$t]}"
        _SPLIT[$t]="${c#"${c%%[![:space:]]*}"}"
        _SPLIT[$t]="${_SPLIT[$t]%"${_SPLIT[$t]##*[![:space:]]}"}"
    done
}

# ------------------------------ argument parsing ------------------------------
declare -a FEATS=() DEFINES=() RADIOS=() TELEMETRIES=() OSDS=() MOTORS=()
CONFIG_SRC="" NAME_ARG="" TARGET_ARG=""
TARGET_MODE=0 PLAIN=0 PREVIEW=0 VERBOSE=0 NO_AUTO=0 LIST_OPTS=0 LIST_CFG=0 LIST_TGT=0

while (($#)); do
    case "$1" in
        -b|--bf-version) BF_VERSION="$2"; shift 2;;
        -i|--image)      IMAGE="$2"; shift 2;;
        -c|--config)     CONFIG_SRC="$2"; shift 2;;
        -n|--name)       NAME_ARG="$2"; shift 2;;
        -t|--target)     TARGET_ARG="$2"; shift 2;;
        -f|--feat)       split_list "$2"; FEATS+=("${_SPLIT[@]}"); shift 2;;
        -D|--define)     DEFINES+=("$2"); shift 2;;
        --radio)         split_list "$2"; RADIOS+=("${_SPLIT[@]}"); shift 2;;
        --telemetry)     split_list "$2"; TELEMETRIES+=("${_SPLIT[@]}"); shift 2;;
        --osd)           split_list "$2"; OSDS+=("${_SPLIT[@]}"); shift 2;;
        --motor)         split_list "$2"; MOTORS+=("${_SPLIT[@]}"); shift 2;;
        --plain)         PLAIN=1; shift;;
        --no-auto)       NO_AUTO=1; shift;;
        -v|--verbose)    VERBOSE=1; shift;;
        --preview|--dry-run) PREVIEW=1; shift;;
        --list-options)  LIST_OPTS=1; shift;;
        --list-configs)  LIST_CFG=1; shift;;
        --list-targets)  LIST_TGT=1; shift;;
        -h|--help)       usage; exit 0;;
        -*)              echo "Unknown option: $1" >&2; usage >&2; exit 1;;
        *)               NAME_ARG="$1"; shift;;
    esac
done

# --no-auto is an experts-only mode: the Configurator-style wizard flags are off,
# the user lists every define by hand (-f "<UI name>" / -D USE_XXX).
if ((NO_AUTO)) && ((${#RADIOS[@]} || ${#TELEMETRIES[@]} || ${#OSDS[@]} || ${#MOTORS[@]})); then
    echo "Error: --no-auto (experts only) does not accept --radio/--telemetry/--osd/--motor." >&2
    echo "  Use -f \"<UI name>\" (see --list-options) or -D USE_XXX for every define." >&2
    exit 1
fi

cd "$(dirname "$0")"
mkdir -p .build
OPT_JSON=".build/options-${BF_VERSION}.json"

fetch_options() {
    if [ ! -s "$OPT_JSON" ]; then
        curl -fsSL --retry 3 -o "$OPT_JSON" "$BUILD_API/api/options/${BF_VERSION}" \
            || { rm -f "$OPT_JSON"
                 echo "Error: build API does not know version '${BF_VERSION}'. Pass options via -D USE_XXX" >&2
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
    # all repo submodules, sequentially on the host: concurrent
    # git submodule update calls race on the .git/config lock file
    git -C betaflight submodule update --init --recursive
}

base_targets() {
    find betaflight/src/platform/*/target -mindepth 2 -maxdepth 2 -name target.mk \
        | awk -F/ '{print $(NF-1)}' | sort -u
}

# -------------------------------- list modes ----------------------------------
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
        print(f"  {name:28s} {it['value'] or '(none)':26s} {', '.join(flags)}")
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

# ----------------------------- build mode selection ---------------------------
if [ -n "$TARGET_ARG" ]; then
    TARGET_MODE=1
    NAME_ARG="$TARGET_ARG"
fi

CUSTOM_ROOT=""   # directory handed to the container as BETAFLIGHT_CONFIG
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
        # ready-made CONFIG_DIR: configs/<NAME>/config.h or configs/<MFR>/<NAME>/config.h
        CUSTOM_ROOT="$(realpath "$CONFIG_SRC")"
        cfgs="$(find "$CUSTOM_ROOT/configs" -mindepth 2 -maxdepth 3 -name config.h)"
        if [ -z "$cfgs" ]; then
            echo "Error: no config.h found under '$CUSTOM_ROOT/configs'" >&2; exit 1
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
            echo "Error: config.h not found: $CONFIG_SRC" >&2; exit 1
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
        echo "Error: --target cannot be combined with --config" >&2; exit 1
    fi
    ensure_sources
    if ! base_targets | grep -qx "$BUILD_NAME"; then
        echo "Error: '$BUILD_NAME' is not among the base targets. Similar:" >&2
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
        echo "Error: config '$BUILD_NAME' not found in betaflight/config. Similar:" >&2
        find betaflight/src/config/configs -mindepth 2 -maxdepth 3 -name config.h \
            | awk -F/ '{print $(NF-1)}' | grep -i -- "$(echo "$BUILD_NAME" | cut -c1-6)" | head -10 >&2 || true
        echo "(custom config — use -c/--config)" >&2
        exit 1
    fi
    MAKE_VARIANT=("CONFIG=$BUILD_NAME")
fi

# -------------------------- options -> defines (via API) ----------------------
declare -a MAP_SEL=()
for r in "${RADIOS[@]+"${RADIOS[@]}"}"; do MAP_SEL+=("radio	$r"); done
for t in "${TELEMETRIES[@]+"${TELEMETRIES[@]}"}"; do MAP_SEL+=("telemetry	$t"); done
for o in "${OSDS[@]+"${OSDS[@]}"}"; do MAP_SEL+=("osd	$o"); done
for m in "${MOTORS[@]+"${MOTORS[@]}"}"; do MAP_SEL+=("motor	$m"); done
for f in "${FEATS[@]+"${FEATS[@]}"}"; do MAP_SEL+=("general	$f"); done
HAVE_OPTS=0
if ((${#MAP_SEL[@]} || ${#DEFINES[@]})); then HAVE_OPTS=1; fi

OPTIONS=""
if ((HAVE_OPTS)); then
    fetch_options
    DEFS="$(BF_VERBOSE="$VERBOSE" BF_NO_AUTO="$NO_AUTO" python3 - "$OPT_JSON" "${MAP_SEL[@]+"${MAP_SEL[@]}"}" <<'PY'
import json, os, re, sys

path = sys.argv[1]
tokens = [t.split("\t", 1) for t in sys.argv[2:]]
d = json.load(open(path))
sections = [("radio", d["radioProtocols"]),
            ("telemetry", d["telemetryProtocols"]),
            ("general", d["generalOptions"]),
            ("motor", d["motorProtocols"])]

# telemetry automatically enabled together with the radio protocol
radio_telemetry = {"USE_SERIALRX_CRSF": "USE_TELEMETRY_CRSF",
                   "USE_SERIALRX_FPORT": "USE_TELEMETRY_SMARTPORT",
                   "USE_SERIALRX_GHST": "USE_TELEMETRY_GHST",
                   "USE_SERIALRX_JETIEXBUS": "USE_TELEMETRY_JETIEXBUS"}

def norm(s):
    # case- and separator-insensitive: "IBUS EXTENDED" == "ibus_extended" == "use_telemetry_ibus_extended"-suffix
    return re.sub(r"[^a-z0-9]+", "", s.lower())

# define name variants a token can match: the full define and the define without
# its section prefix (MAG -> USE_MAG, CRSF -> USE_SERIALRX_CRSF, IBUS_EXTENDED ->
# USE_TELEMETRY_IBUS_EXTENDED)
VAL_PREFIXES = ("USE_SERIALRX_", "USE_TELEMETRY_", "USE_RX_", "USE_OSD_", "USE_")

def variants(it):
    out = {norm(it["name"])}
    if it.get("groupedName"):
        out.add(norm(it["groupedName"]))
    v = it["value"]
    names = [v]
    for p in VAL_PREFIXES:
        if v.startswith(p) and len(v) - len(p) >= 3:
            names.append(v[len(p):])
    for n in names:
        out.add(norm(n))
    return out

def lookup(sec_wanted, tok):
    t = norm(tok)
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
            if t in variants(it):
                cands.append((sec, it))
    if not cands:
        return None
    if len(cands) > 1:
        strict = [c for c in cands
                  if norm(c[1]["name"]) == t or norm(c[1]["value"]) == t]
        if len(strict) == 1:
            cands = strict
    if len(cands) > 1:
        print("Ambiguous: '%s': %s" % (tok, "; ".join(
            f"{c[1]['name']}={c[1]['value']}" for c in cands)), file=sys.stderr)
        sys.exit(2)
    return cands[0]

defines, notes = [], []
no_auto = os.environ.get("BF_NO_AUTO") == "1"
for sec_wanted, tok in tokens:
    if tok.strip().lower() in ("none", ""):
        continue
    hit = lookup(sec_wanted, tok)
    if hit is None:
        print(f"Unknown option: '{tok}' (section {sec_wanted}). "
              f"Full list: --list-options", file=sys.stderr)
        sys.exit(2)
    sec, it = hit
    defines.append(it["value"])
    notes.append(f"{it['name']} -> {it['value']}")
    if no_auto:
        continue
    if it["value"] in ("USE_OSD_SD", "USE_OSD_HD", "USE_FRSKYOSD"):
        defines.append("USE_OSD")
    if sec == "radio" and it.get("includesTelemetry"):
        defines.append("USE_TELEMETRY")
        extra = radio_telemetry.get(it["value"])
        if extra:
            defines.append(extra)
            notes.append(f"auto-telemetry: {it['name']} -> {extra}")
    if sec == "telemetry" and it["value"]:
        defines.append("USE_TELEMETRY")

seen, out = set(), []
for x in defines:
    if x not in seen:
        seen.add(x)
        out.append(x)
if os.environ.get("BF_VERBOSE") == "1":
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

    # auto-defines the official build.betaflight.com adds (rules per
    # betaflight.com docs: development/Defines.md + wiki/Build-Options.md, verified
    # against the POST /api/builds request echo). common_post.h sweeps orphan
    # defines, so USE_SERIALRX_* won't compile without the USE_SERIALRX umbrella.
    # MAVLINK additionally gets USE_TELEMETRY(+MAVLINK): the SERIALRX_MAVLINK provider
    # can not work without TELEMETRY_MAVLINK (common_pre.h:494 auto-defines it outside
    # the CLOUD_BUILD gate, but being belt-and-braces we pass the umbrella explicitly):
    #   USE_SERIALRX_* -> USE_SERIALRX, USE_TELEMETRY_* -> USE_TELEMETRY,
    #   USE_SERIALRX_MAVLINK -> USE_TELEMETRY + USE_TELEMETRY_MAVLINK,
    #   USE_RX_PPM -> USE_PPM, USE_GPS -> USE_ALTITUDE_HOLD/USE_GPS_PLUS_CODES/USE_POSITION_HOLD,
    #   USE_FLIGHT_PLAN -> USE_GPS + USE_ALTITUDE_HOLD + USE_POSITION_HOLD,
    #   USE_EMFAT_TOOLS -> USE_EMFAT_AUTORUN + USE_EMFAT_ICON,
    #   USE_ESCSERIAL_SIMONK -> USE_SERIAL_4WAY_SK_BOOTLOADER,
    #   USE_LED_STRIP_64 -> USE_LED_STRIP
    # (EMFAT_*/4WAY_SK are only in the !CLOUD_BUILD defaults of common_pre.h, so
    # cloud builds really need them passed explicitly.)
    # --no-auto (experts only) turns all of this off: OPTIONS is exactly what -f/-D gave.
    if ((NO_AUTO == 0)); then
    declare -a _exp=()
    for o in "${OPT_LIST[@]}"; do
        case "$o" in
            USE_SERIALRX_MAVLINK) _exp+=("USE_SERIALRX" "USE_TELEMETRY" "USE_TELEMETRY_MAVLINK");;
            USE_SERIALRX_*)  _exp+=("USE_SERIALRX");;
            USE_TELEMETRY_*) _exp+=("USE_TELEMETRY");;
            USE_RX_PPM)      _exp+=("USE_PPM");;
            USE_GPS)         _exp+=("USE_ALTITUDE_HOLD" "USE_GPS_PLUS_CODES" "USE_POSITION_HOLD");;
            USE_FLIGHT_PLAN) _exp+=("USE_GPS" "USE_ALTITUDE_HOLD" "USE_POSITION_HOLD");;
            USE_EMFAT_TOOLS) _exp+=("USE_EMFAT_AUTORUN" "USE_EMFAT_ICON");;
            USE_ESCSERIAL_SIMONK) _exp+=("USE_SERIAL_4WAY_SK_BOOTLOADER");;
            USE_LED_STRIP_64) _exp+=("USE_LED_STRIP");;
        esac
    done
    for o in "${_exp[@]+"${_exp[@]}"}"; do
        present=0
        for e in "${OPT_LIST[@]}"; do
            if [ "$e" = "$o" ]; then present=1; break; fi
        done
        if ((present == 0)); then
            OPT_LIST+=("$o")
            if ((VERBOSE)); then echo "  # auto: +$o" >&2; fi
        fi
    done
    fi
    # documented sweeps that silently drop a chosen option (warn, don't change defines):
    #  - USE_TELEMETRY_SRXL is undefined by common_post.h:438 unless the build has
    #    USE_SERIALRX_SPEKTRUM or USE_SERIALRX_SRXL2 (common_pre.h:395 pulls SPEKTRUM
    #    in, but common_post.h:340 sweeps it when there is no USE_SERIALRX umbrella);
    #  - USE_POSITION_HOLD without USE_GPS/USE_OPTICALFLOW stops the build with
    #    #error (common_post.h:907) unless the board config.h supplies one.
    if [[ " ${OPT_LIST[*]} " == *" USE_TELEMETRY_SRXL "*
          && " ${OPT_LIST[*]} " != *" USE_SERIALRX "*
          && " ${OPT_LIST[*]} " != *" USE_SERIALRX_SPEKTRUM "*
          && " ${OPT_LIST[*]} " != *" USE_SERIALRX_SRXL2 "* ]]; then
        echo "Warning: SRXL telemetry needs a Spektrum/SRXL2 receiver: add --radio SPEKTRUM or SRXL2," >&2
        echo "         otherwise common_post.h:438 removes USE_TELEMETRY_SRXL from the firmware." >&2
    fi
    if [[ " ${OPT_LIST[*]} " == *" USE_POSITION_HOLD "*
          && " ${OPT_LIST[*]} " != *" USE_GPS "*
          && " ${OPT_LIST[*]} " != *" USE_OPTICALFLOW "* ]]; then
        echo "Warning: USE_POSITION_HOLD requires USE_GPS and/or USE_OPTICALFLOW (common_post.h:907" >&2
        echo "         #error) - add -f \"GPS\"/\"Optical Flow\" unless the board config.h defines one." >&2
    fi
    OPTIONS="${OPT_LIST[*]}"
fi

# ------------------------------- build (docker) -------------------------------
ensure_sources
ensure_submodules

DOCKER_ARGS=(run --rm -u "$(id -u):$(id -g)" -v "$(pwd)/betaflight":/src)
if [ -n "$CUSTOM_ROOT" ]; then
    DOCKER_ARGS+=(-v "$CUSTOM_ROOT":/configs -e "BETAFLIGHT_CONFIG=/configs")
fi
MAKE_ARGS=(-j)
if [ -n "$OPTIONS" ]; then MAKE_ARGS+=("OPTIONS=$OPTIONS"); fi
MAKE_ARGS+=("${MAKE_VARIANT[@]}" hex)

echo "==> Target: ${MAKE_VARIANT[*]}"
if [ -n "$OPTIONS" ]; then echo "==> Options: $OPTIONS"; fi

DOCKER_CMD=(docker "${DOCKER_ARGS[@]}" "$IMAGE" make "${MAKE_ARGS[@]}")
if ((PREVIEW)); then
    echo "==> Build command (preview, nothing is run):"
    _q=""
    for _a in "${DOCKER_CMD[@]}"; do
        case "$_a" in
            *[[:space:]]*) _q+=" \"$_a\"";;
            *)             _q+=" $_a";;
        esac
    done
    echo "${_q# }"
    exit 0
fi

STAMP="$(mktemp)"
trap 'rm -f "$STAMP"' EXIT
docker "${DOCKER_ARGS[@]}" "$IMAGE" make "${MAKE_ARGS[@]}"

# --------------------------------- result -------------------------------------
mkdir -p dist
new_hexes="$(find betaflight/obj -maxdepth 1 -name '*.hex' -newer "$STAMP")"
if [ -n "$new_hexes" ]; then
    echo "$new_hexes" | while read -r h; do cp -v "$h" dist/; done
    echo "==> Done: $(echo "$new_hexes" | head -1)"
else
    echo "Warning: no new .hex found in betaflight/obj/" >&2
fi
