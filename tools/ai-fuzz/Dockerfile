FROM debian:bookworm-slim

ARG OMOHI_REPO=hirotoyoshidome/omohi
ARG OMOHI_RELEASE=latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends bash ca-certificates coreutils curl findutils gawk grep sed tar xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY tools/ai-fuzz/container_runner.sh /opt/omohi-ai-fuzz/container_runner.sh
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
        amd64) asset_arch="x86_64" ;; \
        arm64) asset_arch="arm64" ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && asset_suffix="linux-${asset_arch}.tar.gz" \
    && if [ "${OMOHI_RELEASE}" = "latest" ]; then \
         release_json="$(curl -fsSL "https://api.github.com/repos/${OMOHI_REPO}/releases/latest")"; \
       else \
         release_json="$(curl -fsSL "https://api.github.com/repos/${OMOHI_REPO}/releases/tags/${OMOHI_RELEASE}")"; \
       fi \
    && asset_url="$(printf '%s\n' "${release_json}" | grep -F '"browser_download_url"' | grep -F "${asset_suffix}\"" | head -n 1 | cut -d '"' -f 4)" \
    && checksum_url="$(printf '%s\n' "${release_json}" | grep -F '"browser_download_url"' | grep -F "${asset_suffix}.sha256\"" | head -n 1 | cut -d '"' -f 4)" \
    && if [ -z "${asset_url}" ]; then \
         echo "release asset not found for ${asset_suffix}" >&2; \
         exit 1; \
       fi \
    && curl -fsSL "${asset_url}" -o /tmp/omohi.tar.gz \
    && if [ -n "${checksum_url}" ]; then \
         curl -fsSL "${checksum_url}" -o /tmp/omohi.tar.gz.sha256; \
         checksum_expected="$(awk '{ print $1 }' /tmp/omohi.tar.gz.sha256)"; \
         checksum_actual="$(sha256sum /tmp/omohi.tar.gz | awk '{ print $1 }')"; \
         [ "${checksum_expected}" = "${checksum_actual}" ]; \
       fi \
    && tar -xzf /tmp/omohi.tar.gz -C /tmp \
    && install -m 755 /tmp/omohi /usr/local/bin/omohi \
    && rm -rf /tmp/omohi /tmp/share /tmp/omohi.tar.gz /tmp/omohi.tar.gz.sha256

RUN chmod 755 /usr/local/bin/omohi /opt/omohi-ai-fuzz/container_runner.sh

ENTRYPOINT ["/opt/omohi-ai-fuzz/container_runner.sh"]
