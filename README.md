# Chart testing action

A GitHub Action to lint and test Helm charts, using the [helm/chart-testing](https://github.com/helm/chart-testing) CLI tool.

## Usage

### Pre-requisites

1. A GitHub repo containing a directory with your Helm charts
1. A [chart-testing config file](https://github.com/helm/chart-testing#configuration) in your GitHub repo
1. Create a workflow `.yml` file in your `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

### Inputs

For more information on these inputs, see the [API Documentation](https://developer.github.com/v3/repos/releases/#input)

- `image`: The chart-testing Docker image to use (default: `quay.io/helmpack/chart-testing:v2.4.0`)
- `config`: The path to the config file
- `command`: The chart-testing command to run
- `kubeconfig`: The path to the kube config file
- `context`: The kubeconfig context to use

### Example workflow

Create a workflow (eg: .github/workflows/chart-testing.yml see Creating a Workflow file):

```yaml
name: chart actions

on:
  pull_request:
  push:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v1
      - name: Create cluster
        uses: helm/kind-action@v1
        with:
          installLocalPathProvisioner: true
      - name: Run chart-testing
        uses: helm/chart-testing-action@v1
        with:
          command: version
```

This uses [`@helm/kind-action`](https://www.github.com/helm/kind-action) GitHub Action to spin up a [kind](https://kind.sigs.k8s.io/) Kubernetes cluster, and [`@helm/chart-testing-action`](https://www.github.com/helm/chart-testing-action) to lint and test your charts on every pull request and push.

## Code of conduct

Participation in the Helm community is governed by the [Code of Conduct](code-of-conduct.md).
