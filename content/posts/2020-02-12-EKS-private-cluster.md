---
title: "More complicated EKS scenarios: EKS managed worker nodes without internet access"
date: 2020-02-12T08:00:00+01:00
draft: false
images:
  - images/2020-02-12-EKS-private-cluster-title.png
authors:
  - stepan-vrany
tags:
  - aws
  - kubernetes
  - eks
---

Are you using EKS managed worker
pools? If you don't have any specific reasons for not using them, you should.
It saves tons of time plus it boosts the "managed Kubernetes" feeling.
However, this pretty new offering did not cover one specific use case:
cluster with no Internet access.
<!--more-->

By default,
[workers need Internet access](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)
so they can pull Docker images and register to the control plane. On the other hand,
no internet access is a pretty common requirement, especially in
regulated businesses.

So how to find some common ground here?

> For the record, it really does not work by default.
> When we put everything to the private subnets with no outbound
> Internet access, workers can't join the cluster. 

## Community for the rescue

If you know me, you know what I did. [Search engine](https://duckduckgo.com/)!
And I was very successful cause I've found this GitHub issue after five
minutes of searching. What's going on there?

[Mike Stefaniak](https://github.com/mikestef9) from the EKS team is saying there
that it can work as long as you set up the other required PrivateLink
endpoints correctly. 

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/2020-02-11/gh01.png">}}

Moreover, there's also a link to the [GitHub repository](https://github.com/jpbarto/private-eks-cluster/blob/master/cloudformation/network.yaml)
with some CloudFormation samples. Challenge accepted. I'm gonna build it 💪

## Terraforming the CloudFormation stack

I'm not that much into CloudFormation. Not yet.
So I had to rewrite it to Terraform first.
Check the key components below, I'll also add some explanation.

**VPC settings**

Note the property `enable_dns_support`, this part is required by
private EKS endpoint. [See more details in the documentation](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html).

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  tags = {
    "kubernetes.io/cluster/cl01" = "shared"
  }
}
```

**Private subnets**

Also, let's add some basic private networks.

```hcl
resource "aws_subnet" "private-0" {
  availability_zone = "eu-central-1a"
  cidr_block        = "10.20.1.0/24"
  vpc_id            = aws_vpc.main.id

  tags = {
    "kubernetes.io/cluster/cl01" = "shared"
  }
}

resource "aws_subnet" "private-1" {
  availability_zone = "eu-central-1b"
  cidr_block        = "10.20.2.0/24"
  vpc_id            = aws_vpc.main.id

  tags = {
    "kubernetes.io/cluster/cl01" = "shared"
  }
}

resource "aws_subnet" "private-2" {
  availability_zone = "eu-central-1c"
  cidr_block        = "10.20.3.0/24"
  vpc_id            = aws_vpc.main.id

  tags = {
    "kubernetes.io/cluster/cl01" = "shared"
  }
}
```

**Endpoint for EC2 API**

```hcl
resource "aws_security_group" "endpoint_ec2" {
  name   = "endpoint-ec2"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "endpoint_ec2_443" {
  security_group_id = aws_security_group.endpoint_ec2.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks = [
    10.20.1.0/24, // private subnet 1
    10.20.2.0/24, // private subnet 2
    10.20.3.0/24, // private subnet 3
  ]
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-central-1.ec2"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = [
    aws_subnet.private-0.id,
    aws_subnet.private-1.id,
    aws_subnet.private-2.id,
  ]

  security_group_ids = [
    aws_security_group.endpoint_ec2.id,
  ]
}
```

**Endpoint for ECR/Docker APIs**

```hcl
resource "aws_security_group" "endpoint_ecr" {
  name   = "endpoint-ecr"
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group_rule" "endpoint_ecr_443" {
  security_group_id = aws_security_group.endpoint_ecr.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks = [
    10.20.1.0/24, // private subnet 1
    10.20.2.0/24, // private subnet 2
    10.20.3.0/24, // private subnet 3
  ]
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-central-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = [
    aws_subnet.private-0.id,
    aws_subnet.private-1.id,
    aws_subnet.private-2.id,
  ]

  security_group_ids = [
    aws_security_group.endpoint_ecr.id,
  ]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-central-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids = [
    aws_subnet.private-0.id,
    aws_subnet.private-1.id,
    aws_subnet.private-2.id,
  ]

  security_group_ids = [
    aws_security_group.endpoint_ecr.id,
  ]
}
```

**Endpoint for s3 API**

In this part, we're associating s3 private gateway with our private
subnets' routing tables.
[See more details in the documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpce-gateway.html).
We need this API as images are stored in S3 buckets. So when it's not enabled,
nodes won't be able to start essential services (pods).

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-central-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private-0.id,
    aws_route_table.private-1.id,
    aws_route_table.private-2.id,
  ]
}

resource "aws_route_table" "private-0" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "private-1" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "private-2" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private-0" {
  subnet_id      = aws_subnet.private-0.id
  route_table_id = aws_route_table.private-0.id
}

resource "aws_route_table_association" "private-1" {
  subnet_id      = aws_subnet.private-1.id
  route_table_id = aws_route_table.private-1.id
}

resource "aws_route_table_association" "private-2" {
  subnet_id      = aws_subnet.private-2.id
  route_table_id = aws_route_table.private-2.id
}
```

**EKS**

Now are somehow ready to start the control plane.
Please note I don't mention there IAM resources and Security
Groups as it would make the whole post even bigger.
But don't worry, Hashicorp prepared a [beautiful tutorial](https://learn.hashicorp.com/terraform/aws/eks-intro)
so you can use those. 

In the following example note the property `vpc_config.endpoint_private_access`.
This is the private EKS endpoint I was talking about.

```hcl
resource "aws_eks_cluster" "master" {
  name     = var.cluster_name
  role_arn = aws_iam_role.default-master.arn

  vpc_config {

    subnet_ids = [
      aws_subnet.private-0.id,
      aws_subnet.private-1.id,
      aws_subnet.private-2.id,
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs = [
      "0.0.0.0/0"
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_master_default_policy,
    aws_iam_role_policy_attachment.eks_master_default_service_policy,
  ]
}
```

And that's pretty much it for the control plane.
Let's proceed to managed worker nodes!

```hcl
resource "aws_eks_node_group" "aza" {
  cluster_name    = aws_eks_cluster.master.name
  node_group_name = "AZa"
  node_role_arn   = aws_iam_role.default-worker.arn
  instance_types  = ["t3.small"]
  subnet_ids = [
    aws_subnet.private-0.id,
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.default-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.default-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.default-AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "azb" {
  cluster_name    = aws_eks_cluster.master.name
  node_group_name = "AZb"
  node_role_arn   = aws_iam_role.default-worker.arn
  instance_types  = ["t3.small"]
  subnet_ids = [
    aws_subnet.private-1.id,
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.default-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.default-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.default-AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "azc" {
  cluster_name    = aws_eks_cluster.master.name
  node_group_name = "AZc"
  node_role_arn   = aws_iam_role.default-worker.arn
  instance_types  = ["t3.small"]
  subnet_ids = [
    aws_subnet.private-2.id,
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.default-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.default-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.default-AmazonEC2ContainerRegistryReadOnly,
  ]
}
```

Please note that we're using 3 managed node groups. That's because we are
following the [official recommendation](https://github.com/awsdocs/amazon-eks-user-guide/blob/master/doc_source/managed-node-groups.md) about the stateful applications
and cluster autoscaler. In any perspective, this setup can't cause any harm.

## Rise of the EKS cluster

We're ready to go. Let's give it a spin! The creation of such a setup
takes almost 20 minutes. I usually use such time for emailing
or Slack conversations but there might be a better way to utilize that 😄

```bash
terraform apply
```

After 20 minutes, we can view our brand new cluster in the console.

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/2020-02-11/eks.png">}}

It's truly beautiful and guess what, even all the Kubernetes
components are up and running! This means that worker
nodes were able to pull everything via configured private endpoints.

```bash
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
kube-system   aws-node-687nk             1/1     Running   0          88s
kube-system   aws-node-mppfc             1/1     Running   0          78s
kube-system   aws-node-s9d4z             1/1     Running   0          82s
kube-system   coredns-5b5455fd88-mdzs5   1/1     Running   0          5m19s
kube-system   coredns-5b5455fd88-znqmz   1/1     Running   0          5m19s
kube-system   kube-proxy-d5jbs           1/1     Running   0          82s
kube-system   kube-proxy-fhsxt           1/1     Running   0          88s
kube-system   kube-proxy-w2sbp           1/1     Running   0          78s
```

## Wrap

Let's summarize the specification of this setup:

- 3 private subnets
- [VPC endpoints for ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html#ecr-vpc-endpoint-considerations)
- EC2 endpoint
- S3 endpoint
- EKS control plane with private endpoint
- no internet access

We've just witnessed that it is absolutely possible to
create totally isolated clusters even for the most demanding
customers. Moreover, official documentation
[will reflect this setup soon](https://github.com/aws/containers-roadmap/issues/298#issuecomment-584403418)! Don't forget that such setup can't
pull images from the public repositories, so there's always an
extra step needed for each application deployed: pushing its images to the
ECR repository.

Seriously, I'm really glad that AWS is visible on GitHub and they
actually care about the users of their products.
I'd be totally lost without that advice I got there.
