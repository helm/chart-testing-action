import * as exec from '@actions/exec';

const defaultChartTestingVersion = "v2.4.0";

export class ChartTesting {
    private containerRunning = false;

    constructor(readonly version: string, readonly configFile: string, readonly command: string, readonly kubeconfigFile: string) {
        if (version === "") {
            this.version = defaultChartTestingVersion;
        }
        if (command === "") {
            throw new Error("command is required")
        }
        if (kubeconfigFile === "") {
            throw new Error("kubeconfigFile is required")
        }
    }

    private async startContainer(version: string, configFile: string, kubeconfigFile: string) {
        console.log("running ct...");

        const ctImage = `quay.io/helmpack/chart-testing:${version}`;
        let args: string[] = ["pull", ctImage];

        await exec.exec("docker", args);

        const workspace = process.env[`GITHUB_WORKSPACE`] || "";
        args = [
            "run",
            "--rm",
            "--interactive",
            "--detach",
            "--network=host",
            "--name=ct",
            `--volume=${workspace}/${configFile}:/etc/ct/ct.yaml`,
            `--volume=${workspace}:/workdir`,
            "--workdir=/workdir",
            ctImage,
            "cat"
        ];

        await exec.exec("docker", args);

        this.containerRunning = true;

        await this.runInContainer("mkdir", "-p", "/root/.kube");
        await exec.exec("docker", ["cp", kubeconfigFile, "ct:/root/.kube/config"]);
    }

    private async runInContainer(...procArgs: string[]) {
        if (!this.containerRunning) {
            await this.startContainer(this.version, this.configFile, this.kubeconfigFile);
        }
        let args = ["exec", "--interactive", "ct"];
        args.push(...procArgs);
        await exec.exec("docker", args);
    }

    async verifyCluster() {
        await this.runInContainer("kubectl", "cluster-info");
        await this.runInContainer("kubectl", "get", "nodes");
    }

    async installLocalPathProvisioner() {
        await this.runInContainer("kubectl", "delete", "storageclass", "standard");
        await this.runInContainer("kubectl", "apply", "-f", "https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml");
    }

    async runChartTesting() {
        await this.runInContainer("ct", this.command)
    }
}
