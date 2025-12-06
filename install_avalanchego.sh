#!/bin/bash
# AvalancheGo v1.14.0 一键安装脚本 - 终极稳妥版
set -e

VERSION="v1.14.0"
TARBALL="avalanchego-linux-amd64-${VERSION}.tar.gz"
INSTALL_DIR="/root/avalanchego-${VERSION}"
BIN_DIR="/usr/local/bin"
SERVICE_NAME="avalanchego"

echo "============================================================="
echo "   AvalancheGo ${VERSION} 一键安装 - 终极稳妥版"
echo "============================================================="

# 1. 下载（如果已经下了就跳过）
if [ ! -f "$TARBALL" ]; then
    echo "[1/6] 正在下载 $TARBALL ..."
    wget -q https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/${TARBALL}
else
    echo "[1/6] 检测到已下载 $TARBALL，跳过下载"
fi

# 2. 先预读压缩包里最顶层的目录名（不解压也能读）
echo "[2/6] 正在读取压缩包内的目录名..."
EXTRACTED_DIR=$(tar -tf "$TARBALL" | head -1 | cut -f1 -d"/")
echo "    → 压缩包内目录为: $EXTRACTED_DIR"

# 3. 解压
echo "[3/6] 正在解压..."
tar -xzf "$TARBALL"

# 4. 移动（现在一定找得到）
echo "[4/6] 移动到 $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mv "$EXTRACTED_DIR" "$INSTALL_DIR"

# 5. 安装二进制
echo "[5/6] 安装二进制文件..."
cp "$INSTALL_DIR/avalanchego" "$BIN_DIR/"
mkdir -p "$BIN_DIR/plugins"
cp "$INSTALL_DIR/plugins/"* "$BIN_DIR/plugins/" 2>/dev/null || true

# 6. 创建 systemd 服务并启动
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
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE_NAME} >/dev/null

# 7. 等待并显示 NodeID
echo "等待节点启动（最多 60 秒）..."
for i in {1..60}; do
    if curl -s 127.0.0.1:9650/ext/info >/dev/null 2>&1; then
        echo -e "\n节点启动成功！你的节点信息："
        curl -s -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' \
             -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | \
             python3 -c "import sys,json; r=json.load(sys.stdin)['result']; \
             print('NodeID        :', r['nodeID']); \
             print('BLS 公钥      :', r['nodePOP']['publicKey']); \
             print('BLS 签名(PoP) :', r['nodePOP']['proofOfPossession'])"
        echo -e "\n全部完成！常用命令："
        echo "journalctl -u avalanchego -f"
        echo "systemctl restart avalanchego"
        echo -e "\n重装系统记得备份 /root/.avalanchego\n"
        exit 0
    fi
    sleep 1
done

echo "60 秒内未检测到节点启动，请查看日志：journalctl -u avalanchego -f"
