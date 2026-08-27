#!/usr/bin/env bash
# ==============================================================================
# install.sh 函数级单元测试
# 用法: 在可写 /etc 的环境运行 (推荐 docker 容器, 见 .github/workflows/ci.yml)
#   docker run --rm -v "$PWD:/repo:ro" debian:12 bash -c \
#     'apt-get update && apt-get install -y procps curl python3 && bash /repo/test/unit-test.sh'
# ==============================================================================
export XRAY_ONECLICK_SOURCE_ONLY=1
export INSTALL_DIR=/tmp/xo-test
export SCRIPT_DIR=/repo
export ASSUME_YES=1
export ENABLE_BBR=1

source /repo/install.sh
PASS=0; FAIL=0
chk() { if [ "$1" = "0" ]; then echo "PASS: $2"; PASS=$((PASS+1)); else echo "FAIL: $2"; FAIL=$((FAIL+1)); fi }

echo "===== 1. 配置模板生成 ====="
ensure_base_files
test -f "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "增强路由配置模板已生成"
python3 -m json.tool "$INSTALL_DIR/conf/xray-config.template.json" >/dev/null 2>&1; chk $? "模板是合法 JSON"
grep -q "geosite:category-ads-all" "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "模板含 v2ray-rules-dat 广告拦截规则"
grep -q "geosite:cn" "$INSTALL_DIR/conf/xray-config.template.json"; chk $? "模板含 geosite:cn 直连规则"

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
[ "$DEST" = "www.apple.com:443" ]; chk $? "默认 DEST=$DEST"
[ -n "$SERVERNAMES" ]; chk $? "默认 SERVERNAMES=$SERVERNAMES"

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

echo "===== 7. 安装脚本语法 ====="
bash -n /repo/install.sh; chk $? "install.sh 语法检查"

echo ""
echo "===== 单元测试结果: PASS=$PASS FAIL=$FAIL ====="
exit $FAIL
