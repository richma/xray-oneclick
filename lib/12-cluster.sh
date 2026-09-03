# 3X-UI 主从集群: 纯函数 (可单测) + 运行时 API 封装

cluster_token_body() {
  local name="${1:-xray-oneclick-node-sync}" scope="${2:-node-sync}"
  printf '{"name":"%s","scope":"%s","expiresAt":0}' "$(json_escape "$name")" "$(json_escape "$scope")"
}

cluster_node_body() {
  local name="$1" address="$2" port="$3" base_path="$4" token="$5"
  local scheme="${6:-http}" sync="${7:-all}" allow_priv="${8:-false}" tls_mode="${9:-skip}"
  [ "${base_path#/}" = "$base_path" ] && [ -n "$base_path" ] && base_path="/$base_path"
  [ -z "$base_path" ] && base_path="/"
  printf '{"name":"%s","remark":"%s","scheme":"%s","address":"%s","port":%s,"basePath":"%s","apiToken":"%s","enable":true,"allowPrivateAddress":%s,"inboundSyncMode":"%s","tlsVerifyMode":"%s"}' \
    "$(json_escape "$name")" \
    "$(json_escape "$name")" \
    "$(json_escape "$scheme")" \
    "$(json_escape "$address")" \
    "$port" \
    "$(json_escape "$base_path")" \
    "$(json_escape "$token")" \
    "$allow_priv" \
    "$(json_escape "$sync")" \
    "$(json_escape "$tls_mode")"
}

cluster_client_body() {
  local email="$1" sub_id="$2" uuid="$3" inbound_ids_csv="$4" flow="${5:-xtls-rprx-vision}"
  local ids="" id
  IFS=',' read -r -a _ids <<< "$inbound_ids_csv"
  for id in "${_ids[@]}"; do
    id="$(echo "$id" | tr -d '[:space:]')"
    [ -n "$id" ] || continue
    [ -n "$ids" ] && ids="$ids,"
    ids="$ids$id"
  done
  printf '{"client":{"email":"%s","enable":true,"flow":"%s","subId":"%s","id":"%s"},"inboundIds":[%s]}' \
    "$(json_escape "$email")" "$(json_escape "$flow")" "$(json_escape "$sub_id")" "$(json_escape "$uuid")" "$ids"
}

cluster_host_body() {
  local inbound_id="$1" host="$2" remark="${3:-}" port="${4:-443}" sni="${5:-}" fingerprint="${6:-chrome}"
  printf '{"inboundIds":[%s],"hosts":["%s"],"remark":"%s","port":%s,"security":"reality","sni":"%s","fingerprint":"%s"}' \
    "$inbound_id" "$(json_escape "$host")" "$(json_escape "$remark")" "$port" "$(json_escape "$sni")" "$(json_escape "$fingerprint")"
}

xui_cookie_file() {
  echo "${XUI_COOKIE_FILE:-$INSTALL_DIR/.xui-cookies}"
}

xui_local_origin() {
  echo "http://127.0.0.1:${XUI_PORT:-2053}"
}

xui_login() {
  local user="${XUI_USER:-admin}" pass="${XUI_PASS:-admin}"
  local base origin path cookie
  origin="$(xui_local_origin)"
  path="$(parse_xui_base_path)"
  cookie="$(xui_cookie_file)"
  mkdir -p "$(dirname "$cookie")"
  rm -f "$cookie"
  [ -z "$path" ] && path="/"
  case "$path" in
    */) ;;
    *) path="$path/" ;;
  esac
  local url="${origin}${path}login"
  info "登录本地 3X-UI: $url (用户 $user)"
  local code
  code="$(curl -sS -o /tmp/xui-login.json -w '%{http_code}' -c "$cookie" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$(json_escape "$user")\",\"password\":\"$(json_escape "$pass")\"}" \
    "$url" 2>/dev/null || echo 000)"
  if [ "$code" != "200" ]; then
    die "面板登录失败 (HTTP $code). 请用 --xui-user / --xui-pass, 或先改掉默认 admin 后传入新密码. 响应: $(head -c 200 /tmp/xui-login.json 2>/dev/null)"
  fi
  if grep -q '"success":false' /tmp/xui-login.json 2>/dev/null; then
    die "面板登录被拒绝: $(cat /tmp/xui-login.json)"
  fi
  chmod 600 "$cookie" 2>/dev/null || true
  ok "面板登录成功"
}

xui_api() {
  local method="$1" rel="$2" body="${3:-}"
  local origin path cookie token url
  origin="$(xui_local_origin)"
  path="$(parse_xui_base_path)"
  [ -z "$path" ] && path="/"
  case "$path" in
    */) ;;
    *) path="$path/" ;;
  esac
  case "$rel" in
    /*) ;;
    *) rel="/$rel" ;;
  esac
  # rel 形如 /setting/apiTokens/create
  url="${origin}${path}panel/api${rel}"

  cookie="$(xui_cookie_file)"
  token="${XUI_TOKEN:-}"
  local args=(-sS -X "$method" "$url" -H 'Content-Type: application/json' -H 'Accept: application/json')
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  else
    [ -f "$cookie" ] || xui_login
    args+=(-b "$cookie" -c "$cookie")
    local csrf
    csrf="$(curl -sS -b "$cookie" "${origin}${path}csrf-token" 2>/dev/null | sed -n 's/.*"csrf":"\([^"]*\)".*/\1/p')"
    [ -z "$csrf" ] && csrf="$(curl -sS -b "$cookie" "${origin}${path}csrf-token" 2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    [ -n "$csrf" ] && args+=(-H "X-CSRF-Token: $csrf")
  fi
  if [ -n "$body" ]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

cmd_cluster_token() {
  check_root
  docker ps --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 未运行, 请先 install"
  [ -n "${XUI_TOKEN:-}" ] || xui_login
  local name="${CLUSTER_TOKEN_NAME:-xray-oneclick-node-sync}"
  local body resp token_val
  body="$(cluster_token_body "$name" "node-sync")"
  resp="$(xui_api POST "/setting/apiTokens/create" "$body")" || die "创建 API Token 请求失败"
  if echo "$resp" | grep -q '"success":false'; then
    name="${name}-$(date +%s)"
    body="$(cluster_token_body "$name" "node-sync")"
    resp="$(xui_api POST "/setting/apiTokens/create" "$body")" || die "创建 API Token 请求失败"
  fi
  token_val="$(echo "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("obj") or {}).get("token") or "")' 2>/dev/null || true)"
  [ -n "$token_val" ] || die "未能解析 Token, 面板响应: $resp"
  umask 077
  printf '%s\n' "$token_val" > "$INSTALL_DIR/cluster-node-sync.token"
  chmod 600 "$INSTALL_DIR/cluster-node-sync.token"
  banner "子节点 node-sync Token (只显示一次, 已写入 $INSTALL_DIR/cluster-node-sync.token)"
  echo "$token_val"
  info "在主节点执行:"
  local path; path="$(parse_xui_base_path)"
  echo "  sudo bash install.sh cluster-add-node --node-name <名称> --node-address <本机IP或域名> --node-port ${XUI_PORT} --node-path '${path:-/}' --node-token '<上面的Token>'"
}

cmd_cluster_add_node() {
  check_root
  docker ps --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 未运行, 请先 install"
  [ -n "${NODE_NAME:-}" ] || die "需要 --node-name"
  [ -n "${NODE_ADDRESS:-}" ] || die "需要 --node-address"
  [ -n "${NODE_TOKEN:-}" ] || die "需要 --node-token (子节点 cluster-token 的输出)"
  local port="${NODE_PORT:-$XUI_PORT}"
  local path="${NODE_PATH:-/}"
  local scheme="${NODE_SCHEME:-http}"
  local sync="${NODE_SYNC:-all}"
  local allow=false tls="skip"
  [ "${NODE_ALLOW_PRIVATE:-0}" = 1 ] && allow=true
  [ "${NODE_TLS_SKIP:-1}" = 0 ] && tls="verify"
  [ "$scheme" = "https" ] && [ "${NODE_TLS_SKIP:-1}" = 1 ] && tls="skip"
  [ -n "${XUI_TOKEN:-}" ] || xui_login
  local body resp
  body="$(cluster_node_body "$NODE_NAME" "$NODE_ADDRESS" "$port" "$path" "$NODE_TOKEN" "$scheme" "$sync" "$allow" "$tls")"
  info "向主面板注册子节点 $NODE_NAME ($scheme://$NODE_ADDRESS:$port$path) ..."
  resp="$(xui_api POST "/nodes/add" "$body")" || die "nodes/add 请求失败"
  echo "$resp"
  echo "$resp" | grep -q '"success":true' || die "添加子节点失败"
  ok "子节点已添加. 可执行: bash install.sh cluster-status"
}

cmd_cluster_share() {
  check_root
  docker ps --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 未运行"
  local email="${SHARE_EMAIL:-main}"
  local sub_id="${SHARE_SUBID:-main}"
  local uuid="${SHARE_UUID:-}"
  [ -n "$uuid" ] || uuid="$(gen_uuid)"
  [ -n "${XUI_TOKEN:-}" ] || xui_login
  local list ids
  list="$(xui_api GET "/inbounds/list")" || die "读取入站列表失败"
  ids="$(echo "$list" | python3 -c '
import json,sys
d=json.load(sys.stdin)
obj=d.get("obj") or d.get("data") or []
if isinstance(obj, dict):
    obj=obj.get("list") or obj.get("inbounds") or []
out=[]
for it in obj:
    i=it.get("id")
    if i is not None:
        out.append(str(i))
print(",".join(out))
' 2>/dev/null)" || true
  [ -n "$ids" ] || die "未找到任何入站, 请先在面板创建 Reality 入站. 响应: $(echo "$list" | head -c 300)"
  local body resp
  body="$(cluster_client_body "$email" "$sub_id" "$uuid" "$ids")"
  info "在入站 [$ids] 上添加共享客户端 email=$email subId=$sub_id uuid=$uuid"
  resp="$(xui_api POST "/clients/add" "$body")" || die "clients/add 请求失败"
  echo "$resp"
  echo "$resp" | grep -q '"success":true' || warn "添加客户端可能失败 (email 已存在时属正常)"
  umask 077
  cat > "$INSTALL_DIR/cluster-share.txt" <<EOF
email=$email
subId=$sub_id
uuid=$uuid
inbounds=$ids
EOF
  chmod 600 "$INSTALL_DIR/cluster-share.txt"
  ok "共享客户端已写入. 主面板订阅: http://<主节点>:2096/sub/$sub_id (需先 xui-port 2096)"
  info "其它节点请使用相同 UUID: --share-uuid $uuid"
}

cmd_cluster_host() {
  check_root
  [ -n "${HOST_INBOUND:-}" ] || die "需要 --host-inbound <入站ID>"
  [ -n "${HOST_ADDR:-}" ] || die "需要 --host-addr <域名或 域名:端口>"
  docker ps --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 未运行"
  [ -n "${XUI_TOKEN:-}" ] || xui_login
  local port=443 host="$HOST_ADDR"
  if [[ "$host" == *:* ]]; then
    port="${host##*:}"
    host="${host%:*}"
  fi
  local body resp
  body="$(cluster_host_body "$HOST_INBOUND" "${host}:${port}" "${HOST_REMARK:-$host}" "$port" "${HOST_SNI:-}" "${HOST_FINGERPRINT:-chrome}")"
  resp="$(xui_api POST "/hosts/add" "$body")" || die "hosts/add 请求失败"
  echo "$resp"
  echo "$resp" | grep -q '"success":true' || die "添加 Host 覆盖失败"
  ok "已为入站 $HOST_INBOUND 覆盖订阅地址 $host:$port"
}

cmd_cluster_status() {
  check_root
  docker ps --format '{{.Names}}' | grep -qx "3x-ui" || die "3X-UI 未运行"
  [ -n "${XUI_TOKEN:-}" ] || xui_login
  local resp
  resp="$(xui_api GET "/nodes/list")" || die "nodes/list 请求失败"
  echo "$resp" | python3 -c '
import json,sys
d=json.load(sys.stdin)
obj=d.get("obj") or []
if not obj:
    print("(主面板尚未注册子节点)")
    sys.exit(0)
print("{:<4} {:<16} {:<28} {:<8} {:>8} {}".format("ID","NAME","ADDRESS","STATUS","LATENCY","SYNC"))
for n in obj:
    print("{:<4} {:<16} {:<28} {:<8} {:>8} {}".format(
        n.get("id",""),
        (n.get("name") or "")[:16],
        "{}://{}:{}".format(n.get("scheme"), n.get("address"), n.get("port"))[:28],
        n.get("status") or "",
        str(n.get("latencyMs") or "-"),
        n.get("inboundSyncMode") or "",
    ))
' 2>/dev/null || echo "$resp"
}
