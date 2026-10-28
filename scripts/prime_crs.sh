#!/usr/bin/env bash
# Downloads the Barretenberg CRS once, at image build time, so that
# `docker run` needs no network. Proves and verifies TV-001 once with UltraHonk
# (outputs discarded) to cache every CRS point the circuit needs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../noir/redemption"
nargo compile >/dev/null
nargo execute >/dev/null
for attempt in 1 2 3 4 5; do
    if bb write_vk -b target/redemption.json -o target >/dev/null 2>&1 \
        && bb prove -b target/redemption.json -w target/redemption.gz -k target/vk -o target >/dev/null 2>&1 \
        && bb verify -k target/vk -p target/proof -i target/public_inputs >/dev/null 2>&1; then
        rm -rf target
        echo "Barretenberg CRS cached:"
        ls -la "$HOME/.bb-crs"
        exit 0
    fi
    echo "CRS download attempt $attempt failed (crs.aztec-labs.com); retrying in 15 s"
    sleep 15
done
rm -rf target
echo "Could not download the Barretenberg CRS from crs.aztec-labs.com; check the network and rebuild."
exit 1
