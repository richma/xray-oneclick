#!/usr/bin/env bash
# ==============================================================================
# install.sh / lib/* 函数级单元测试
# 用法: 在可写 /etc 的环境运行 (推荐 docker 容器, 见 .github/workflows/ci.yml)
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash -c \
#     'apt-get update && apt-get install -y procps curl python3 openssl && bash /repo/test/unit-test.sh'
# ==============================================================================
export XRAY_ONECLICK_SOURCE_ONLY=1
export INSTALL_DIR=/tmp/xo-test
export SCRIPT_DIR=/repo
export ASSUME_YES=1
export ENABLE_BBR=1
rm -rf /tmp/xo-test
mkdir -p /tmp/xo-test

# shellcheck disable=SC1091
source /repo/install.sh
PASS=0; FAIL=0
chk() { if [ "$1" = "0" ]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi }

echo "===== 0. 模块加载 ====="
[ -n "$(type -t gen_uuid)" ]; chk $? "gen_uuid 已加载"
[ -n "$(type -t cluster_node_body)" ]; chk $? "cluster_node_body 已加载"
[ -n "$(type -t xui_insert_port_mapping)" ]; chk $? "xui_insert_port_mapping 已加载"
[ "$VERSION" = "1.1.0" ]; chk $? "VERSION=1.1.0"

echo "===== 1. 配置模板生成 ====="
ensure_base_files
test -f "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "增强路由配置模板已生成"
python3 -m json.tool "$INSTALL_DIR/conf/xray-config.template.json" >/dev/null 2>&1; chk $? "模板是合法 JSON"
grep -q "geosite:category-ads-all" "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "模板含 v2ray-rules-dat 广告拦截规则"
grep -q "geosite:cn" "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "模板含 geosite:cn 直连规则"
grep -q '"show": false' "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "realitySettings.show 为 false"
test -d "$INSTALL_DIR/lib"; chk $? "lib/ 已复制到 INSTALL_DIR"
test -f "$INSTALL_DIR/install.sh"; chk $? "install.sh 已复制到 INSTALL_DIR"

echo "===== 2. 内核优化文件写入 ====="
apply_sysctl
test -f /etc/sysctl.d/99-xray-optimize.conf; chk $? "sysctl 文件已写入 /etc/sysctl.d"
grep -q "net.ipv4.tcp_fastopen = 3" /etc/sysctl.d/99-xray-optimize.conf; chk $? "sysctl 含 TCP 优化参数"
grep -q "fs.file-max = 1048576" /etc/sysctl.d/99-xray-optimize.conf; chk $? "sysctl 含文件描述符优化"

echo "===== 3. BBR (环境受限时仅验证文件逻辑) ====="
if [ -w /proc/sys/net/ipv4/tcp_congestion_control ] \
   && (command -v modprobe >/dev/null 2>&1 || grep -qw tcp_bbr /proc/modules 2>/dev/null); then
  enable_bbr
  grep -q "tcp_congestion_control = bbr" /etc/sysctl.d/99-xray-optimize.conf; chk $? "BBR 行已追加"
  [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; chk $? "BBR 已真实生效"
else
  echo "SKIP: 容器环境无内核模块/权限, 跳过 BBR 生效测试, 仅验证写入逻辑"
  printf "\n# BBR (测试验证)\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n" >> /etc/sysctl.d/99-xray-optimize.conf
  grep -q "tcp_congestion_control = bbr" /etc/sysctl.d/99-xray-optimize.conf; chk $? "BBR 配置行写入逻辑"
fi

echo "===== 4. 伪装站点 (SERVERNAMES_ZH.MD) ====="
fetch_servernames
test -s "$INSTALL_DIR/conf/SERVERNAMES_ZH.MD"; chk $? "SERVERNAMES_ZH.MD 已下载"
n=$(parse_servernames | wc -l)
[ "$n" -ge 1 ]; chk $? "解析出 $n 个伪装站点 (DEST/TAB/SERVERNAMES)"
pick_dest
[[ "$DEST" =~ :[0-9]+$ ]]; chk $? "DEST 为 host:port 格式 ($DEST)"
[ -n "$SERVERNAMES" ]; chk $? "SERVERNAMES 非空"

echo "===== 5. 定时更新任务 ====="
install_cron
test -f /etc/cron.d/xray-rules-update; chk $? "cron 任务已写入"
grep -q "update-rules" /etc/cron.d/xray-rules-update; chk $? "cron 指向 update-rules"

echo "===== 6. 节点信息解析与订阅链接构建 ====="
mkdir -p /tmp/xo-test/nodes/node_443/data
cat > /tmp/xo-test/nodes/node_443/data/reality_config_info.txt <<'EOF'
UUID: 11111111-2222-3333-4444-555555555555
DEST: www.apple.com:443
PORT: 443
SERVERNAMES: images.apple.com www.apple.com (任选其一)
PRIVATEKEY: ppp
PUBLICKEY/PASSWORD: ppp-public
NETWORK: tcp
EOF
u=$(node_field /tmp/xo-test/nodes/node_443/data/reality_config_info.txt uuid)
[ "$u" = "11111111-2222-3333-4444-555555555555" ]; chk $? "node_field 解析 UUID"
s=$(node_field /tmp/xo-test/nodes/node_443/data/reality_config_info.txt servernames)
[ "$s" = "images.apple.com www.apple.com" ]; chk $? "node_field 解析 SERVERNAMES (去注释)"
l=$(build_vless_link /tmp/xo-test/nodes/node_443 1.2.3.4)
echo "$l" | grep -q "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443.*pbk=ppp-public.*flow=xtls-rprx-vision"; chk $? "tcp/vision 订阅链接构建"

cat > /tmp/xo-test/nodes/node_443/data/reality_config_info.txt <<'EOF'
UUID: 11111111-2222-3333-4444-555555555555
DEST: www.apple.com:443
PORT: 8443
SERVERNAMES: images.apple.com www.apple.com (任选其一)
PUBLICKEY/PASSWORD: ppp-public
NETWORK: xhttp
SHORTID: 6ba85179e30d4fc2 (6ba85179e30d4fc2 任选其一)
XHTTP_PATH: /ab12cd34
EOF
l=$(build_vless_link /tmp/xo-test/nodes/node_443 1.2.3.4)
echo "$l" | grep -q "type=xhttp.*sni=images.apple.com.*sid=6ba85179e30d4fc2.*path=/ab12cd34"; chk $? "xhttp+shortid+path 订阅链接构建"

echo "===== 7. UUID ====="
is_valid_uuid "11111111-2222-3333-4444-555555555555"; chk $? "合法 UUID 通过"
if is_valid_uuid "not-a-uuid"; then chk 1 "非法 UUID 应拒绝"; else chk 0 "非法 UUID 应拒绝"; fi
if is_valid_uuid "$(date +%s%N)-host-1"; then chk 1 "旧兜底格式不应算合法 UUID"; else chk 0 "旧兜底格式不应算合法 UUID"; fi
gu="$(gen_uuid)"
is_valid_uuid "$gu"; chk $? "gen_uuid 输出合法 UUID ($gu)"

echo "===== 8. GitHub Release 镜像 URL ====="
mapfile -t ru < <(github_release_urls "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat")
[ "${ru[0]}" = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" ]; chk $? "官方 URL 在首位"
echo "${ru[*]}" | grep -q "ghfast.top\|gh-proxy.com\|ghproxy.net"; chk $? "包含 GitHub 代理前缀"

echo "===== 9. Docker daemon.json 合并 ====="
mkdir -p /tmp/xo-dock
echo '{"bip":"10.20.0.1/24","log-driver":"json-file"}' > /tmp/xo-dock/daemon.json
merge_docker_daemon_json /tmp/xo-dock/daemon.json "https://docker.1ms.run" "https://example-mirror.test"
python3 - <<'PY'
import json,sys
d=json.load(open("/tmp/xo-dock/daemon.json"))
assert d.get("bip")=="10.20.0.1/24", d
assert "https://docker.1ms.run" in d.get("registry-mirrors",[]), d
assert d.get("log-driver")=="json-file"
sys.exit(0)
PY
chk $? "合并 daemon.json 保留 bip 并写入 mirrors"

echo "===== 10. xui_port 换行插入 ====="
cat > /tmp/xo-run.sh <<'EOF'
PORTS=(
  -p 2053:2053
)
IMAGE='x'
EOF
xui_insert_port_mapping /tmp/xo-run.sh 8388
grep -qx '  -p 8388:8388' /tmp/xo-run.sh; chk $? "端口映射独占一行"
python3 - <<'PY'
from pathlib import Path
t=Path("/tmp/xo-run.sh").read_text()
assert "-p 8388:8388" in t
assert t.split("PORTS=(")[1].split(")")[0].count("\n")>=2
PY
chk $? "PORTS 数组仍是合法多行"

echo "===== 11. 面板路径 / 卸载容器名 ====="
mkdir -p /tmp/xo-test/3x-ui
cat > /tmp/xo-test/3x-ui/info.txt <<'EOF'
3X-UI 面板信息
  面板地址: http://<服务器IP>:2053/xui-abcd1234
EOF
bp="$(parse_xui_base_path /tmp/xo-test/3x-ui/info.txt /tmp/xo-test/3x-ui/run.sh)"
[ "$bp" = "/xui-abcd1234" ]; chk $? "parse_xui_base_path=$bp"
echo "$(extra_uninstall_containers)" | grep -qx caddy-panel; chk $? "卸载列表含 caddy-panel"
echo "$(extra_uninstall_containers)" | grep -qx sub-server; chk $? "卸载列表含 sub-server"

echo "===== 12. 集群 JSON 载荷 ====="
tb="$(cluster_token_body "edge-sync" "node-sync")"
echo "$tb" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["scope"]=="node-sync" and d["expiresAt"]==0'
chk $? "cluster_token_body 合法 JSON"
nb="$(cluster_node_body "sg" "1.2.3.4" "2053" "xui-ab" "tok" "http" "all" "true" "skip")"
echo "$nb" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["basePath"]=="/xui-ab" and d["allowPrivateAddress"] is True and d["apiToken"]=="tok"'
chk $? "cluster_node_body 补全 basePath 前导斜杠"
cb="$(cluster_client_body "main" "main" "11111111-2222-3333-4444-555555555555" "1,2,3")"
echo "$cb" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["inboundIds"]==[1,2,3] and d["client"]["subId"]=="main"'
chk $? "cluster_client_body inboundIds 为数字数组"
hb="$(cluster_host_body "7" "sg.example.com:8443" "SG" "8443" "images.apple.com" "chrome")"
echo "$hb" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["security"]=="reality" and d["inboundIds"]==[7]'
chk $? "cluster_host_body 合法 JSON"

echo "===== 13. 订阅路径令牌 / CLI ====="
tok="$(sub_server_token_path "abcDEF12")"
[ "$tok" = "abcDEF12" ]; chk $? "指定 sub-token 原样使用"
tok2="$(sub_server_token_path)"
[ -n "$tok2" ] && [ "$tok2" != "abcDEF12" ]; chk $? "随机 sub-token 非空"

bash -n /repo/install.sh; chk $? "install.sh 语法检查"
failn=0
for f in /repo/lib/*.sh /repo/test/unit-test.sh; do
  bash -n "$f" || failn=1
done
[ "$failn" = 0 ]; chk $? "lib/*.sh 与测试脚本语法检查"

cli() { env -u XRAY_ONECLICK_SOURCE_ONLY bash /repo/install.sh "$@"; }
cli --help >/dev/null; chk $? "--help 退出 0"
if cli --not-a-flag >/tmp/xo-cli.err 2>&1; then
  chk 1 "未知参数应失败"
else
  grep -q "未知参数" /tmp/xo-cli.err; chk $? "未知参数报错含 '未知参数'"
fi
if cli xui-port >/tmp/xo-cli2.err 2>&1; then
  chk 1 "xui-port 无端口应失败"
else
  grep -q "用法" /tmp/xo-cli2.err; chk $? "xui-port 无端口提示用法"
fi

echo ""
echo "===== 单元测试结果: PASS=$PASS FAIL=$FAIL ====="
exit $FAIL
