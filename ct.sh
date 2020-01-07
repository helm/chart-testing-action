#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_IMAGE=quay.io/helmpack/chart-testing:v2.4.0

show_help() {
cat << EOF
Usage: $(basename "$0") <options>

    -h, --help          Display help
    -i, --image         The chart-testing Docker image to use (default: quay.io/helmpack/chart-testing:v2.4.0)
    -c, --command       The chart-testing command to run
        --config        The path to the chart-testing config file
        --kubeconfig    The path to the kube config file
EOF
}

main() {
    local image="$DEFAULT_IMAGE"
    local config=
    local command=
    local kubeconfig="$HOME/.kube/config"

    parse_command_line "$@"

    if [[ -z "$command" ]]; then
        echo "ERROR: '-c|--command' is required." >&2
        show_help
        exit 1
    fi

    run_ct_container
    trap cleanup EXIT

    local changed
    changed=$(docker_exec ct list-changed)
    if [[ -z "$changed" ]]; then
        echo 'No chart changes detected.'
        return
    fi

    if [[ "$command" == "lint" ]]; then
        helm_init
    else
        configure_kube
        install_tiller
    fi

    if [[ "$command" == "list-changed" ]]; then
        echo "::set-output name=changed::true"
    fi

    run_ct
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -i|--image)
                if [[ -n "${2:-}" ]]; then
                    image="$2"
                    shift
                else
                    echo "ERROR: '-i|--image' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -c|--command)
                if [[ -n "${2:-}" ]]; then
                    command="$2"
                    shift
                else
                    echo "ERROR: '-c|--command' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --config)
                if [[ -n "${2:-}" ]]; then
                    config="$2"
                    shift
                else
                    echo "ERROR: '--config' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            --kubeconfig)
                if [[ -n "${2:-}" ]]; then
                    kubeconfig="$2"
                    shift
                else
                    echo "ERROR: '--kubeconfig' cannot be empty." >&2
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

run_ct_container() {
    echo 'Running ct container...'
    local args=(run --rm --interactive --detach --network host --name ct "--volume=$(pwd):/workdir" "--workdir=/workdir")

    if [[ -n "$config" ]]; then
        args+=("--volume=$(pwd)/$config:/etc/ct/ct.yaml" )
    fi

    args+=("$image" cat)

    docker "${args[@]}"
    echo
}

configure_kube() {
    docker_exec sh -c 'mkdir -p /root/.kube'
    docker cp "$kubeconfig" ct:/root/.kube/config
}

install_tiller() {
    echo 'Installing Tiller...'
    docker_exec sh -c 'kubectl create serviceaccount tiller --namespace kube-system --save-config --dry-run \
        --output=yaml | kubectl apply -f -'
    docker_exec sh -c 'kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin \
        --serviceaccount=kube-system:tiller --save-config --dry-run --output=yaml | kubectl apply -f -'
    docker_exec helm init --service-account tiller --upgrade --wait
    echo
}

helm_init() {
    docker_exec helm init --client-only
    echo
}

run_ct() {
    echo "Running 'ct $command'..."
    docker_exec ct "$command"
    echo
}

cleanup() {
    echo 'Removing ct container...'
    docker kill ct > /dev/null 2>&1
    echo 'Done!'
}

docker_exec() {
    docker exec --interactive ct "$@"
}

main "$@"
