#!/bin/bash
set -e

# 强制回到家目录，防止误操作
cd /root

VERSION="v1.14.0"
TARBALL="avalanchego-linux-amd64-${VERSION}.tar.gz"
INSTALL_DIR="/root/avalanchego-${VERSION}"
BIN_DIR="/usr/local/bin"

echo "开始安装 AvalancheGo ${VERSION}（强制在家目录操作）"

[ -f "$TARBALL" ] || wget -q https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/${TARBALL}

echo "读取压缩包内目录名..."
DIR_IN_TAR=$(tar -tf "$TARBALL" | head -1 | cut -f1 -d"/")
echo "即将解压出: $DIR_IN_TAR"

echo "解压中..."
tar -xzf "$TARBALL"

echo "移动 $DIR_IN_TAR → $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mv "$DIR_IN_TAR" "$INSTALL_DIR"

cp "$INSTALL_DIR/avalanchego" "$BIN_DIR/"
mkdir -p "$BIN_DIR/plugins" && cp "$INSTALL_DIR/plugins/"* "$BIN_DIR/plugins/" 2>/dev/null || true

cat > /etc/systemd/system/avalanchego.service <<EOF
[Unit]Description=AvalancheGo ${VERSION} After=network-online.target
[Service]Type=simple User=root WorkingDirectory=${INSTALL_DIR} ExecStart=${BIN_DIR}/avalanchego --http-port=9650 Restart=always RestartSec=3 LimitNOFILE=65536
[Install]WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now avalanchego >/dev/null

echo "等待节点启动..."
for i in {1..60}; do
    sleep 1
    if curl -s 127.0.0.1:9650/ext/info >/dev/null 2>&1; then
        echo -e "\n节点启动成功！你的信息如下："
        curl -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
        echo -e "\n备份目录：/root/.avalanchego\n"
        exit 0
    fi
done
echo "启动超时，请查看日志：journalctl -u avalanchego -f"
