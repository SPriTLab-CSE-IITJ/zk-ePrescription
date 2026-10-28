# =========================================================
# Stage 1: Build Circom 2.2.3
# =========================================================

FROM rust:1.96-bookworm AS circom-builder

ENV PATH="/usr/local/cargo/bin:${PATH}"

ARG CIRCOM_VERSION=2.2.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        build-essential \
        pkg-config \
        libssl-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
        --depth 1 \
        --branch "v${CIRCOM_VERSION}" \
        https://github.com/iden3/circom.git \
        /tmp/circom \
    && cd /tmp/circom \
    && cargo build --release \
    && install -m 0755 target/release/circom /usr/local/bin/circom \
    && rm -rf /tmp/circom

RUN circom --version


# =========================================================
# Stage 2: zk-ePrescription research environment
# =========================================================

FROM node:18.20-bookworm

ARG CIRCOM_VERSION=2.2.3
ARG SNARKJS_VERSION=0.7.6
ARG NARGO_VERSION=1.0.0-beta.24
ARG BB_VERSION=5.0.0-nightly.20260522

ENV DEBIAN_FRONTEND=noninteractive

# Tool locations installed by noirup / bbup.
ENV PATH="/root/.nargo/bin:/root/.bb:/usr/local/bin:${PATH}"

WORKDIR /workspace

# ---------------------------------------------------------
# System dependencies
# ---------------------------------------------------------

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        ca-certificates \
        jq \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# Circom
# ---------------------------------------------------------

COPY --from=circom-builder /usr/local/bin/circom /usr/local/bin/circom

# ---------------------------------------------------------
# snarkjs
# ---------------------------------------------------------

RUN npm install --global "snarkjs@${SNARKJS_VERSION}"

# ---------------------------------------------------------
# Noir / Nargo
# ---------------------------------------------------------

RUN curl -L \
        https://raw.githubusercontent.com/noir-lang/noirup/main/install \
        | bash \
    && noirup --version "${NARGO_VERSION}" \
    && nargo --version

# ---------------------------------------------------------
# Barretenberg
# ---------------------------------------------------------

RUN curl -L \
        https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/next/barretenberg/bbup/install \
        | bash \
    && BB_PATH=/usr/local/bin bbup -v "${BB_VERSION}" --no-modify-path \
    && bb --version

# ---------------------------------------------------------
# Verify toolchain
# ---------------------------------------------------------

RUN echo "========== Docker toolchain ==========" \
    && circom --version \
    && echo "snarkjs:" \
    && snarkjs --version 2>&1 | head -1 \
    && echo "nargo:" \
    && nargo --version \
    && echo "barretenberg:" \
    && bb --version \
    && echo "======================================"

# ---------------------------------------------------------
# Repository dependencies
# ---------------------------------------------------------

COPY package.json package-lock.json ./
RUN npm ci

COPY circom/package.json circom/package-lock.json ./circom/
RUN cd circom && npm ci

# ---------------------------------------------------------
# Repository
# ---------------------------------------------------------

COPY . .

# ---------------------------------------------------------
# Canonical regression entry point
# ---------------------------------------------------------

CMD ["npm", "test"]
