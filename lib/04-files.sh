ensure_base_files() {
  mkdir -p "$INSTALL_DIR/conf" "$INSTALL_DIR/rules" "$INSTALL_DIR/nodes" \
           "$INSTALL_DIR/3x-ui/db" "$INSTALL_DIR/3x-ui/cert" "$INSTALL_DIR/3x-ui/acme" \
           "$INSTALL_DIR/lib"

  if [ -f "$SCRIPT_DIR/install.sh" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/install.sh" 2>/dev/null || true
  fi
  if [ -d "$SCRIPT_DIR/lib" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -f "$SCRIPT_DIR/lib/"*.sh "$INSTALL_DIR/lib/" 2>/dev/null || true
  fi
  if [ -d "$SCRIPT_DIR/conf" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -f "$SCRIPT_DIR/conf/"*.conf "$SCRIPT_DIR/conf/"*.json "$INSTALL_DIR/conf/" 2>/dev/null || true
  fi

  if [ ! -f "$TEMPLATE_JSON" ]; then
    if [ -f "$SCRIPT_DIR/conf/xray-config.template.json" ]; then
      cp -f "$SCRIPT_DIR/conf/xray-config.template.json" "$TEMPLATE_JSON"
    else
      die "配置文件模板缺失: $SCRIPT_DIR/conf/xray-config.template.json (请从完整仓库安装)"
    fi
  fi

  if [ ! -f "$SYSCTL_CONF" ] && [ -f "$SCRIPT_DIR/conf/sysctl-xray.conf" ]; then
    cp -f "$SCRIPT_DIR/conf/sysctl-xray.conf" "$SYSCTL_CONF"
  fi
}
