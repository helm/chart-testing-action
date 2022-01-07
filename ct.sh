#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_TESTING_VERSION=v3.5.0

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help          Display help
    -v, --version       The chart-testing version to use (default: $DEFAULT_CHART_TESTING_VERSION)"
EOF
}

main() {
    local version="$DEFAULT_CHART_TESTING_VERSION"

    parse_command_line "$@"

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
                    version="$2"
                    shift
                else
                    echo "ERROR: '-v|--version' cannot be empty." >&2
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
    if [[ ! -d "$RUNNER_TOOL_CACHE" ]]; then
        echo "Cache directory '$RUNNER_TOOL_CACHE' does not exist" >&2
        exit 1
    fi

    local arch
    arch=$(uname -m)
    local cache_dir="$RUNNER_TOOL_CACHE/ct/$version/$arch"
    local venv_dir="$cache_dir/venv"

    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir"

        echo "Installing chart-testing..."
        curl -sSLo ct.tar.gz "https://github.com/helm/chart-testing/releases/download/$version/chart-testing_${version#v}_linux_amd64.tar.gz"
        tar -xzf ct.tar.gz -C "$cache_dir"
        rm -f ct.tar.gz

        echo 'Creating virtual Python environment...'
        python3 -m venv "$venv_dir"

        echo 'Activating virtual environment...'
        # shellcheck disable=SC1090
        source "$venv_dir/bin/activate"

        echo 'Installing yamllint...'
        pip3 install yamllint==1.25.0

        echo 'Installing Yamale...'
        pip3 install yamale==3.0.4
    fi

    # https://github.com/helm/chart-testing-action/issues/62
    echo 'Adding ct directory to PATH...'
    echo "$cache_dir" >> "$GITHUB_PATH"

    echo 'Setting CT_CONFIG_DIR...'
    echo "CT_CONFIG_DIR=$cache_dir/etc" >> "$GITHUB_ENV"

    echo 'Configuring environment variables for virtual environment for subsequent workflow steps...'
    echo "VIRTUAL_ENV=$venv_dir" >> "$GITHUB_ENV"
    echo "$venv_dir/bin" >> "$GITHUB_PATH"

    "$cache_dir/ct" version
}

main "$@"
