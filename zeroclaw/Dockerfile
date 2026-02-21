ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG BUILD_ARCH

# 安装运行所需的基础小工具
RUN apk add --no-cache bash curl jq tzdata ca-certificates libc6-compat ttyd

# 神奇的一步：根据 HA 传入的 CPU 架构，直接从我们刚刚建立的 bin 文件夹复制编译好的程序！
COPY bin/${BUILD_ARCH}/zeroclaw /usr/bin/zeroclaw
RUN chmod +x /usr/bin/zeroclaw

COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]