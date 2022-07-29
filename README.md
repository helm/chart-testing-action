# *chart-testing* Action

A GitHub Action for installing the [helm/chart-testing](https://github.com/helm/chart-testing) CLI tool.

## Usage

### Pre-requisites

1. A GitHub repo containing a directory with your Helm charts (e.g: `charts`)
1. A workflow YAML file in your `.github/workflows` directory.
  An [example workflow](#example-workflow) is available below.
  For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file)

### Inputs

For more information on inputs, see the [API Documentation](https://developer.github.com/v3/repos/releases/#input)

- `version`: The chart-testing version to install (default: `v3.7.0`)
- `yamllint_version`: The chart-testing version to install (default: `1.27.1`)
- `yamale_version`: The chart-testing version to install (default: `3.0.4`)

### Example Workflow

Create a workflow (eg: `.github/workflows/lint-test.yaml`):

Note that Helm and Python must be installed.
This can be achieved using actions as shown in the example below.
Python is required because `ct lint` runs [Yamale](https://github.com/23andMe/Yamale) and [yamllint](https://github.com/adrienverge/yamllint) which require Python.

```yaml
name: Lint and Test Charts

on: pull_request

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2
        with:
          fetch-depth: 0

      - name: Set up Helm
        uses: azure/setup-helm@v1
        with:
          version: v3.9.2

      - uses: actions/setup-python@v2
        with:
          python-version: 3.7

      - name: Set up chart-testing
        uses: helm/chart-testing-action@v2.2.1

      - name: Run chart-testing (list-changed)
        id: list-changed
        run: |
          changed=$(ct list-changed --target-branch ${{ github.event.repository.default_branch }})
          if [[ -n "$changed" ]]; then
            echo "::set-output name=changed::true"
          fi

      - name: Run chart-testing (lint)
        run: ct lint --target-branch ${{ github.event.repository.default_branch }}

      - name: Create kind cluster
        uses: helm/kind-action@v1.2.0
        if: steps.list-changed.outputs.changed == 'true'

      - name: Run chart-testing (install)
        run: ct install
```

This uses [`helm/kind-action`](https://www.github.com/helm/kind-action) GitHub Action to spin up a [kind](https://kind.sigs.k8s.io/) Kubernetes cluster,
and [`helm/chart-testing`](https://www.github.com/helm/chart-testing) to lint and test your charts on every pull request.

## Upgrading from v1.x.x

v2.0.0 is a major release with breaking changes.
The action no longer wraps the chart-testing tool but simply installs it.
It is no longer run in a Docker container.
All `ct` options are now directly available without the additional abstraction layer.

## Code of conduct

Participation in the Helm community is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
