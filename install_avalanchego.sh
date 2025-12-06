#!/bin/bash
# AvalancheGo v1.14.0+ 一键安装脚本（已兼容新文件名）
set -e

VERSION="v1.14.0"
INSTALL_DIR="/root/avalanchego-${VERSION}"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="avalanchego"

echo "============================================================="
echo "   AvalancheGo ${VERSION} 一键安装脚本（已修复文件名问题）"
echo "============================================================="

# 下载
echo "[1/6] 正在下载 avalanchego ${VERSION} ..."
wget -q https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/avalanchego-linux-amd64-${VERSION}.tar.gz

# 解压
echo "[2/6] 正在解压..."
tar -xzf avalanchego-linux-amd64-${VERSION}.tar.gz
rm -f avalanchego-linux-amd64-${VERSION}.tar.gz

# 自动识别解压后真实的目录名（兼容新老两种命名）
EXTRACTED_DIR=$(tar -tzf avalanchego-linux-amd64-${VERSION}.tar.gz | head -1 | cut -f1 -d"/" | uniq)
echo "检测到解压目录：$EXTRACTED_DIR"

# 删除旧的安装目录（如果存在）
[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"

# 移动到目标目录
mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# 安装二进制文件
echo "[3/6] 安装二进制文件..."
cp "${INSTALL_DIR}/avalanchego" "$BIN_DIR/"
mkdir -p "$BIN_DIR/plugins"
cp "${INSTALL_DIR}/plugins/"* "$BIN_DIR/plugins/" 2>/dev/null || true

# 创建 systemd 服务
echo "[4/6] 创建 systemd 服务..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=AvalancheGo ${VERSION}
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_DIR}/avalanchego --http-port=9650
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}

# 启动
echo "[5/6] 启动服务..."
systemctl restart ${SERVICE_NAME}

# 等待节点就绪并显示信息
echo "等待节点启动（最多 60 秒）..."
for i in {1..60}; do
    if curl -s 127.0.0.1:9650/ext/info >/dev/null 2>&1; then
        echo -e "\n节点已就绪！\n"
        curl -s -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | \
            python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print('NodeID         :', r['nodeID']); print('BLS 公钥       :', r['nodePOP']['publicKey']); print('BLS 签名(PoP)  :', r['nodePOP']['proofOfPossession'])"
        echo -e "\n安装完成！常用命令："
        echo "查看状态： systemctl status avalanchego"
        echo "查看日志： journalctl -u avalanchego -f"
        echo "重启节点： systemctl restart avalanchego"
        echo -e "\n重要：重装系统请务必备份 /root/.avalanchego 目录！\n"
        exit 0
    fi
    sleep 1
done

echo "超时：节点启动失败，请用 journalctl -u avalanchego -f 查看日志"
