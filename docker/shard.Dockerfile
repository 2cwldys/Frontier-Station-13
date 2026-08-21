# Frontier Station 13 -- shard runtime image.
#
# Runtime ONLY -- no compiler, no bun/tgui toolchain. A shard runs the
# EXACT already-compiled code from the host's own checkout (bind-mounted
# read-only at /aurora at `docker run` time -- see db_central_add_shard.*),
# so this image only needs what DreamDaemon itself needs to execute an
# already-built aurorastation.dmb.
#
# Every step here is lifted directly from this repo's own tested, working
# CI pipeline (.github/workflows/byond.yml, tools/ci/install_byond.sh,
# tools/ci/install_rust_g.sh) -- not invented from scratch. Target is
# 32-bit x86 Linux (confirmed by tools/ci/libbapi_ci.so's ELF header and
# the rust_g build scripts' i686-unknown-linux-gnu target), so i386
# multilib support is required even though the host is normally amd64.
#
# BYOND version MUST match dependencies.sh's BYOND_MAJOR/BYOND_MINOR and
# config/config.txt's enforced MIN_CLIENT_BUILD -- if that ever changes,
# update the two ARGs below to match (see scripts/set_byond_version.py,
# which already tracks every other file that needs to agree on this).

FROM ubuntu:24.04

ARG BYOND_MAJOR=516
ARG BYOND_MINOR=1687
ARG RUST_G_VERSION=v3.1.0+a1

# mariadb-client (mysqldump/mysqladmin) -- NOT the Docker CLI, deliberately
# never installed here (a shard's container has no business reaching other
# containers via Docker). This is only for scripts/central/
# shard_backup_self.sh, which backs up this shard's own local DB by
# connecting straight over the network to its sibling DB container, the same
# way the game itself already does via config/dbconfig.txt.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl unzip make \
        gcc-multilib zlib1g-dev:i386 libssl-dev:i386 libgcc-s1:i386 libc6:i386 \
        libcurl4t64 libcurl4t64:i386 \
        mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# BYOND itself -- same sequence as tools/ci/install_byond.sh: download the
# official Linux build zip, `make here` (BYOND's own Linux installer).
RUN mkdir -p /root/BYOND && cd /root/BYOND && \
    curl -fsSL "http://www.byond.com/download/build/${BYOND_MAJOR}/${BYOND_MAJOR}.${BYOND_MINOR}_byond_linux.zip" \
        -o byond.zip -H "User-Agent: Mozilla/5.0" && \
    unzip -q byond.zip && rm byond.zip && \
    cd byond && make here

ENV PATH="/root/BYOND/byond/bin:${PATH}"
ENV LD_LIBRARY_PATH="/root/BYOND/byond/bin:/usr/local/lib:${LD_LIBRARY_PATH}"

# rust_g -- prebuilt release asset, same as tools/ci/install_rust_g.sh,
# installed to ~/.byond/bin/ (one of the paths code/__DEFINES/rust_g.dm's
# own Linux auto-detection already checks -- no DM-side changes needed).
RUN mkdir -p /root/.byond/bin && \
    curl -fsSL -o /root/.byond/bin/librust_g.so \
        "https://github.com/Aurorastation/rust-g/releases/download/${RUST_G_VERSION}/librust_g.so" && \
    chmod +x /root/.byond/bin/librust_g.so && \
    ldd /root/.byond/bin/librust_g.so

# The actual game files (aurorastation.dmb, config/, data/, resources) are
# bind-mounted in at `docker run` time, not baked into this image -- see
# db_central_add_shard.ps1/.sh. This is deliberate: a shard always runs
# whatever's currently compiled on the host, never a stale copy frozen at
# image-build time.
WORKDIR /aurora

# ShardId, port, and -trusted are supplied as CMD args by db_central_add_shard.*
# (`docker run ... aurora-shard-runtime:latest aurorastation.dmb <port> -trusted`)
# -- ENTRYPOINT only fixes WHICH binary runs.
ENTRYPOINT ["DreamDaemon"]
