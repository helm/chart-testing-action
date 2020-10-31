#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_CHART_TESTING_VERSION=v3.2.0

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
    echo "Installing chart-testing..."

    curl -sSLo ct.tar.gz "https://github.com/helm/chart-testing/releases/download/$version/chart-testing_${version#v}_linux_amd64.tar.gz"
    tar -xzf ct.tar.gz
    sudo mv ct /usr/local/bin/ct
    mkdir "$HOME/.ct"
    mv etc/* "$HOME/.ct"

    pip install yamllint==1.25.0
    pip install yamale==3.0.4
}

main "$@"
