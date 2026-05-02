# Node + Zig for wasm orchestration (`circ-compile` shells out to `zig build wasm`).
# Host supplies the Linux ELF `circ-compile` binary (mounted at runtime).

FROM node:22-bookworm-slim

ARG ZIG_VERSION=0.15.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils bash \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux \
    && curl -fsSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && tar -xf /tmp/zig.tar.xz -C /opt \
    && ln -sf "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

RUN zig version
