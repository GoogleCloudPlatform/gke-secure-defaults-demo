# Google Kubernetes Engine Secure Defaults Demo

## Table of Contents

<!-- toc -->
* [Google Kubernetes Engine Secure Defaults Demo](#google-kubernetes-engine-secure-defaults-demo)
* [Introduction](#introduction)
* [Objectives](#objectives)
* [Prerequisites](#prerequisites)
  * [Run Demo in a Google Cloud Shell](#run-demo-in-a-google-cloud-shell)
  * [Supported Operating Systems](#supported-operating-systems)
  * [Tools](#tools)
  * [Versions](#versions)
* [Deployment Steps](#deployment-steps)
* [Validation](#validation)
* [Tear Down](#tear-down)
* [Troubleshooting](#troubleshooting)
* [Relevant Materials](#relevant-materials)
<!-- toc -->

## Introduction

This lab demonstrates some of the security concerns of a default [Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) cluster configuration and the corresponding hardening measures to prevent multiple paths of pod escape and cluster privilege escalation.  These attack paths are relevant in the following scenarios:

1. An application flaw in an external facing pod that allows for Server-Side Request Forgery (SSRF) attacks.
2. A fully compromised container inside a pod allowing for Remote Command Execution (RCE).
3. A malicious internal user or an attacker with a set of compromised internal user credentials with the ability to create/update a pod in a given namespace.

The following security settings will be tested in both disabled and enabled states to demonstrate the real-world implications of these configurations:

* Disabling the [Legacy GCE Metadata API Endpoint][8]
* Enabling [Metadata Concealment][10]
* Enabling and configuring [PodSecurityPolicy][5]

## Objectives

Upon completion of this lab you will understand the need for protecting the GKE Instance Metadata and defining appropriate PodSecurityPolicy policies for your environment.

You will:

1. Create a small GKE cluster in an existing GCP project.
2. Validate the most common paths of pod escape and cluster privilege escalation from the perspective of a malicious internal user.
3. Harden the GKE cluster for these issues by attaching a new node pool with improved security settings.
4. Validate the cluster no longer allows for each of those actions to occur.

## Prerequisites

* Access to an existing Google Cloud project with the Kubernetes Engine service enabled. If you do not have a Google Cloud account, please signup for a free trial [here][2].
* A Google Cloud account and project is required for this demo. The project must have the proper quota to run a Kubernetes Engine cluster with at least 3 vCPUs and 10GB of RAM. How to check your account's quota is documented here: [quotas][1].

### Supported Operating Systems

This demo can be run from MacOS, Linux, or, alternatively, directly from [Google Cloud Shell](https://cloud.google.com/shell/docs/). The latter option is the simplest as it only requires browser access to GCP and no additional software is required. Instructions for both alternatives can be found below.

### Deploying Demo from Google Cloud Shell

_NOTE: This section can be skipped if the cloud deployment is being performed without Cloud Shell, for instance from a local machine or from a server outside GCP._

[Google Cloud Shell](https://cloud.google.com/shell/docs/) is a browser-based terminal that Google provides to interact with your GCP resources. It is backed by a free Compute Engine instance that comes with many useful tools already installed, including everything required to run this demo.

Click the button below to open the demo in your Cloud Shell:

[![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/open?git_repo=https%3A%2F%2Fgithub.com%2FGoogleCloudPlatform%2Fgke-secure-defaults-demo&page=editor&tutorial=README.md)

To prepare [gcloud](https://cloud.google.com/sdk/gcloud/) for use in Cloud Shell, execute the following command in the terminal at the bottom of the browser window you just opened:

```console
gcloud init
```

Respond to the prompts and continue with the following deployment instructions. The prompts will include the account you want to run as, the current project, and, optionally, the default region and zone. These configure Cloud Shell itself-the actual project, region, and zone, used by the demo will be configured separately below.

### Deploying the Demo without Cloud Shell

_NOTE: If the demo is being deployed via Cloud Shell, as described above, this section can be skipped._

For deployments without using Cloud Shell, you will need to have access to a computer providing a [bash](https://www.gnu.org/software/bash/) shell with the following tools installed:

* [Google Cloud SDK (v214.0.0 or later)](https://cloud.google.com/sdk/downloads)
* [kubectl (v1.12.0 or later)](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [git](https://git-scm.com/)

Use `git` to clone this project to your local machine:

```console
git clone https://github.com/GoogleCloudPlatform/gke-secure-defaults-demo
```

When downloading is complete, change your current working directory to the new project:

```console
cd gke-secure-defaults-demo
```

Continue with the instructions below, running all commands from this directory.

## Deployment Steps

_NOTE: The following instructions are applicable for deployments performed both with and without Cloud Shell._

To deploy the cluster, execute the following command:

```console
./create.sh -c default-cluster
```

Replace the text `default-cluster` the name of the cluster that you would like to create.

The create script will output the following message when complete:

```console
...snip...
NAME          LOCATION    MASTER_VERSION  MASTER_IP     MACHINE_TYPE   NODE_VERSION  NUM_NODES  STATUS
default-cluster  us-central1-a  1.12.8-gke.6    34.66.214.195  n1-standard-1  1.12.8-gke.6  2          RUNNING
Fetching cluster endpoint and auth data.
kubeconfig entry generated for default-cluster.
```

The script will:

1. Enable the necessary APIs in your project.  Specifically, `compute` and `container`.
1. Create a new Kubernetes Engine cluster in your current ZONE, VPC and network that omits configuring the [GKE Metadata Concealment proxy][10] and does not enable the setting to block access to the [Legacy Compute Metadata API][8].
1. Retrieve your cluster credentials to enable `kubectl` usage.

After the cluster is created successfully, check your installed version of Kubernetes using the `kubectl version` command:

```console
kubectl version

Client Version: version.Info{Major:"1", Minor:"14", GitVersion:"v1.14.3", GitCommit:"5e53fd6bc17c0dec8434817e69b04a25d8ae0ff0", GitTreeState:"clean", BuildDate:"2019-06-06T01:44:30Z", GoVersion:"go1.12.5", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"12+", GitVersion:"v1.12.8-gke.10", GitCommit:"f53039cc1e5295eed20969a4f10fb6ad99461e37", GitTreeState:"clean", BuildDate:"2019-06-19T20:48:40Z", GoVersion:"go1.10.8b4", Compiler:"gc", Platform:"linux/amd64"}
```

Your `kubectl` version (Client) should be within two minor releases of the GKE cluster created (Server).

### Run a Google Cloud-SDK pod

From your Cloud Shell prompt, launch a single instance of the Google Cloud-SDK container that will be automatically removed after exiting from the shell:

```console
kubectl run -it --generator=run-pod/v1 --rm gcloud --image=google/cloud-sdk:latest --restart=Never -- bash
```

This will take a few moments to complete.

You should now have a bash shell inside the pod's container:

```console
root@gcloud:/#
```

It may take a few seconds for the container to be started and the command prompt to be displayed. If you don't see a command prompt, try pressing __Enter__.

### Explore the Legacy Compute Metadata Endpoint

In GKE Clusters created with version 1.11 or below, the "Legacy" or `v1beta1` Compute Metadata endpoint is available by default.  Unlike the current Compute Metadata version, `v1`, the `v1beta1` Compute Metadata endpoint does not require a custom HTTP header to be included in all requests.  On new GKE Clusters created at version 1.12 or greater, the legacy Compute Engine metadata endpoints are now disabled by default.  For more information, see: [Protecting Cluster Metadata][10]

Run the following command to access the "Legacy" Compute Metadata endpoint without requiring a custom HTTP header to get the GCE Instance name where this pod is running:

```console
curl -s http://metadata.google.internal/computeMetadata/v1beta1/instance/name && echo

gke-default-cluster-default-pool-b57a043a-6z5v
```

The `&& echo` command is to aid with terminal formatting and output readability.  Now, re-run the same command, but instead use the `v1` Compute Metadata endpoint:

```console
curl -s http://metadata.google.internal/computeMetadata/v1/instance/name && echo

...snip...
Your client does not have permission to get URL <code>/computeMetadata/v1/instance/name</code> from this server. Missing Metadata-Flavor:Google header.
...snip...
```

Notice how it returns an error stating that it requires the custom HTTP header to be present.  Add the custom header on the next run and retrieve the GCE instance name that is running this pod:

```console
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name && echo

gke-default-cluster-default-pool-b57a043a-6z5v
```

Without requiring a custom HTTP header when accessing the GCE Instance Metadata endpoint, a flaw in an application that allows an attacker to trick the code into retrieving the contents of an attacker-specified web URL could provide a simple method for enumeration and potential credential exfiltration.  By requiring a custom HTTP header, the attacker needs to exploit an application flaw that allows them to control the URL and also add custom headers in order to carry out this attack successfully.

Keep this shell inside the pod available for the next step.  If you accidentally exit from the pod, simply re-run:

```console
kubectl run -it --generator=run-pod/v1 --rm gcloud --image=google/cloud-sdk:latest --restart=Never -- bash
```

### Explore the GKE node bootstrapping credentials

From inside the same pod shell, run the following command to list the attributes associated with the underlying GCE instances. Be sure to include the trailing slash:

```console
curl -s http://metadata.google.internal/computeMetadata/v1beta1/instance/attributes/
```

Perhaps the most sensitive data in this listing is `kube-env`.  It contains several variables which the `kubelet` uses as initial credentials when attaching the node to the GKE cluster.  The variables `CA_CERT`, `KUBELET_CERT`, and `KUBELET_KEY` contain this information and are therefore considered sensitive to non-cluster administrators.

To see the potentially sensitive variables and data, run the following command:

```console
curl -s http://metadata.google.internal/computeMetadata/v1beta1/instance/attributes/kube-env
```

Therefore, in any of the following situations:

1. A flaw that allows for SSRF in a pod application
2. An application or library flaw that allow for RCE in a pod
3. An internal user with the ability to create or exec into a pod

There exists a high likelihood for compromise and exfiltration of sensitive `kubelet` bootstrapping credentials via the Compute Metadata endpoint.  With the `kubelet` credentials, it is possible to leverage them in certain circumstances to escalate privileges to that of  `cluster-admin` and therefore have full control of the GKE Cluster including all data, applications, and access to the underlying nodes.

### Leverage the Permissions Assigned to this Node Pool's Service Account

By default, GCP projects with the Compute API enabled have a default service account in the format of `NNNNNNNNNN-compute@developer.gserviceaccount.com` in the project and the `Editor` role attached to it.  Also by default, GKE clusters created without specifying a service account will utilize the default Compute service account and attach it to all worker nodes.

Run the following `curl` command to list the OAuth scopes associated with the service account attached to the underlying GCE instance:

```console
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/scopes

https://www.googleapis.com/auth/devstorage.read_only
https://www.googleapis.com/auth/logging.write
https://www.googleapis.com/auth/monitoring
https://www.googleapis.com/auth/service.management.readonly
https://www.googleapis.com/auth/servicecontrol
https://www.googleapis.com/auth/trace.append
```

The combination of authentication scopes and the permissions of the service account dictates what applications on this node can access.  The above list is the minimum scopes needed for most GKE clusters, but some use cases require increased scopes.

If the authentication scope were to be configured during cluster creation to include `https://www.googleapis.com/auth/cloud-platform`, this would allow any GCP API to be considered "in scope", and only the IAM permissions assigned to the service account would determine what can be accessed.  If the default service account is in use and the default IAM Role of `Editor` was not modified, this effectively means that any pod on this node pool has `Editor` permissions to the GCP project where the GKE cluster is deployed.  As the `Editor` IAM Role has a wide range of read/write permissions to interact with resources in the project such as Compute instances, GCS buckets, GCR registries, and more, this is most likely not desired.

Exit out of this pod by typing:

```console
exit
```

### Deploy a pod that mounts the host filesystem

One of the simplest paths for "escaping" to the underlying host is by mounting the host's filesystem into the pod's filesystem using standard Kubernetes `volumes` and `volumeMounts` in a `Pod` specification.

To demonstrate this, run the following to create a Pod that mounts the underlying host filesystem `/` at the folder named `/rootfs` inside the container:

```console
kubectl apply -f manifests/hostpath.yml
```

Run `kubectl get pod` and re-run until it's in the "Running" state:

```console
kubectl get pod

NAME       READY   STATUS    RESTARTS   AGE
hostpath   1/1     Running   0          30s
```

### Explore and compromise the underlying host

Run the following to obtain a shell inside the pod you just created:

```console
kubectl exec -it hostpath -- bash
```

Switch to the pod shell's root filesystem point to that of the underlying host:

```console
chroot /rootfs /bin/bash

hostpath / #
```

With those simple commands, the pod is now effectively a `root` shell on the node. You are now able to do the following:

| run the standard docker command with full permissions                          | `docker ps`                                          |
|--------------------------------------------------------------------------------|------------------------------------------------------|
| list all local docker images                                                   | `docker images`                                      |
| `docker run` privileged container of your choosing                             | `docker run --privileged <imagename>:<imageversion>` |
| examine the Kubernetes secrets mounted on the node                             | `mount \| grep volumes \| awk '{print $3}' \| xargs ls` |
| `exec` into any running container (even into another pod in another namespace) | `docker exec -it <docker container ID> sh`           |

Nearly every operation that the `root` user can perform is available to this pod shell.  This includes persistence mechanisms like adding SSH users/keys, running privileged docker containers on the host outside the view of Kubernetes, and much more.

To exit the pod shell, run `exit` twice - once to leave the `chroot` and another to leave the pod's shell:

```console
exit
```

```console
exit
```

Now you can delete the `hostpath` pod:

```console
kubectl delete -f manifests/hostpath.yml

pod "hostpath" deleted
```

### Understand the available controls

The next steps of this demo will cover:

* __Disabling the Legacy GCE Metadata API Endpoint__ - By specifying a custom metadata key and value, the `v1beta1` metadata endpoint will no longer be available from the instance.
* __Enable Metadata Concealment__ - Passing an additional configuration during cluster and/or node pool creation, a lightweight proxy will be installed on each node that proxies all requests to the Metadata API and prevents access to sensitive endpoints.
* __Enable and configure PodSecurityPolicy__ - Configuring this option on a GKE cluster will add the PodSecurityPolicy Admission Controller which can be used to restrict the use of insecure settings during Pod creation.  In this demo's case, preventing containers from running as the root user and having the ability to mount the underlying host filesystem.

### Deploy a second node pool

To enable you to experiment with and without the Metadata endpoint protections in place, you'll create a second node pool that includes two additional settings.  Pods that are scheduled to the generic node pool will not have the protections, and Pods scheduled to the second node pool will have them enabled.

Note: In GKE versions 1.12 and newer, the `--metadata=disable-legacy-endpoints=true` setting will automatically be enabled.  The next command is defining it explicitly for clarity.

Create the second node pool:

```console
./second-pool.sh -c default-cluster

NAME         MACHINE_TYPE   DISK_SIZE_GB  NODE_VERSION
second-pool  n1-standard-1  100           1.12.8-gke.6
```

### Run a Google Cloud-SDK pod

In Cloud Shell, launch a single instance of the Google Cloud-SDK container that will be run only on the second node pool with the protections enabled and not run as the root user.

```console
kubectl run -it --generator=run-pod/v1 --rm gcloud --image=google/cloud-sdk:latest --restart=Never --overrides='{ "apiVersion": "v1", "spec": { "securityContext": { "runAsUser": 65534, "fsGroup": 65534 }, "nodeSelector": { "cloud.google.com/gke-nodepool": "second-pool" } } }' -- bash
```

You should now have a bash shell inside the pod's container running on the node pool named `second-pool`. You should see the following:

```console
nobody@gcloud:/$
```
It may take a few seconds for the container to be started and the command prompt to be displayed.

If you don't see a command prompt, try pressing __Enter__.

### Explore various blocked endpoints

With the configuration of the second node pool set to `--metadata=disable-legacy-endpoints=true`, the following command will now fail as expected:

```console
curl -s http://metadata.google.internal/computeMetadata/v1beta1/instance/name

...snip...
Legacy metadata endpoints are disabled. Please use the /v1/ endpoint.
...snip...
```

With the configuration of the second node pool set to `--workload-metadata-from-node=SECURE` , the following command to retrieve the sensitive file, `kube-env`, will now fail:

```console
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/kube-env

This metadata endpoint is concealed.
```

But other commands to non-sensitive endpoints will still succeed if the proper HTTP header is passed:

```console
curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name && echo

gke-default-cluster-second-pool-8fbd68c5-gzzp
```

Exit out of the pod:

```console
exit
```

You should now be back to your shell.

### Deploy PodSecurityPolicy objects

In order to have the necessary permissions to proceed, grant explicit permissions to your own user account to become `cluster-admin:`

```console
kubectl create clusterrolebinding clusteradmin --clusterrole=cluster-admin --user="$(gcloud config list account --format 'value(core.account)')"

clusterrolebinding.rbac.authorization.k8s.io/clusteradmin created
```

Next, deploy a more restrictive `PodSecurityPolicy` on all authenticated users in the default namespace:

```console
kubectl apply -f manifests/restrictive-psp.yml

podsecuritypolicy.extensions/restrictive-psp created
```

Next, add the `ClusterRole` that provides the necessary ability to "use" this PodSecurityPolicy.

```console
kubectl apply -f manifests/restrictive-psp-clusterrole.yml

clusterrole.rbac.authorization.k8s.io/restrictive-psp created
```

Finally, create a RoleBinding in the default namespace that allows any authenticated user permission to leverage the PodSecurityPolicy.

```console
kubectl apply -f manifests/restrictive-psp-clusterrolebinding.yml

rolebinding.rbac.authorization.k8s.io/restrictive-psp created
```

__Note:__ In a real environment, consider replacing the `system:authenticated` user in the ClusterRoleBinding or Namespace RoleBinding with the specific user or service accounts that you want to have the ability to create pods in the default namespace.

### Enable PodSecurity policy

Next, enable the PodSecurityPolicy Admission Controller:

```console
./enable-psp.sh -c default-cluster
```

This will take a few minutes to complete.

### Deploy a blocked pod that mounts the host filesystem

Because the account used to deploy the GKE cluster was granted cluster-admin permissions in a previous step, it's necessary to create another separate "user" account to interact with the cluster and validate the PodSecurityPolicy enforcement.  To do this, run:

```console
./create-demo-developer.sh -c default-cluster

Created service account [demo-developer].
...snip...
Fetching cluster endpoint and auth data.
kubeconfig entry generated for default-cluster.
```

The `create-demo-developer.sh` script will create a new service account named `demo-developer`, grant that service account the `container.developer` IAM role, create a service account key, configure gcloud to use that service account key, and then configure kubectl to use those service account credentials when communicating with the cluster.

Now, try to create another pod that mounts the underlying host filesystem `/` at the folder named `/rootfs` inside the container:

```console
kubectl apply -f manifests/hostpath.yml
```

This output validatates that it's blocked by PSP:

```console
Error from server (Forbidden): error when creating "STDIN": pods "hostpath" is forbidden: unable to validate against any pod security policy: [spec.volumes[0]: Invalid value: "hostPath": hostPath volumes are not allowed to be used]
```

Deploy another pod that meets the criteria of the `restrictive-psp`:

```console
kubectl apply -f manifests/nohostpath.yml

pod/nohostpath created
```

To view the annotation that gets added to the pod indicating which PodSecurityPolicy authorized the creation, run:

```console
kubectl get pod nohostpath -o=jsonpath="{ .metadata.annotations.kubernetes\.io/psp }" && echo

restrictive-psp
```

Congratulations! In this lab you configured a default Kubernetes cluster in Google Kubernetes Engine.  You then probed and exploited the access available to your pod, hardened the cluster, and validated those malicious actions were no longer possible.

## Validation

The following script will validate that the demo is deployed correctly:

```console
./validate.sh -c default-cluster
```

Replace the text `default-cluster` the name of the cluster that you would like to validate. If the script fails it will output:

```console
Fetching cluster endpoint and auth data.
kubeconfig entry generated for default-cluster.
```

## Tear Down

Log back in as your user account.

```console
gcloud auth login
```

The following script will destroy the Kubernetes Engine cluster.

```console
./delete.sh -c default-cluster

Fetching cluster endpoint and auth data.
kubeconfig entry generated for default-cluster.
Deleting cluster
Deleting cluster default-cluster...
...snip...
deleted service account [demo-developer@my-project-id.iam.gserviceaccount.com]
```

Replace the text `default-cluster` the name of the cluster that you would like to delete.

## Troubleshooting

### Errors about project quotas

If you get errors about quotas, please increase your quota in the project.  See [here][1] for more details.

## Relevant Materials

1. [Google Cloud Quotas][1]
1. [Signup for Google Cloud][2]
1. [Google Cloud Shell][3]
1. [Hardening your Cluster][4]
1. [PodSecurityPolicy][5]
1. [Restricting Pod Permissions][6]
1. [Node Service Accounts][7]
1. [Protecting Node Metadata][8]
1. [Launch Stages][9]
1. [Protecting Cluster Metadata][10]

[1]: https://cloud.google.com/compute/quotas
[2]: https://cloud.google.com
[3]: https://cloud.google.com/shell/docs/
[4]: https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster
[5]: https://cloud.google.com/kubernetes-engine/docs/how-to/pod-security-policies
[6]: https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#restrict_pod_permissions
[7]: https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster#use_least_privilege_sa
[8]: https://cloud.google.com/kubernetes-engine/docs/how-to/protecting-cluster-metadata#disable-legacy-apis
[9]: https://cloud.google.com/terms/launch-stages
[10]: https://cloud.google.com/kubernetes-engine/docs/how-to/protecting-cluster-metadata#concealment

Note, **this is not an officially supported Google product**.

