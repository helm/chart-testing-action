# *chart-testing* Action

A GitHub Action to lint and test Helm charts, using the [helm/chart-testing](https://github.com/helm/chart-testing) CLI tool.

`master` supports Helm 3 only.
Support for Helm 2 is on branch `dev-v2`.

## Usage

### Pre-requisites

1. A GitHub repo containing a directory with your Helm charts (eg: `/charts`)
1. Optional: if you want to override the defaults, a [chart-testing config file](https://github.com/helm/chart-testing#configuration) in your GitHub repo (eg. `/ct.yaml`)
1. A workflow YAML file in your `.github/workflows` directory. An [example workflow](#example-workflow) is available below.
  For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file)

### Inputs

For more information on inputs, see the [API Documentation](https://developer.github.com/v3/repos/releases/#input)

- `image`: The chart-testing Docker image to use (default: `quay.io/helmpack/chart-testing:v2.4.0`)
- `config`: The path to the config file
- `command`: The chart-testing command to run
- `kubeconfig`: The path to the kube config file

### Example Workflow

Create a workflow (eg: `.github/workflows/lint-test.yaml`):

```yaml
name: Lint and Test Charts

on: pull_request

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v1

      - name: Run chart-testing (lint)
        id: lint
        uses: helm/chart-testing-action@v1.0.0-alpha.3
        with:
          command: lint

      - name: Create kind cluster
        uses: helm/kind-action@v1.0.0-alpha.3
        with:
          install_local_path_provisioner: true
        # Only build a kind cluster if there are chart changes to test.
        if: steps.lint.outputs.changed == 'true'

      - name: Run chart-testing (install)
        uses: helm/chart-testing-action@v1.0.0-alpha.3
        with:
          command: install
```

This uses [`@helm/kind-action`](https://www.github.com/helm/kind-action) GitHub Action to spin up a [kind](https://kind.sigs.k8s.io/) Kubernetes cluster, and [`@helm/chart-testing-action`](https://www.github.com/helm/chart-testing-action) to lint and test your charts on every Pull Request.

## Code of conduct

Participation in the Helm community is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
