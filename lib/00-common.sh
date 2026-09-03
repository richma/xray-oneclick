# 输出、交互、下载、JSON/UUID 工具
: "${C_RESET:=$'\033[0m'}"; : "${C_RED:=$'\033[0;31m'}"; : "${C_GREEN:=$'\033[0;32m'}"
: "${C_YELLOW:=$'\033[0;33m'}"; : "${C_BLUE:=$'\033[0;34m'}"; : "${C_CYAN:=$'\033[0;36m'}"; : "${C_BOLD:=$'\033[1m'}"

info()  { printf "${C_CYAN}[信息]${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[成功]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[警告]${C_RESET} %s\n" "$*"; }
die()   { printf "${C_RED}[错误]${C_RESET} %s\n" "$*"; exit 1; }
banner(){ printf "${C_BOLD}%s${C_RESET}\n" "$*"; }

ask() {
  local prompt="$1" def="$2"
  if [ "${ASSUME_YES:-0}" = 1 ]; then ANSWER="$def"; return; fi
  printf "%s [%s]: " "$prompt" "$def"; read -r ans
  ANSWER="${ans:-$def}"
}

ask_yn() {
  local prompt="$1" def="$2" ans
  if [ "${ASSUME_YES:-0}" = 1 ]; then ANSWER="$def"; return; fi
  printf "%s (y/n) [%s]: " "$prompt" "$def"; read -r ans
  case "${ans:-$def}" in y|Y|yes|YES) ANSWER=y ;; *) ANSWER=n ;; esac
}

confirm() {
  if [ "${ASSUME_YES:-0}" = 1 ]; then return 0; fi
  printf "${C_YELLOW}%s (y/n): ${C_RESET}" "$1"; read -r a
  case "$a" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

try_download() {
  local out="$1"; shift
  local u
  for u in "$@"; do
    [ -n "$u" ] || continue
    if curl -fsSL --connect-timeout 10 --max-time 120 -o "$out" "$u" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

raw_urls() {
  local url="$1" path="${1#https://raw.githubusercontent.com/}"
  echo "$url"
  local m
  for m in "${GITHUB_RAW_MIRRORS[@]}"; do
    case "$m" in
      *gitmirror*|*raw.gitmirror*) echo "${m}${path}" ;;
      *) echo "${m}${url}" ;;
    esac
  done
}

# GitHub Release / 任意 github.com URL 的镜像候选 (官方优先, 随后代理)
github_release_urls() {
  local url="$1"
  echo "$url"
  local m
  for m in "${GITHUB_RAW_MIRRORS[@]}"; do
    case "$m" in
      *gitmirror*|*raw.gitmirror*) ;;
      *) echo "${m}${url}" ;;
    esac
  done
}

is_valid_uuid() {
  [[ "${1:-}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

json_escape() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

gen_uuid() {
  local u h a b c d e nibble
  u="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
  is_valid_uuid "$u" && { echo "$u"; return 0; }
  u="$(command -v uuidgen >/dev/null 2>&1 && uuidgen 2>/dev/null || true)"
  is_valid_uuid "$u" && { echo "$u"; return 0; }
  u="$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || true)"
  is_valid_uuid "$u" && { echo "$u"; return 0; }
  if command -v openssl >/dev/null 2>&1; then
    h="$(openssl rand -hex 16 2>/dev/null || true)"
    if [ "${#h}" = 32 ]; then
      a="${h:0:8}"; b="${h:8:4}"; c="${h:12:4}"; d="${h:16:4}"; e="${h:20:12}"
      c="4${c:1}"
      nibble="${d:0:1}"
      case "$nibble" in
        [0-3]) nibble=8 ;;
        [4-7]) nibble=9 ;;
        [89abAB]) ;;
        *) nibble=a ;;
      esac
      d="${nibble}${d:1}"
      u="${a}-${b}-${c}-${d}-${e}"
      is_valid_uuid "$u" && { echo "$u"; return 0; }
    fi
  fi
  die "无法生成合法 UUID (需要 /proc/sys/kernel/random/uuid、uuidgen、python3 或 openssl)"
}
