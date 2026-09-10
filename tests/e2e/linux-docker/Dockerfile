# Runtime image for Linux Docker E2E.
# Intentionally Zig-free: the new compile path embeds the runtime WASM at
# CLI build time, so end users do NOT need Zig installed. We assert this
# inside the container as part of the test (see container-e2e.sh).

ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

# Copy the host-built circ-compile ELF and the test artifacts into the image.
# Everything the container needs is baked in — no volume mounts required.
COPY circ-compile /usr/local/bin/circ-compile
COPY inverter.circ /test/inverter.circ
COPY drive-inverter.mjs /test/drive-inverter.mjs
COPY libcirc.wasm /test/libcirc.wasm
COPY drive-libcirc.mjs /test/drive-libcirc.mjs
COPY container-e2e.sh /test/container-e2e.sh

RUN chmod +x /usr/local/bin/circ-compile /test/container-e2e.sh

WORKDIR /test
CMD ["bash", "/test/container-e2e.sh"]
