#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}" || realpath "${BASH_SOURCE[0]}")")

main() {
    args=(--command "${INPUT_COMMAND?'command' is required}")

    if [[ -n "${INPUT_IMAGE:-}" ]]; then
        args+=(--image "${INPUT_IMAGE}")
    fi

    if [[ -n "${INPUT_CONFIG:-}" ]]; then
        args+=(--config "${INPUT_CONFIG}")
    fi

    if [[ -n "${INPUT_KUBECONFIG:-}" ]]; then
        args+=(--kubeconfig "${INPUT_KUBECONFIG}")
    fi

    "$SCRIPT_DIR/ct.sh" ${args[@]}
}

main
