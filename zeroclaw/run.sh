#!/command/with-contenv bashio
set -euo pipefail

# ==========================================
# 1. 持久化护城河 (将容器数据映射到 HA 配置目录)
# ==========================================
if [ ! -e /data ]; then
  ln -s /config /data || true
fi

export HOME="/config"
export XDG_CONFIG_HOME="/config"
export ZEROCLAW_CONFIG_DIR="/config/.zeroclaw"
export ZEROCLAW_WORKSPACE_DIR="/config/zeroclaw_workspace"

# 确保目录存在
mkdir -p "$ZEROCLAW_CONFIG_DIR" "$ZEROCLAW_WORKSPACE_DIR"

CONFIG_FILE="$ZEROCLAW_CONFIG_DIR/config.toml"
ENV_FILE="$ZEROCLAW_CONFIG_DIR/.env"
OPTIONS_FILE="/data/options.json"

# 从 HA 插件界面读取基础参数
PROVIDER=$(jq -r '.provider // "nvidia"' "$OPTIONS_FILE")
API_KEY=$(jq -r '.api_key // empty' "$OPTIONS_FILE")
PORT=$(jq -r '.port // 8080' "$OPTIONS_FILE")
DEBUG=$(jq -r '.debug_mode // false' "$OPTIONS_FILE")

# ==========================================
# 2. 非破坏性引导 (保护你的飞书和多模型配置)
# ==========================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "INFO: config.toml missing; bootstrapping minimal config..."
    echo "[gateway]" > "$CONFIG_FILE"
    echo "port = ${PORT}" >> "$CONFIG_FILE"
    echo "default_provider = \"${PROVIDER}\"" >> "$CONFIG_FILE"
    echo "default_temperature = 0.7" >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "INFO: Bootstrap complete. Future changes via CLI/Web will persist."
else
    echo "INFO: Found existing config.toml. We will NOT overwrite it."
    # 微创补丁：防止旧文件缺少温度参数导致崩溃
    if ! grep -q "default_temperature" "$CONFIG_FILE"; then
        echo "WARN: Patching missing default_temperature safely..."
        sed -i '/\[gateway\]/a default_temperature = 0.7' "$CONFIG_FILE"
    fi
    chmod 600 "$CONFIG_FILE" || true
fi

# ==========================================
# 3. 动态注入密钥 (绝对安全的本地 .env 方案)
# ==========================================
# A. 优先读取 Home Assistant UI 界面里填写的 API_KEY (备用选项)
if [ -n "$API_KEY" ]; then
    if [ "$PROVIDER" = "groq" ]; then
        export GROQ_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "anthropic" ]; then
        export ANTHROPIC_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "openai" ]; then
        export OPENAI_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "openrouter" ]; then
        export OPENROUTER_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "nvidia" ]; then
        export NVIDIA_API_KEY="$API_KEY"
    elif [ "$PROVIDER" = "xai" ]; then
        export XAI_API_KEY="$API_KEY"
    fi
fi

# B. 🌟 核心魔法：读取本地硬盘上的 .env 隐藏文件，加载你的多模型武器库
if [ -f "$ENV_FILE" ]; then
    echo "INFO: Loading secret environment variables from $ENV_FILE"
    # set -a 允许将 source 进来的所有变量自动 export 成全局环境变量
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "WARN: No .env file found at $ENV_FILE. Multi-model auto-keys skipped."
fi

# 日志级别控制
if [ "$DEBUG" = "true" ]; then
    export RUST_LOG="debug"
else
    export RUST_LOG="info"
fi

# ==========================================
# 4. 后台引擎三开与优雅停机
# ==========================================
# 捕获停止信号，确保容器关闭时能安全退出所有进程
shutdown() {
  echo "INFO: Shutdown requested..."
  kill -TERM "$GW_PID" 2>/dev/null || true
  kill -TERM "$CHAN_PID" 2>/dev/null || true
  kill -TERM "$TTYD_PID" 2>/dev/null || true
  wait "$GW_PID" "$CHAN_PID" "$TTYD_PID" 2>/dev/null || true
  exit 0
}
trap shutdown INT TERM

cd "$ZEROCLAW_WORKSPACE_DIR"

echo "🚀 Starting ZeroClaw Gateway on port ${PORT}..."
/usr/bin/zeroclaw gateway --port "${PORT}" &
GW_PID=$!

echo "📡 Starting ZeroClaw Channels (Lark, etc.)..."
/usr/bin/zeroclaw channel start &
CHAN_PID=$!

echo "💻 Starting Web Terminal (ttyd) on port 8099..."
ttyd -W -p 8099 bash &
TTYD_PID=$!

# 挂起主进程，维持容器运行
wait -n "$GW_PID" "$CHAN_PID" "$TTYD_PID"