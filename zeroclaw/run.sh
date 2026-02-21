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

mkdir -p "$ZEROCLAW_CONFIG_DIR" "$ZEROCLAW_WORKSPACE_DIR"

CONFIG_FILE="$ZEROCLAW_CONFIG_DIR/config.toml"
ENV_FILE="$ZEROCLAW_CONFIG_DIR/.env"
OPTIONS_FILE="/data/options.json"

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
    if ! grep -q "default_temperature" "$CONFIG_FILE"; then
        echo "WARN: Patching missing default_temperature safely..."
        sed -i '/\[gateway\]/a default_temperature = 0.7' "$CONFIG_FILE"
    fi
    chmod 600 "$CONFIG_FILE" || true
fi

# ==========================================
# 3. 动态注入密钥 (绝对安全的本地 .env 方案)
# ==========================================
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

if [ -f "$ENV_FILE" ]; then
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

# 🌟 核心升级：使用 daemon 模式。
# 它会自动拉起网关、频道和定时任务。
# 注意：一定要确保你的 build.yml 已经加上了 --all-features，
# 否则 daemon 发现配置了频道却找不到功能模块会直接报错退出。
echo "👹 Starting ZeroClaw Daemon (Gateway + Channels + Cron)..."
/usr/bin/zeroclaw daemon &
DAEMON_PID=$!

# 守护进程，任何一个退出则容器重启
wait -n "$DAEMON_PID" "$TTYD_PID"