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

import * as core from '@actions/core';
import {ChartTesting} from "./ct";

const ImageInput = "image";
const ConfigInput = "config";
const CommandInput = "command";
const KubeconfigInput = "kubeconfig";
const ContextInput = "context";

export function createChartTesting(): ChartTesting {
    const image = core.getInput(ImageInput);
    const config = core.getInput(ConfigInput);
    const command = core.getInput(CommandInput, {required: true});
    const kubeconfig = core.getInput(KubeconfigInput);
    const context = core.getInput(ContextInput);

    return new ChartTesting(image, config, command, kubeconfig, context)
}

async function run() {
    try {
        const ct = createChartTesting();
        await ct.execute()
    } catch (error) {
        core.setFailed(error.message);
    }
}

run();
