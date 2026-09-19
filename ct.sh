#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_TESTING_VERSION=3.14.0
DEFAULT_YAMLLINT_VERSION=1.33.0
DEFAULT_YAMALE_VERSION=6.0.0

# Set once a download is staged, so cleanup() can remove it on any exit path.
staging_dir=

cleanup() {
    if [[ -n "${staging_dir}" ]]; then
        rm -rf "${staging_dir}"
    fi
}

# Version strings are interpolated into filesystem paths and into the
# $GITHUB_PATH / $GITHUB_ENV files, so restrict them to characters that can
# neither traverse directories nor add extra lines to those files.
validate_version() {
    local flag="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[0-9]+(\.[0-9]+)*([-+][A-Za-z0-9.]+)?$ ]]; then
        echo "ERROR: '${flag}' must be a version number, got: '${value}'" >&2
        exit 1
    fi
}

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help          Display help
    -v, --version       The chart-testing version to use (default: ${DEFAULT_CHART_TESTING_VERSION})"
EOF
}

main() {
    local version="${DEFAULT_CHART_TESTING_VERSION}"
    local yamllint_version="${DEFAULT_YAMLLINT_VERSION}"
    local yamale_version="${DEFAULT_YAMALE_VERSION}"

    trap cleanup EXIT

    parse_command_line "$@"

    validate_version '-v|--version' "${version}"
    validate_version '--yamllint-version' "${yamllint_version}"
    validate_version '--yamale-version' "${yamale_version}"

    install_chart_testing
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    version="${2#v}"
                    shift
                else
                    echo "ERROR: '-v|--version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --yamllint-version)
                if [[ -n "${2:-}" ]]; then
                    yamllint_version="$2"
                    shift
                else
                    echo "ERROR: '--yamllint-version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --yamale-version)
                if [[ -n "${2:-}" ]]; then
                    yamale_version="$2"
                    shift
                else
                    echo "ERROR: '--yamale-version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            *)
                break
                ;;
        esac

        shift
    done
}

install_chart_testing() {
    if [[ ! -d "${RUNNER_TOOL_CACHE}" ]]; then
        echo "Cache directory '${RUNNER_TOOL_CACHE}' does not exist" >&2
        exit 1
    fi

    local arch
    if [[ $(uname -m) == "aarch64" ]]; then
      arch=arm64
    else
      arch=amd64
    fi
    local cache_dir="${RUNNER_TOOL_CACHE}/ct/${version}/${arch}"
    local venv_dir="${cache_dir}/venv"

    # Only treat the cache as populated when the binary itself is present. An
    # empty or partially populated directory -- left behind by an earlier run
    # that failed after mkdir but before extraction -- must never suppress
    # signature verification.
    if [[ ! -x "${cache_dir}/ct" ]]; then
        echo "Installing chart-testing v${version}..."
        local ct_cert="https://github.com/helm/chart-testing/releases/download/v${version}/chart-testing_${version}_linux_${arch}.tar.gz.pem"
        local ct_sig="https://github.com/helm/chart-testing/releases/download/v${version}/chart-testing_${version}_linux_${arch}.tar.gz.sig"

        # Stage everything outside the cache, and publish to ${cache_dir} only
        # after the download, signature verification and extraction have all
        # succeeded. This keeps a failed run from leaving anything behind that
        # a later run could mistake for a verified install.
        staging_dir="$(mktemp -d)"

        # --fail so an HTTP error is reported as a download failure rather than
        # being saved as the "tarball" and surfacing later as a bogus
        # signature-verification error.
        if ! curl --fail --retry 5 --retry-delay 1 -sSLo "${staging_dir}/ct.tar.gz" \
          "https://github.com/helm/chart-testing/releases/download/v${version}/chart-testing_${version}_linux_${arch}.tar.gz"; then
          echo "ERROR: Unable to download chart-testing version: v${version}" >&2
          exit 1
        fi

        if ! cosign verify-blob --certificate "${ct_cert}" --signature "${ct_sig}" \
          --certificate-identity "https://github.com/helm/chart-testing/.github/workflows/release.yaml@refs/heads/main" \
          --certificate-oidc-issuer "https://token.actions.githubusercontent.com" "${staging_dir}/ct.tar.gz"; then
          echo "ERROR: Unable to validate chart-testing version: v${version}" >&2
          exit 1
        fi

        mkdir -p "${staging_dir}/extracted"
        tar -xzf "${staging_dir}/ct.tar.gz" -C "${staging_dir}/extracted"

        # Safe because validate_version has already rejected anything that
        # could make ${cache_dir} point outside ${RUNNER_TOOL_CACHE}.
        rm -rf "${cache_dir}"
        mkdir -p "$(dirname "${cache_dir}")"
        mv "${staging_dir}/extracted" "${cache_dir}"

        echo 'Creating virtual Python environment...'
        export UV_LINK_MODE=copy
        uv venv "${venv_dir}"
        export VIRTUAL_ENV="${venv_dir}"

        echo 'Installing yamllint...'
        uv pip install "yamllint==${yamllint_version}"

        echo 'Installing Yamale...'
        uv pip install "yamale==${yamale_version}"
    fi

    # https://github.com/helm/chart-testing-action/issues/62
    echo 'Adding ct directory to PATH...'
    echo "${cache_dir}" >> "${GITHUB_PATH}"

    echo 'Setting CT_CONFIG_DIR...'
    echo "CT_CONFIG_DIR=${cache_dir}/etc" >> "${GITHUB_ENV}"

    echo 'Configuring environment variables for virtual environment for subsequent workflow steps...'
    echo "VIRTUAL_ENV=${venv_dir}" >> "${GITHUB_ENV}"
    echo "${venv_dir}/bin" >> "${GITHUB_PATH}"

    "${cache_dir}/ct" version
}

main "$@"
