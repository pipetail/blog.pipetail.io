---
title: "Helmfile basics: get your Helm flow organized"
date: 2020-07-13T10:00:00+01:00
draft: false
images:
  - images/2020-07-13-helm.png
authors:
  - stepan-vrany
tags:
  - helm
  - kubernetes
  - CI/CD
---
There are no doubts that Helm is extremely popular tool,
perhaps the most popular tool in the whole Kubernetes ecosystem.
But are there any ways how to streamline deployments of complex applications?
<!--more-->

I'm not big fan of Helm when it comes to delivery of applications.
When used with inappropriate amount of vigilance, it can generate a huge mess (technical debt).
I've seen this couple of times in different places,
a good example is huge Helm release used for all the services.

This might be working for smaller applications, but when you grow and
adding more services, this can become a **major blocker** of your deployment
velocity:

- you always need to collect information for all the services so you are able to populate Helm values properly
- when using `--atomic` flag, unimportant small application can break and revert the whole deployment
- bigger release means longer execution time of the deployment (more things can go wrong in that time period)
- small change in monolithic Helm chart might cause butterfly effect

That's not complete list of course. But yeah, that's the reality, Helm is here and it won't go away any time soon.
So let's try to come with some solution!

## How we got here

First we need to think about how we got here. Why do we use monolithic Helm charts?
I'd say it's mainly due to fear of repetition while installing components of the
application (services). That's a good point, when installing application
with 10 services, we essentially need to run `helm upgrade` ten times.

Or we can create all-in-one chart that simplifies this a bit. Or we can create
all-in-one chart that simplifies this a bit. Alternatively we can create an envelope
chart and use separate charts for all the applications.

So this is how we got here. All the stuff that I've mentioned before applies here.

## Enter the Helmfile

A few weeks ago I've discovered Helmfile which is basically wrapper for Helm that
can simplify installation of multiple charts. But there's a difference:
Helmfile does not combine everything to the single Helm release.

Let's check quick and dirty example of Helmfile for the application composed from
two services. 

```yaml
helmDefaults:
  atomic: true
  wait: true
  timeout: 3600
releases:

  - name: backend
    namespace: backend-production
    createNamespace: true
    labels:
      app: backend
    chart: ./charts/backend
    missingFileHandler: Error
    set:
      - name: image.tag
        value: {{ env "BACKEND_VERSION" }}
    values:
      - "./environments/{{ .Environment.Name }}/backend-values.yaml"
      - "./environments/{{ .Environment.Name }}/values.yaml"
    secrets:
      - "environments/{{ .Environment.Name }}/backend-secrets.enc.yaml"
      - "environments/{{ .Environment.Name }}/secrets.enc.yaml"

  - name: frontend
    namespace: frontend-production
    createNamespace: true
    labels:
      app: frontend
    chart: ./charts/frontend
    missingFileHandler: Error
    set:
      - name: image.tag
        value: {{ env "FRONTEND_VERSION" }}
    values:
      - "./environments/{{ .Environment.Name }}/frontend-values.yaml"
      - "./environments/{{ .Environment.Name }}/values.yaml"
    secrets:
      - "environments/{{ .Environment.Name }}/frontend-secrets.enc.yaml"
      - "environments/{{ .Environment.Name }}/secrets.enc.yaml"

environments:
  default:
  production:
```

You can see a couple of things there:

- global flags for Helm can be defined there
- releases can be installed to different namespaces
- helmfile somehow distinguishes between values and secrets (we will talk about this later on)
- Helmfile is able to handle different environments
- releases can have labels
- we can even use environment variables!

Now, let's go through some basic features that can simplify deployment process.
I'm gonna create extra topic for each feature that I find interesting for this purpose.

### Labels

There are situations when we want to install all the releases at the same time.
Deployment to production is not one of them. But let's go back to the valid situations.
How about review environments? That's a good example, right? In such case, you
can simple run `helmfile apply`.

```bash
helmfile apply
```

End of story. Now we have Helm releases `backend` in the namespace `backend-production`
and `frontend` in the namespace `frontend-production`.

Now let's focus on the production scenario when we want to install only on release at time.

```bash
helmfile --environment production --selector app=backend diff
```

This command installs only one release: `backend` to the namespace `backend-production`.

### Environments

In the previous sections you may notice `--environment` flag. That's Helmfile internal
functionality that introduces some templating functions directly to the `helmfile.yaml`
specification.

With this feature you can load different values for different environments:

```yaml
    values:
      - "./environments/{{ .Environment.Name }}/backend-values.yaml"
      - "./environments/{{ .Environment.Name }}/values.yaml"
```

And guess what, you can use it even for namespaces:

```yaml
releases:
  - name: backend
    namespace: backend-{{ .Environment.Name }}
```

With this feature we just need to create a good directory structure and that's it: 

```bash
.
├── charts
│   ├── backend
│   └── frontend
├── environments
│   ├── default
│   │   ├── backend-secrets.enc.yaml
│   │   ├── backend-values.yaml
│   │   ├── secrets.enc.yaml
│   │   └── values.yaml
│   └── production
│       ├── backend-secrets.enc.yaml
│       ├── backend-values.yaml
│       ├── secrets.enc.yaml
│       └── values.yaml
├── helmfile.yaml
└── README.md
```

### Environment variables
The typical use case for environment variables is updating of service versions.
In Kubernetes terminology we're basically switching images.

Traditionally we process the version in the orchestration tool and then we
provide it as `--set` flag to Helm. With Helmfile, you can skip this
part and you can use environment variables as the reference directly in
helmfile.yaml.

```yaml
    set:
      - name: image.tag
        value: {{ env "BACKEND_VERSION" }}
```

This feature is rather for machines (automation engines) but still I find
this as a really useful one.

### Secrets management

Helmfile integrates with [Helm secrets plugin](https://github.com/zendesk/helm-secrets) for Helm.
With this plugin you have an ability to store encrypted secrets in git
repository using [SOPS](https://github.com/mozilla/sops) tool from Mozilla engineering team.

I don't want to go soo deep to SOPS internals but here are the key takeaways:
- secrets can be encrypted with managed solutions like AWS KMS or GCP KMS
- SOPS is encrypting values only, this means that keys are visible and you can see the context while doing reviews for changes

Here's the example for the second takeaway:

```yaml
global:
    secrets:
        GLOBAL_SECRET: ENC[AES256_GCM,data:LuHVrAE6nkFH,iv:EHm8cPw8dfaHQSyqN0YKEpK/53gv1ljL5zYWACqUP2E=,tag:Rx9bcfZ3XCJph50wWKYAew==,type:str]
```

Now let's just connect this SOPS stuff with Helmfile. All you need to know is
that Helmfile is handling decryption process and then it merges secrets with values.

All you need to know is that Helmfile is handling decryption process and then it merges secrets with values. There's no magic there, all you need to do is refer values as usual:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}
type: Opaque
data:
  {{- range $key, $value := .Values.global.secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
```

## Wrap
Is it all you can do with Helmfile? Hell no! Helmfile has a lot of features
that I did not cover in this blog post. However I was mainly focusing on
release cycle of applications with Helm so that's why I've named here only few features.

Let's wrap this blog post with my advice: try to create not so complex Helm charts
and if you need to compose more things together, use rather some orchestration tool
without adding more complexity to charts. Helmfile can serve you well
for this purpose and it also does not create any lock-in so you can switch
back to plain Helm anytime.

