ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG BUILD_ARCH

# 安装运行所需的基础工具
# 1. 补齐 git，让 AI 能管理代码和技能
# 2. 补齐 openssh-client，用于身份验证
# 3. 保留 libc6-compat 确保 Rust 编译的二进制文件兼容性
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tzdata \
    ca-certificates \
    libc6-compat \
    ttyd \
    git \
    openssh-client

# 从我们刚刚在 CI 中组装好的 bin 文件夹复制程序
COPY bin/${BUILD_ARCH}/zeroclaw /usr/bin/zeroclaw
RUN chmod +x /usr/bin/zeroclaw

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]