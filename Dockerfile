# Base images pinned by digest (as verified on 2026-10-28). If a digest is not
# available for your architecture, override it, e.g.
#   docker build --build-arg NODE_IMAGE=node:18.20-bookworm --build-arg RUST_IMAGE=rust:1.96-bookworm -t zkep .
ARG RUST_IMAGE=rust:1.96-bookworm@sha256:a339861ae23e9abb272cea45dfafde21760d2ce6577a70f8a926153677902663
ARG NODE_IMAGE=node:18.20-bookworm@sha256:c6ae79e38498325db67193d391e6ec1d224d96c693a8a4d943498556716d3783

# =========================================================
# Stage 1: Build Circom 2.2.3
# =========================================================

FROM ${RUST_IMAGE} AS circom-builder

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

FROM ${NODE_IMAGE}

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
        time \
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
# Pin the downloaded prover binaries (x86-64): the build stops if noirup/bbup
# deliver anything other than the binaries verified on 2026-10-28. On other
# architectures (Raspberry Pi, Jetson) the hashes are printed for the record.
# ---------------------------------------------------------

ARG NARGO_SHA256_AMD64=247b1d71a01993f2f4102ba92b3da84f5ff2cbafdde0de989c7aa3c6c9600c1a
ARG BB_SHA256_AMD64=031556ee54dc65b3fffb6388a267460c02f988dd4420721b381067d0151b4942

RUN echo "tool binaries ($(uname -m)):" \
    && sha256sum "$(command -v circom)" "$(command -v nargo)" "$(command -v bb)" \
    && if [ "$(uname -m)" = "x86_64" ]; then \
         echo "${NARGO_SHA256_AMD64}  $(command -v nargo)" | sha256sum -c - \
         && echo "${BB_SHA256_AMD64}  $(command -v bb)" | sha256sum -c - ; \
       fi

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
# Barretenberg CRS: downloaded once here (with retries) so that
# `docker run` needs no network access
# ---------------------------------------------------------

RUN bash scripts/prime_crs.sh

# ---------------------------------------------------------
# Entry point: demo | test | kat | help (scripts/run.sh)
# ---------------------------------------------------------

ENTRYPOINT ["bash", "/workspace/scripts/run.sh"]
CMD ["test"]
