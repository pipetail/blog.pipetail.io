---
title: "GitLab Runner on EKS"
date: 2020-03-05T08:00:00+01:00
draft: false
images:
  - images/2020-03-05-gitlab-cicd.png
authors:
  - marek-bartik
tags:
  - aws
  - eks
  - gitlab
  - ci/cd
---

GitLab-CI/CD is a great and powerful product for CI/CD pipelines. Hosted gitlab.com solution offers shared runners and some usage minutes based on your paid plan (even if the free tier). Though you might want to run your own runner in your private or public cloud. I will show how to run GitLab runner on AWS using terraform, Elastic Kubernetes Service and GitLab kubernetes integration.
<!--more-->

## When not to use shared runners
Shared runners can be very slow and you are limited to "CI pipeline minutes" per month based on your [paid plan](https://about.gitlab.com/pricing/). You could always buy extra minutes but if you run a lot of pipelines, things might get expensive.

Another reason not to use shared runners can be **security concerns**. Processing sensitive data might be a no-go for a lot of corporations.

Luckily GitLab allows using **self-hosted gitlab runners**! You can run a single Go binary on a variety of OSes. GitLab runners have the concept of [executors](https://docs.gitlab.com/runner/executors/README.html#compatibility-chart), currently supported executors are:

- shell
- Docker
- Docker Machine
- Docker Machine SSH
- Parallels
- VirtualBox
- SSH
- Kubernetes

These executors allow running your runners with additional features like private container registry, interactive web terminal, cache, artifacts, etc. Based on the executor used you might find harder or easier to debug problems, cache, persist and share build assets and dependencies and scale / utilize your compute.


## Kubernetes executor
We will pick Kubernetes executor as we are already familiar with it and it is quite easy to use it. It is relatively simple to debug problems and great to use at bigger scale to **better utilize our compute resources**.

You could go through the pain of deploying it yourself on a Kubernetes cluster and registering it in GitLab or you could use [GitLab Runner Helm Chart](https://docs.gitlab.com/runner/install/kubernetes.html). Helm is a package manager for kubernetes (think npm for kubernetes).

However, we can simplify the previous step and not deploy the chart ourselves! GitLab has a [Kubernetes Integration](https://docs.gitlab.com/ee/user/project/clusters/index.html) to create new or add existing kubernetes clusters. As of now it supports **Google Kubernetes Engine** (Google Cloud Platform) and **Elastic Kubernetes Service** (Amazon Web Services) natively but you should be able to add any kubernetes cluster no matter where it runs.

Integration with GKE seems a bit more seamless than the one for EKS (as of now) at least for creating new clusters. Anyway, I don't want GitLab to provision EKS cluster for me. I will provision it myself (or I could use an existing one) and just add it to the integration.

## Provision the AWS resources with terraform

We will use terraform to provision a bunch of AWS resources, including the EKS cluster.

We will use VPC and EKS modules (now with added support for the new EKS managed groups) to easily provision all the necessary resources. Here is a short example:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 9.0"

  cluster_name = local.cluster_name
  subnets      = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 50
  }

  node_groups = {
    example = {
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1

      instance_type = "m5.large"
    }
  }

  map_roles    = var.map_roles
  map_users    = var.map_users
  map_accounts = var.map_accounts
}
```

You might probably want to use **spot instances**, but for the sake of keeping this demo simple, we will just stick with the defaults.

Check `variables.tf` for default values. If you want to provide a more sane values or change a region, you can create a `*.auto.tfvars` file that will be automatically used with following terraform commands.

```bash
echo <<EOF >ci.auto.tfvars
environment   = "ci"
region        = "eu-central-1"
map_accounts = ["111111111YOUR_ACCOUNT_ID"]

EOF
```

Finally let's provision all the resources. Execute these one by one to see what is going to happen.

```bash
terraform init
terraform plan -out planfile
terraform apply planfile
```

## kubectl all the things!

We will add a service account for GitLab to our new kubernetes cluster. For simplicity we follow the [official docs](https://gitlab.com/help/user/project/clusters/add_remove_clusters.md#add-existing-cluster) and giving the service account a `cluster-admin` role.

```yaml
# eks-admin-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eks-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: eks-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: eks-admin
  namespace: kube-system
```

In the previous step there was a *kubeconfig* generated for us in the current directory. We can use it to apply the previous yaml on our kubernetes cluster.

```bash
KUBECONFIG=./kubeconfig_* kubectl apply -f eks-admin-sa.yaml
```

## gather the information

Now let's fetch all the necessary information we need to set up the GitLab k8s integration.

```bash
echo "Kubernetes cluster name:"
terraform output kubernetes_cluster_name
echo ""

echo "API URL:"
terraform output API_URL
echo ""

echo "CA Certificate:"
kubectl -n kube-system get secret \
  -o jsonpath='{.items[?(@.metadata.annotations.kubernetes\.io/service-account\.name=="default")].data.ca\.crt}'\
   | base64 --decode
echo ""

echo "Service Token:"
 kubectl -n kube-system get secret \
   -o jsonpath='{.items[?(@.metadata.annotations.kubernetes\.io/service-account\.name=="eks-admin")].data.token}'\
   | base64 --decode
echo ""
```

When you save the changes, you should get an information confirming successfully adding a kubernetes cluster to GitLab.

## install tiller and runners

When the integration was successfully added and verified to work, we can install Helm tiller (server part of helm that will install the rest of the things we need).

Click on Install:
{{< figure src="/images/2020-03-05-install-tiller.png">}}



When that is done, we will install GitLab runner too:
{{< figure src="/images/2020-03-05-install-gitlab-runner.png">}}


## testing it
Now go to `CI/CD` pane and see if this runner is enabled. Also you might want to disable your shared runners.

{{< figure src="/images/2020-03-05-runners-activated.png">}}

Run a pipeline and see if it is being run on the new runner in EKS. Check both the GitLab UI - detail of the pipeline stages:
{{< figure src="/images/2020-03-05-pipeline-working-ui.png">}}

and the cluster using `kubectl get pods --all-namespaces`:
{{< figure src="/images/2020-03-05-pipeline-working-terminal.png">}}

Yay, it works!

## to finish

Let's summarize the specification of this setup:

- EKS cluster with managed nodes
- GitLab Runners installed using GitLab Kubernetes Integration


You should take a look at few more stuff:
- how to optimize build cache using in-cluster distributed Minio cache
- using spot instances in EKS when they are available in EKS managed workers
- having **cluster autoscaler** in the cluster to autoscale the worker nodes based on demand
