# syntax=docker/dockerfile:1

ARG BUILD_IMAGE=debian:trixie@sha256:913f6706df59a68922d1dd08f78c2476560a8d367897200a6005b00e5f67c2d5
ARG RUNTIME_IMAGE=gcr.io/distroless/cc-debian13:nonroot@sha256:e792ab3d241a468a4fd7519ddbbebe66b49b5f365771716ea688ad40b6c6f1c2

# Images are digest-pinned through ARGs, which hadolint cannot resolve.
# hadolint ignore=DL3006
FROM ${RUNTIME_IMAGE} AS runtime-base

# hadolint ignore=DL3006
FROM ${BUILD_IMAGE} AS build

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Pin the commit SHA for integrity
ARG FLEXISIP_VERSION=2.6.2
ARG FLEXISIP_COMMIT=68ba0e8a51227acbb7e88f2d2f90fb2afee5bee4

ENV PREFIX=/opt/belledonne-communications
ENV DEBIAN_FRONTEND=noninteractive

# Keep downloaded .deb files in the apt cache mount instead of deleting them.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
 && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Packages are deliberately unpinned to pick up security fixes on rebuild.
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      ccache \
      cmake \
      g++ \
      git \
      nasm \
      ninja-build \
      pkgconf \
      python3 \
      libnghttp2-dev \
      libssl-dev

RUN git clone --quiet --depth 1 --branch "${FLEXISIP_VERSION}" \
      https://gitlab.linphone.org/BC/public/flexisip.git /src \
 && test "$(git -C /src rev-parse HEAD)" = "${FLEXISIP_COMMIT}" \
 && git -C /src submodule --quiet update --init --recursive --depth 1 \
 # linphone-sdk derives its version from `git describe`, which needs its tags.
 # Without --no-recurse-submodules, fetch would lazily download every tree
 # one request at a time to look for submodule changes.
 && git -C /src/linphone-sdk fetch --quiet --no-recurse-submodules \
      --filter=tree:0 --unshallow --tags origin

# Only the SIP proxy core is built
RUN --mount=type=cache,target=/root/.cache/ccache \
    hardening='-D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection'; \
    if [ "$(dpkg --print-architecture)" = amd64 ]; then hardening="$hardening -fcf-protection"; fi; \
    export CFLAGS="$hardening" CXXFLAGS="$hardening" LDFLAGS='-Wl,-z,relro -Wl,-z,now'; \
    cmake -S /src -B /build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DSYSCONF_INSTALL_DIR=/etc \
      -DENABLE_STRICT=OFF \
      -DENABLE_SYSTEMD=OFF \
      -DENABLE_PRESENCE=OFF \
      -DENABLE_REDIS=OFF \
      -DENABLE_SNMP=OFF \
      -DENABLE_SOCI=OFF \
      -DENABLE_TRANSCODER=OFF \
      -DENABLE_MDNS=OFF \
      -DENABLE_OPENID_CONNECT=OFF \
      -DENABLE_EXTERNAL_AUTH_PLUGIN=OFF \
      -DENABLE_VOICEMAIL=OFF \
      -DENABLE_UNIT_TESTS=OFF; \
    cmake --build /build; \
    cmake --install /build --strip

COPY --from=runtime-base / /runtime-base

# Stage only the binary, the libraries it loads that the runtime base lacks,
# and the belr grammars (needed by the file-based authentication backend).
RUN install -D -m 0755 "${PREFIX}/bin/flexisip" "/rootfs${PREFIX}/bin/flexisip"; \
    install -d "/rootfs${PREFIX}/share"; \
    cp -a "${PREFIX}/share/belr" "/rootfs${PREFIX}/share/"; \
    ldd "${PREFIX}/bin/flexisip" | awk '$2 == "=>" { print $3 }' | while read -r lib; do \
      [ -e "/runtime-base${lib}" ] && continue; \
      # /lib is a symlink to /usr/lib in the runtime base: never create it as a directory.
      case "$lib" in /lib/*) dest="/usr${lib}" ;; *) dest="$lib" ;; esac; \
      install -D -m 0644 "$(readlink -f "$lib")" "/rootfs${dest}"; \
    done

FROM runtime-base

COPY --link --from=build /rootfs/ /

ENTRYPOINT ["/opt/belledonne-communications/bin/flexisip"]
CMD ["--server", "proxy"]
