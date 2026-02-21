#!/command/with-contenv bashio
set -euo pipefail

# 1. 检查 Home Assistant 插件配置文件
OPTIONS_FILE="/data/options.json"
if [ ! -f "$OPTIONS_FILE" ]; then
  echo "ERROR: Missing $OPTIONS_FILE (add-on options)."
  exit 1
fi

# 2. 读取用户在 HA 界面填写的配置
PROVIDER=$(jq --raw-output '.provider // "anthropic"' "$OPTIONS_FILE")
API_KEY=$(jq --raw-output '.api_key // empty' "$OPTIONS_FILE")
PORT=$(jq --raw-output '.port // 8080' "$OPTIONS_FILE")
DEBUG=$(jq --raw-output '.debug_mode // false' "$OPTIONS_FILE")

# 3. 数据持久化目录映射
# Home Assistant 会将 /config 映射到宿主机的物理目录
export XDG_CONFIG_HOME="/config"
export ZEROCLAW_CONFIG_DIR="/config/.zeroclaw"
export ZEROCLAW_WORKSPACE_DIR="/config/zeroclaw_workspace"

# 确保持久化目录存在
mkdir -p "$ZEROCLAW_CONFIG_DIR" "$ZEROCLAW_WORKSPACE_DIR"

# 4. 配置环境变量
# 根据选择的模型供应商注入 API Key
if [ -n "$API_KEY" ]; then
    if [ "$PROVIDER" = "groq" ]; then
        export GROQ_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "anthropic" ]; then
        export ANTHROPIC_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "openai" ]; then
        export OPENAI_API_KEY="$API_KEY"
    fi
else
    echo "WARN: No API Key provided in add-on configuration."
fi

# 设置日志级别
if [ "$DEBUG" = "true" ]; then
    export RUST_LOG="debug"
    echo "INFO: Debug mode enabled."
else
    export RUST_LOG="info"
fi

# 5. 优雅关机处理 (捕获终止信号)
shutdown() {
  echo "INFO: Shutdown requested; stopping ZeroClaw..."
  if [ -n "${GW_PID:-}" ] && kill -0 "${GW_PID}" >/dev/null 2>&1; then
    kill -TERM "${GW_PID}" >/dev/null 2>&1 || true
    wait "${GW_PID}" || true
  fi
  echo "INFO: ZeroClaw stopped gracefully."
  exit 0
}
trap shutdown INT TERM

# 6. 启动 ZeroClaw 守护进程
echo "🚀 Starting ZeroClaw (Provider: ${PROVIDER}) on port ${PORT}..."

# 切换工作目录到持久化空间，确保产生的任何 SQLite/本地日志不丢失
cd "$ZEROCLAW_WORKSPACE_DIR"

# 启动 ZeroClaw 守护进程 (网关模式)
echo "🚀 Starting ZeroClaw (Provider: ${PROVIDER}) on port ${PORT}..."
/usr/bin/zeroclaw gateway --port "${PORT}" &
GW_PID=$!

# 启动网页终端 (ttyd)
# -W 允许写入操作，监听 8099 端口，打开 bash 命令行
echo "💻 Starting Web Terminal on port 8099..."
ttyd -W -p 8099 bash &
TTYD_PID=$!

# 捕获终止信号，优雅关机
shutdown() {
  echo "INFO: Shutdown requested; stopping services..."
  kill -TERM "$GW_PID" 2>/dev/null || true
  kill -TERM "$TTYD_PID" 2>/dev/null || true
  wait "$GW_PID" "$TTYD_PID" 2>/dev/null || true
  exit 0
}
trap shutdown INT TERM

# 等待进程，保持容器持续运行
wait -n "$GW_PID" "$TTYD_PID"