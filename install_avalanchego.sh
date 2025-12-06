#!/bin/bash
# 一键安装 AvalancheGo v1.14.0 + 自动开机启动 + 完成后自动显示 NodeID 和 BLS 信息
# 作者：ChatGPT 2025版 😄

set -e

VERSION="v1.14.0"
INSTALL_DIR="/root/avalanchego-${VERSION}"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="avalanchego"

echo "============================================================="
echo "   AvalancheGo ${VERSION} 一键安装脚本"
echo "   适用于 Ubuntu 22.04 / 24.04"
echo "============================================================="

# 1. 下载并解压
echo "[1/6] 正在下载 avalanchego ${VERSION} ..."
wget https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/avalanchego-linux-amd64-${VERSION}.tar.gz

echo "[2/6] 正在解压..."
tar -xzf avalanchego-linux-amd64-${VERSION}.tar.gz
rm avalanchego-linux-amd64-${VERSION}.tar.gz

# 如果已经存在就删掉旧的
[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
mv avalanchego-linux-amd64-${VERSION} "$INSTALL_DIR"

# 2. 放入系统路径（方便直接调用）
echo "[3/6] 安装二进制文件到 $BIN_DIR ..."
cp "${INSTALL_DIR}/avalanchego" "$BIN_DIR/"
cp "${INSTALL_DIR}/plugins/"* "$BIN_DIR/" 2>/dev/null || true

# 3. 创建 systemd 服务（开机自启 + 自动重启）
echo "[4/6] 创建 systemd 服务..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=AvalancheGo Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_DIR}/avalanchego --http-port=9650
Restart=always
RestartSec=5
LimitNOFILE=65535

# 数据目录（重要！重装系统要备份这个目录）
Environment="AVALANCHE_DATA_DIR=/root/.avalanchego"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}

# 4. 启动服务
echo "[5/6] 启动 AvalancheGo 服务（首次启动需要几秒到几十秒同步时间）..."
systemctl start ${SERVICE_NAME}

# 等待节点完全启动（最多等 60 秒）
echo "等待节点启动..."
for i in {1..60}; do
    if curl -s 127.0.0.1:9650/ext/info > /dev/null 2>&1; then
        echo "节点已就绪！"
        break
    fi
    sleep 1
done

# 5. 获取并显示 NodeID 和 BLS 信息
echo "[6/6] 获取节点信息..."
sleep 2
curl -s -X POST --data '{
    "jsonrpc":"2.0",
    "id"     :1,
    "method" :"info.getNodeID"
}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | python3 -c "import sys,json; data=json.load(sys.stdin)['result']; print('\n你的节点信息（请妥善保存）：\n'); print('NodeID          : ' + data['nodeID']); print('BLS 公钥        : ' + data['nodePOP']['publicKey']); print('BLS 签名 (PoP)  : ' + data['nodePOP']['proofOfPossession']); print('')"

# 6. 完成提示
echo "============================================================="
echo "安装完成！"
echo "服务状态：     systemctl status ${SERVICE_NAME}"
echo "停止服务：     systemctl stop ${SERVICE_NAME}"
echo "重启服务：     systemctl restart ${SERVICE_NAME}"
echo "查看日志：     journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "重要提醒：VPS 重装系统或格式化数据盘时，务必备份以下目录："
echo "           /root/.avalanchego    （里面有你的节点身份和链上数据）"
echo "============================================================="
