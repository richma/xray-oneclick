fetch_servernames() {
  mkdir -p "$INSTALL_DIR/conf"
  if [ ! -s "$SERVERNAMES_FILE" ]; then
    info "获取伪装站点列表 SERVERNAMES_ZH.MD ..."
    # shellcheck disable=SC2046
    try_download "$SERVERNAMES_FILE" \
      $(raw_urls "https://raw.githubusercontent.com/wulabing/xray_docker/master/reality/SERVERNAMES_ZH.MD") \
      "https://cdn.jsdelivr.net/gh/wulabing/xray_docker@master/reality/SERVERNAMES_ZH.MD" || {
      warn "SERVERNAMES_ZH.MD 获取失败, 使用内置默认值 (www.apple.com)"
    }
  fi
}

parse_servernames() {
  [ -s "$SERVERNAMES_FILE" ] || return 0
  awk -F'|' '
    /^\|/ {
      d=$2; s=$3
      gsub(/^ +| +$/, "", d); gsub(/^ +| +$/, "", s)
      if (d ~ /^[^ |]+\.[^ |]+:[0-9]+$/ && s != "" && d != "DEST") {
        print d "\t" s
      }
    }' "$SERVERNAMES_FILE"
}

pick_dest() {
  local choice=0 n=0 line d s
  fetch_servernames
  local list=()
  while IFS=$'\t' read -r d s; do
    [ -n "$d" ] && list+=("$d|$s")
  done < <(parse_servernames)
  if [ "${#list[@]}" = 0 ]; then
    DEST="www.apple.com:443"; SERVERNAMES="images.apple.com www.apple.com"
    return 0
  fi
  banner "可用的伪装站点 (Reality DEST / SERVERNAMES):"
  local i
  for i in "${!list[@]}"; do
    d="${list[$i]%|*}"; s="${list[$i]#*|}"
    printf "  ${C_CYAN}%d${C_RESET}) %-28s SNI: %s\n" "$((i+1))" "$d" "$s"
  done
  ask "选择伪装站点" "1"
  choice="$ANSWER"
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#list[@]}" ]; then
    warn "输入无效, 使用默认第 1 项"; choice=1
  fi
  DEST="${list[$((choice-1))]%|*}"
  SERVERNAMES="${list[$((choice-1))]#*|}"
  ok "伪装站点: DEST=$DEST  SERVERNAMES=$SERVERNAMES"
}
