---
title: "AWS Systems Manager Session Manager: bye bye bastion hosts!"
date: 2020-02-24T07:00:00+01:00
draft: false
images:
  - images/2020-02-24-amazon-ssm-session-manager.png
authors:
  - stepan-vrany
tags:
  - aws
  - amazon
  - ssm
---
There are customers where public internet access is no go. But
at the same time you need to access your EC2 instances,
right? How would you approach this? Usually, we use bastion hosts,
that's basically a different name for jump host you can use 
to access internal resources. In AWS, you don't need to manage 
such extra instances and take care of all the low-level configuration.
Instead, you can leverage fully managed Session Manager from the
AWS Systems Manager suite!
<!--more-->

## Before you start
First, you need to make sure that your systems have SSM Agent installed.
There's [decent documentation available](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html)
but if you are using official AMI, you can skip this since SSM Agent
is already pre-installed. 

Also, your instances need proper IAM permissions. And that's actually
pretty simple task, just attach AWS managed policy
`AmazonSSMManagedInstanceCore` to your instances and that's it!
Alternatively, we can just copy&paste the content of this
managed role to the existing user-managed role.
Both scenarios work well. 

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeAssociation",
                "ssm:GetDeployablePatchSnapshotForInstance",
                "ssm:GetDocument",
                "ssm:DescribeDocument",
                "ssm:GetManifest",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:ListAssociations",
                "ssm:ListInstanceAssociations",
                "ssm:PutInventory",
                "ssm:PutComplianceItems",
                "ssm:PutConfigurePackageResult",
                "ssm:UpdateAssociationStatus",
                "ssm:UpdateInstanceAssociationStatus",
                "ssm:UpdateInstanceInformation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2messages:AcknowledgeMessage",
                "ec2messages:DeleteMessage",
                "ec2messages:FailMessage",
                "ec2messages:GetEndpoint",
                "ec2messages:GetMessages",
                "ec2messages:SendReply"
            ],
            "Resource": "*"
        }
    ]
}
```

## Viewing available sessions
When the instances are ready, we can view all the available session
in the System Manager.

{{< figure src="/images/2020-02-24-amazon-ssm-session-manager-01.png">}}

And you can even start a new session from here. It'll open a
new window with web-based terminal.

{{< figure src="/images/2020-02-24-amazon-ssm-session-manager-02.png">}}

However, it does not feel right for day-to-day operations 😂.
Let's connect there directly from the workstation. 


## Just one more step ...
It's just ssh, right? So we're almost ready,
we just need to quickly prepare our local
workstation by installing Session Manager plugin.
This plugin is available for all major platforms, just copy&paste
a few lines from the [documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
and that's pretty much it.

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

Now, we can just add following lines to `~/.ssh/config`
so shh command knows how to handle hosts starting with
`i-*` or `mi-*`.

```
host i-* mi-*
    ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
```

## Good old SSH
From now it's really straightforward. Get your instance id and
open the SSH session.

```bash
ssh ubuntu@i-0182d91e85d69cf00
```

Yeah, it's that simple. We can treat it as good old SSH
from here. No strings attached.

{{< figure src="/images/2020-02-24-amazon-ssm-session-manager-03.png">}}

## Key advantages of Session Manager service
The obvious was already mentioned: no need to manage own EC2
instances for bastion hosts.

But there's more of it. You can even control access to the instances 
with IAM! User with the following policy attached can access
all three instances mentioned in the `Resource` property. As always,
[everything is documented](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html) so suit
yourself. 

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:StartSession"
            ],
            "Resource": [
                "arn:aws:ec2:us-east-2:123456789012:instance/i-1234567890EXAMPLE",
                "arn:aws:ec2:us-east-2:123456789012:instance/i-abcdefghijEXAMPLE",
                "arn:aws:ec2:us-east-2:123456789012:instance/i-0e9d8c7b6aEXAMPLE"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:TerminateSession"
            ],
            "Resource": [
                "arn:aws:ssm:*:*:session/${aws:username}-*"
            ]
        }
    ]
}
```

And last but not least, you can review all the open session and you can even inspect the history. This will come handy in case of any audit 😏.
From this perspective, AWS Systems Manager Session Manager is even
more secure than traditional setups with bastion hosts (of course,
I'm not talking about over-engineered configurations).

## Wrap
Apparently, there's no need to stick with traditional bastion hosts,
AWS System Manager Session Manager can do all the job. Moreover,
you can granularly control SSH access via IAM. That's actually,
at least from my point of view, the most powerful feature.

**Say bye-bye to your jump hosts!**
