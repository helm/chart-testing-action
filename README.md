# *chart-testing* Action

A GitHub Action to lint and test Helm charts, using the [helm/chart-testing](https://github.com/helm/chart-testing) CLI tool.

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

      - name: Create kind cluster
        uses: helm/kind-action@master
        with:
          installLocalPathProvisioner: true

      - name: Run chart-testing (lint)
        uses: helm/chart-testing-action@master
        with:
          command: lint

      - name: Run chart-testing (install)
        uses: helm/chart-testing-action@master
        with:
          command: install
```

This uses [`@helm/kind-action`](https://www.github.com/helm/kind-action) GitHub Action to spin up a [kind](https://kind.sigs.k8s.io/) Kubernetes cluster, and [`@helm/chart-testing-action`](https://www.github.com/helm/chart-testing-action) to lint and test your charts on every Pull Request.

## Code of conduct

Participation in the Helm community is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
