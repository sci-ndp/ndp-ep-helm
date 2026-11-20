#!/usr/bin/env bash
# Deploy ndp-ep-helm from this checkout's chart (./helm) instead of the
# published one. Same flags as helm.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
NDP_EP_CHART=./helm exec ./helm.sh "$@"
