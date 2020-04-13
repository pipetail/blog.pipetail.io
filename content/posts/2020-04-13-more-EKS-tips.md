---
title: "More EKS tips to make your life easier"
date: 2020-04-13T07:00:00+01:00
draft: false
images:
  - images/2020-04-13-more-EKS-tips.png
authors:
  - stepan-vrany
tags:
  - aws
  - amazon
  - eks
  - kubernetes
  - security
---

We've spent most of the last month on implementing EKS. Surprisingly, we're always solving the same
concerns no matter what project we're working on. Here's couple of tips for your EKS clusters!

## Skip kube2iam, go directly with  IAM Roles for Service Accounts

Kube2iam is amazing tool. I really like it and it helped me with granular control
access in couple of projects. However, there's a better solution that is
supported out of the box: [IAM roles for services accounts](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html).

> Why is it better? We're practically removing one moving part and that's IMO always good.

In essence, we just need to create a new identity provider in the IAM console and that's pretty much it. 
Then, EKS control plane is mutating all the pods that are using ServiceAccount with 
`eks.amazonaws.com/role-arn` annotation.

With all the configuration supplied by the mutating webhook AWS SDK now knows how to
obtain credentials to AWS so your application can interact with AWS API in strictly
controlled fashion. This works with all main stream applications, 
to name a few: Cluster Autoscaler, ALB Ingress Controller or even Gitlab CI runner for Kubernetes.
It's all about supported SDK versions. [Here's the list.](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts-minimum-sdk.html)

## Tag your ASGs properly for the maximum savings

EKS environment is well suited for scaling from zero. This comes handy for downscaling
after working hours (for instance for preview environments) or upscaling of instance
groups for some specialized workload (e.g. batch processing or training of alghorithms).

All mentioned is enabled by
[Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler),
but how can Cluster Autoscaler know what ASG it's supposed to scale up when any
nodes with such Kubernetes labels don't exist yet?

Here's an easy answer: tags. This part is [well documented](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-can-i-scale-a-node-group-to-0) but it sometimes it might
be complicated to find the right piece of docs, right?

Long story short, if your nodes from the single ASG have some labels (`--node-labels` kubelet flag),
always make sure that ASG has the same labels in the following format:

```terraform
    {
      key                 = "k8s.io/cluster-autoscaler/node-template/label/role"
      value               = "some-random-label"
      propagate_at_launch = true
    }
```

With those tags assigned Cluster Autoscaler knows which ASG it is supposed to spin up when we
schedule workload with `nodeSelector` specified.

## Try to experiment with Cluster Autoscaler priority expander

Did you know that Cluster Autoscaler has a functionality called expanders that can
change the way how Cluster Autoscaler behaves? It was sort of a new information,
we've found this last week while implementing setup for some lower priority jobs.

Again, we'll rather use some story to get you into this topic. So try to imagine
that you have some lower priority jobs that are not really critical for your application.
So in this case it does not really make sense to pay for 99.something uptime and we can
use some less reliable spot instances with lower price.

But when we are requesting spot instances, the result is always unknown due to nature of it
so it's absolutely fine. Now I need to return to the part where I was telling you about
low priority jobs. They are low priority, that's still valid. But I need them eventually,
I can't wait for a week till my request will be fulfilled. So what's the process here?

**[Priority exander!](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/expander/priority)** With this beast enabled you can cover such edge cases. 

All you need is start Cluster Autoscaler with `--expander=priority` and create a new ConfigMap
in the same namespace where the Cluster Autoscaler runs.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |-
    10: 
      - name-of-asg-with-on-demand.*
    50: 
      - name-of-asg-with-spot.*
```

Now, cluster autoscaler will try to scale up ASG `name-of-asg-with-spot` first
and if it fails it just continues with ASG `name-of-asg-with-on-demand`.

> From our personal experience, it's also a good idea to experiment with `--max-node-provision-time`
> flag a bit. By default it waits 15 minutes but this might be too long in some cases.
> And one additional tip, always do some PoC for your use cases. Documentation is
> slightly lacking so you won't cause any harm by testing it before it reaches production 😏

## Wrap
Last month was absolutely thrilling. We've learned a lot of new things about EKS and Kubernetes
itself and we're so happy that we can share them with you right away!
Do you have more tips or are you having terrible times with some of mentioned? Just mention us
([@MarekBartik](https://twitter.com/MarekBartik) [@MstrsObserver](https://twitter.com/MstrsObserver))
on Twitter!