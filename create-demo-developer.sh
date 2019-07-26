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
# "-  Creates a second service account user to test PSP    _"
# "-                                                       -"
# "---------------------------------------------------------"

# Do no set exit on error, since the rollout status command may fail
set -o nounset
set -o pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT=""
CLUSTER_NAME=""
ZONE=""
SA_NAME="demo-developer"

# shellcheck source=./common.sh
source "$ROOT/common.sh"

# create the "demo-developer" service account
gcloud iam service-accounts create "${SA_NAME}"

# grant roles/container.developer to the service account - the ability to interact with the cluster and attempt to create pods:
gcloud projects add-iam-policy-binding "${PROJECT}" --role=roles/container.developer --member="serviceAccount:${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

# Create a service account key in json format as a local file called "key.json"
gcloud iam service-accounts keys create key.json --iam-account "${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

# Configure gcloud to authenticate as this service account via the key.json file
gcloud auth activate-service-account --key-file=key.json

# Configure kubectl to interact with the cluster as
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}"

