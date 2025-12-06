#!/bin/bash

# Avalanche Go 一键安装脚本
# 版本: v1.14.0

set -e

VERSION="v1.14.0"
DOWNLOAD_URL="https://github.com/ava-labs/avalanchego/releases/download/${VERSION}/avalanchego-linux-amd64-${VERSION}.tar.gz"
INSTALL_DIR="/root/avalanchego-${VERSION}"
DATA_DIR="/root/.avalanchego"
SCREEN_NAME="avalanchego"
RPC_URL="127.0.0.1:9650"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检查必要工具
check_dependencies() {
    echo_info "检查必要工具..."
    
    if ! command -v wget &> /dev/null; then
        echo_info "安装 wget..."
        apt-get update && apt-get install -y wget || yum install -y wget
    fi
    
    if ! command -v screen &> /dev/null; then
        echo_info "安装 screen..."
        apt-get install -y screen || yum install -y screen
    fi
    
    if ! command -v curl &> /dev/null; then
        echo_info "安装 curl..."
        apt-get install -y curl || yum install -y curl
    fi
}

# 检查是否已有运行中的节点
check_existing_session() {
    if screen -list | grep -q "${SCREEN_NAME}"; then
        echo_warn "发现已存在的 screen session: ${SCREEN_NAME}"
        read -p "是否要停止并重新安装? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo_info "停止现有的 screen session..."
            screen -S ${SCREEN_NAME} -X quit 2>/dev/null || true
            sleep 2
        else
            echo_info "保留现有 session，退出安装"
            exit 0
        fi
    fi
}

# 下载并安装
download_and_install() {
    echo_info "开始下载 Avalanche Go ${VERSION}..."
    
    cd /root
    
    # 下载
    if [ -f "avalanchego-linux-amd64-${VERSION}.tar.gz" ]; then
        echo_warn "安装包已存在，跳过下载"
    else
        wget ${DOWNLOAD_URL}
        if [ $? -ne 0 ]; then
            echo_error "下载失败，请检查网络连接"
            exit 1
        fi
    fi
    
    # 解压
    echo_info "解压安装包..."
    tar -xzf avalanchego-linux-amd64-${VERSION}.tar.gz
    
    # 进入目录
    cd ${INSTALL_DIR}
    
    # 添加执行权限
    chmod +x avalanchego
    
    echo_info "安装完成！"
}

# 启动节点
start_node() {
    echo_info "启动 Avalanche Go 节点..."
    
    cd ${INSTALL_DIR}
    
    # 创建 screen session 并启动节点
    screen -dmS ${SCREEN_NAME} ./avalanchego
    
    echo_info "节点已在 screen session (${SCREEN_NAME}) 中启动"
    echo_info "使用以下命令查看节点运行状态:"
    echo "  screen -r ${SCREEN_NAME}"
    echo_info "退出 screen 按: Ctrl+A 然后按 D"
}

# 等待节点启动
wait_for_node() {
    echo_info "等待节点启动（最多等待60秒）..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' \
           -H 'content-type:application/json' \
           ${RPC_URL}/ext/info > /dev/null 2>&1; then
            echo_info "节点已启动！"
            sleep 2  # 再等待2秒确保完全就绪
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done
    
    echo
    echo_warn "节点启动超时，但可能仍在后台运行中"
    return 1
}

# 获取节点信息
get_node_info() {
    echo_info "获取节点信息..."
    echo
    
    local response=$(curl -s -X POST --data '{
        "jsonrpc":"2.0",
        "id":1,
        "method":"info.getNodeID"
    }' -H 'content-type:application/json' ${RPC_URL}/ext/info)
    
    if [ -z "$response" ] || echo "$response" | grep -q "error"; then
        echo_error "获取节点信息失败，节点可能还未完全启动"
        echo_warn "请稍后手动运行以下命令获取节点信息:"
        echo "curl -X POST --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"info.getNodeID\"}' -H 'content-type:application/json' ${RPC_URL}/ext/info"
        return 1
    fi
    
    # 解析并格式化输出
    local node_id=$(echo "$response" | grep -o '"nodeID": "[^"]*' | cut -d'"' -f4)
    local public_key=$(echo "$response" | grep -o '"publicKey": "[^"]*' | cut -d'"' -f4)
    local proof_of_possession=$(echo "$response" | grep -o '"proofOfPossession": "[^"]*' | cut -d'"' -f4)
    
    echo "=========================================="
    echo "节点信息："
    echo "=========================================="
    echo "nodeID (节点ID): ${node_id}"
    echo "BLS公钥 (publicKey): ${public_key}"
    echo "BLS签名 (proofOfPossession): ${proof_of_possession}"
    echo "=========================================="
    echo
    
    # 保存到文件
    echo "$response" > /root/node_info.json
    echo_info "完整节点信息已保存到: /root/node_info.json"
    
    # 显示备份提醒
    echo_warn "重要提醒: VPS重装或格式化数据时，请备份以下目录:"
    echo "  ${DATA_DIR}"
}

# 主函数
main() {
    echo "=========================================="
    echo "Avalanche Go 一键安装脚本"
    echo "版本: ${VERSION}"
    echo "=========================================="
    echo
    
    check_root
    check_dependencies
    check_existing_session
    download_and_install
    start_node
    
    # 等待节点启动
    wait_for_node
    
    # 获取节点信息
    get_node_info
    
    echo
    echo_info "安装完成！"
    echo_info "查看节点日志: screen -r ${SCREEN_NAME}"
    echo_info "停止节点: screen -S ${SCREEN_NAME} -X quit"
}

# 运行主函数
main

