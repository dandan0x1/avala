#!/bin/bash
# 修复版：自动检测解压目录名
set -e

VERSION="v1.14.0"
INSTALL_DIR="/root/avalanchego-${VERSION}"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="avalanchego"
TARBALL="avalanchego-linux-amd64-${VERSION}.tar.gz"

echo "============================================================="
echo "   AvalancheGo ${VERSION} 一键安装（自动检测目录）"
echo "============================================================="

# 如果 tar.gz 不存在，先下载
[ ! -f "$TARBALL" ] && wget -q https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/$TARBALL

# 解压
echo "[1/5] 解压..."
tar -xzf $TARBALL
rm -f $TARBALL

# 自动找解压出的目录（兼容 avalanchego-v1.14.0 或 avalanchego-linux-amd64-v1.14.0）
EXTRACTED_DIR=$(ls -d avalanchego-* 2>/dev/null | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "错误：未找到解压目录！"
    exit 1
fi
echo "检测到目录：$EXTRACTED_DIR"

# 移动
[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# 安装二进制
echo "[2/5] 安装二进制..."
cp "${INSTALL_DIR}/avalanchego" "$BIN_DIR/"
mkdir -p "$BIN_DIR/plugins"
cp "${INSTALL_DIR}/plugins/"* "$BIN_DIR/plugins/" 2>/dev/null || true

# 服务文件
echo "[3/5] 创建服务..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=AvalancheGo ${VERSION}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_DIR}/avalanchego --http-port=9650
Restart=always
RestartSec=5
LimitNOFILE=65536
Environment="AVALANCHE_DATA_DIR=/root/.avalanchego"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}

# 启动
echo "[4/5] 启动..."
systemctl start ${SERVICE_NAME}

# 等待并显示信息
echo "[5/5] 等待节点就绪..."
for i in {1..60}; do
    if curl -s 127.0.0.1:9650/ext/info >/dev/null 2>&1; then
        echo -e "\n✅ 节点启动成功！你的信息："
        curl -s -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | \
        python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(f'NodeID         : {r[\"nodeID\"]}'); print(f'BLS 公钥       : {r[\"nodePOP\"][\"publicKey\"]}'); print(f'BLS 签名(PoP)  : {r[\"nodePOP\"][\"proofOfPossession\"]}')"
        echo -e "\n📋 常用命令："
        echo "状态： systemctl status $SERVICE_NAME"
        echo "日志： journalctl -u $SERVICE_NAME -f"
        echo "重启： systemctl restart $SERVICE_NAME"
        echo -e "\n⚠️  备份提醒：/root/.avalanchego （节点身份 + 数据）\n"
        exit 0
    fi
    sleep 1
    [ $i -eq 60 ] && echo "❌ 启动超时，检查日志：journalctl -u $SERVICE_NAME"
done
