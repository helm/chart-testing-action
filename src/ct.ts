// Copyright The Helm Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as exec from '@actions/exec';
import * as path from "path";

const defaultChartTestingImage = "quay.io/helmpack/chart-testing:v2.4.0";
const defaultKubeconfig = path.join(process.env["HOME"] || "", ".kube", "config");

export class ChartTesting {
    private containerRunning = false;

    constructor(private readonly image: string, private readonly config: string, private readonly command: string,
                private readonly kubeconfig: string, private readonly context: string) {
        if (image === "") {
            this.image = defaultChartTestingImage;
        }
        if (command === "") {
            throw new Error("command is required")
        }
        if (kubeconfig === "") {
            this.kubeconfig = defaultKubeconfig
        }
    }

    async execute() {
        try {
            await this.runInContainer("ct", this.command)
        } finally {
            await this.killContainer();
        }
    }

    private async startContainer() {
        console.log("Running ct...");

        let args: string[] = ["pull", this.image];

        await exec.exec("docker", args);

        const workspace = process.env[`GITHUB_WORKSPACE`] || "";
        args = [
            "run",
            "--rm",
            "--interactive",
            "--detach",
            "--network=host",
            "--name=ct",
            `--volume=${workspace}:/workdir`,
            "--workdir=/workdir"
        ];
        if (this.config !== "") {
            args = args.concat(`--volume=${workspace}/${this.config}:/etc/ct/ct.yaml`)
        }
        args = args.concat(this.image, "cat");

        await exec.exec("docker", args);

        this.containerRunning = true;

        await this.runInContainer("mkdir", "-p", "/root/.kube");
        await exec.exec("docker", ["cp", this.kubeconfig, "ct:/root/.kube/config"]);

        if (this.context !== "") {
            await exec.exec("kubectl", ["config", "use-context", this.context])
        }

        await exec.exec("sh", ["-c", "kubectl --namespace=kube-system create serviceaccount tiller --dry-run --output=yaml | kubectl apply -f -"]);
        await exec.exec("sh", ["-c", "kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller --dry-run --output=yaml | kubectl apply -f -"]);
        await exec.exec("helm", ["init", "--service-account=tiller", "--upgrade", "--wait"]);
    }

    private async killContainer() {
        await exec.exec("docker", ["kill", "ct"])
    }

    private async runInContainer(...args: string[]) {
        if (!this.containerRunning) {
            await this.startContainer();
        }
        let procArgs = ["exec", "--interactive", "ct"];
        procArgs.push(...args);
        await exec.exec("docker", procArgs);
    }
}
