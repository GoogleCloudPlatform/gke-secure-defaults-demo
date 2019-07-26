#!/usr/bin/env bash

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# "---------------------------------------------------------"
# "-                                                       -"
# "-  Delete deletes the GKE Cluster                       -"
# "-                                                       -"
# "---------------------------------------------------------"

# Do not set errexit as it makes partial deletes impossible
set -o nounset
set -o pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLUSTER_NAME=""
ZONE=""
SA_NAME="demo-developer"

# shellcheck source=./common.sh
source "$ROOT/common.sh"

# Get credentials for the k8s cluster
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE"

# Cleanup the cluster
echo "Deleting cluster"
gcloud container clusters delete "$CLUSTER_NAME" --zone "$ZONE" --quiet

echo "Deleting ${SA_NAME}"
gcloud projects remove-iam-policy-binding "${PROJECT}" --role=roles/container.developer --member="serviceAccount:${SA_NAME}@${PROJECT}.iam.gserviceaccount.com" --quiet
gcloud iam service-accounts delete "${SA_NAME}@${PROJECT}.iam.gserviceaccount.com" --quiet
