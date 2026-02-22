#!/command/with-contenv bashio
set -euo pipefail

# ==========================================
# 1. 持久化护城河 & 目录初始化
# ==========================================
if [ ! -e /data ]; then
  ln -s /config /data || true
fi

export HOME="/config"
export XDG_CONFIG_HOME="/config"
export ZEROCLAW_CONFIG_DIR="/config/.zeroclaw"
export ZEROCLAW_WORKSPACE_DIR="/config/zeroclaw_workspace"

mkdir -p "$ZEROCLAW_CONFIG_DIR" "$ZEROCLAW_WORKSPACE_DIR"

CONFIG_FILE="$ZEROCLAW_CONFIG_DIR/config.toml"
ENV_FILE="$ZEROCLAW_CONFIG_DIR/.env"
OPTIONS_FILE="/data/options.json"

# 🌟 优化 3：加入防崩容错。如果 options.json 丢失，给定安全默认值
if [ -f "$OPTIONS_FILE" ]; then
    PROVIDER=$(jq -r '.provider // "nvidia"' "$OPTIONS_FILE" 2>/dev/null || echo "nvidia")
    API_KEY=$(jq -r '.api_key // empty' "$OPTIONS_FILE" 2>/dev/null || echo "")
    PORT=$(jq -r '.port // 8080' "$OPTIONS_FILE" 2>/dev/null || echo "8080")
    DEBUG=$(jq -r '.debug_mode // false' "$OPTIONS_FILE" 2>/dev/null || echo "false")
else
    PROVIDER="nvidia"; API_KEY=""; PORT="8080"; DEBUG="false"
fi

# ==========================================
# 2. 非破坏性引导 & 核心参数热同步
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
    echo "INFO: Found existing config.toml. We will NOT overwrite entire file."
    
    # 微创补丁：防止缺少温度参数
    if ! grep -q "default_temperature" "$CONFIG_FILE"; then
        echo "WARN: Patching missing default_temperature safely..."
        sed -i '/\[gateway\]/a default_temperature = 0.7' "$CONFIG_FILE"
    fi
    
    # 🌟 优化 1：强制同步 HA 端口。如果 HA 界面改了端口，这里自动修正底层的 config.toml
    if grep -q "^port = " "$CONFIG_FILE"; then
        sed -i "s/^port = .*/port = ${PORT}/" "$CONFIG_FILE"
    else
        sed -i '/\[gateway\]/a port = '"${PORT}" "$CONFIG_FILE"
    fi
    echo "INFO: Gateway port synced to ${PORT}."

    chmod 600 "$CONFIG_FILE" || true
fi

# ==========================================
# 3. 动态注入密钥 (本地 .env 安全沙箱)
# ==========================================
# 🌟 优化 2：使用优雅的 case 语句，扩展性更强，性能更好
if [ -n "$API_KEY" ]; then
    case "$PROVIDER" in
        groq)       export GROQ_API_KEY="$API_KEY" ;;
        anthropic)  export ANTHROPIC_API_KEY="$API_KEY" ;;
        openai)     export OPENAI_API_KEY="$API_KEY" ;;
        openrouter) export OPENROUTER_API_KEY="$API_KEY" ;;
        nvidia)     export NVIDIA_API_KEY="$API_KEY" ;;
        xai)        export XAI_API_KEY="$API_KEY" ;;
        *)          echo "WARN: Unknown provider '$PROVIDER' in options.json" ;;
    esac
fi

if [ -f "$ENV_FILE" ]; then
    # 🌟 优化 4：强制锁定密钥库权限，防止其他容器进程偷窥
    chmod 600 "$ENV_FILE" || true 
    echo "INFO: Loading secret environment variables from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "WARN: No .env file found at $ENV_FILE. Multi-model auto-keys skipped."
fi

if [ "$DEBUG" = "true" ]; then
    export RUST_LOG="debug"
else
    export RUST_LOG="info"
fi

# ==========================================
# 4. 后台引擎启动 (完全体 Daemon 模式)
# ==========================================
shutdown() {
  echo "INFO: Shutdown requested..."
  kill -TERM "$DAEMON_PID" 2>/dev/null || true
  kill -TERM "$TTYD_PID" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown INT TERM

cd "$ZEROCLAW_WORKSPACE_DIR"

echo "💻 Starting Web Terminal (ttyd) on port 8099..."
ttyd -W -p 8099 bash &
TTYD_PID=$!

echo "👹 Starting ZeroClaw Daemon (Gateway + Channels + Cron)..."
/usr/bin/zeroclaw daemon &
DAEMON_PID=$!

# 守护进程，任何一个退出则容器重启
wait -n "$DAEMON_PID" "$TTYD_PID"