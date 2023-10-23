ARG UBUNTU_RELEASE=mantic

FROM ubuntu:$UBUNTU_RELEASE AS build-stage
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git ca-certificates build-essential valac gettext libgtk-4-dev libadwaita-1-dev libgusb-dev meson

COPY . /

ARG BUILD_TYPE=release
ARG ENABLE_LTO=true
ARG TARGETOS TARGETARCH TARGETVARIANT

RUN meson setup \
      --fatal-meson-warnings \
      "--buildtype=${BUILD_TYPE}" \
      "-Db_lto=${ENABLE_LTO}" \
      --prefix=/usr \
      /build && \
    meson compile -C /build && \
    meson install --destdir=/release -C /build

RUN export "TARGETMACHINE=$(uname -m)" && \
    printenv | grep ^TARGET >>/release/.build-metadata.env

FROM scratch AS export-stage
COPY --from=build-stage /release/ /release/.build-metadata.env /
