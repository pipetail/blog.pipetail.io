---
title: "Applications are not easy, tracing is: a brief introduction to OpenTelemetry"
date: 2020-02-09T10:00:00+01:00
draft: false
images:
  - 2020-02-09-opentelemetry-introduction-title.png
authors:
  - stepan-vrany
tags:
  - microservices
  - kubernetes
  - observability
  - tracing
---

I have great news! [OpenTelemetry will be in beta](https://medium.com/opentelemetry/opentelemetry-monthly-update-january-2020-73579f9cb979) soon!
What does it mean? Well, we can start instrumenting applications
directly with OpenTelemetry and we can skip its ancestors.

> Ehmm. Instrumenting? Ancestors? C'mon Stepan. What does it mean? 

My bad, let me step back and make it right. OpenTelemetry is pretty new project
which [merges OpenCensus and OpenTracing](https://opentelemetry.io/about/)
projects together. Both projects had the same vision: make the observability
of applications better with tracing. And now we're getting to the topic.
What's the tracing? What does it mean? 

Tracing is basically a technique to record information about a program's execution.
It means that you can instrument your code with some library to actually
capture what's happening when the application is processing something.
Certain activities can be divided into spans, spans can also represent the
hierarchy so the recorded frame (trace) can mimic all the application logic. 

The practical implications are obvious: when something's broken, you can identify
the exact part of the program without staring into log files. Also, if you're
experiencing long latencies, you can use visualization of your traces to
quickly find the part of the program responsible for such delays!

Try to imagine that we put in place some parallelism and we instrument it
with OpenTelemetry, this is the result:

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/2020-02-05/lightstep02.png">}}

With tracing, you have absolute visibility on what's your application is doing.

## (not so) deep dive into Golang

Previous examples come from [LightStep](https://lightstep.com/),
it's basically managed service for the collecting and visualizing spans from the applications. 
But perhaps you don't want to use third party service for
the local development as your only role is to actually instrument it somehow with
tracing. With OpenTelemetry it's no problem at all cause it's designed to be modular!

So let's just start with dummy exporter which is pushing spans to stdout.

```go
package main

import (
        "log"

        "go.opentelemetry.io/otel/api/global"
        "go.opentelemetry.io/otel/exporter/trace/stdout"
        sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func initTracerStdOut() {
    var err error
    exp, err := stdout.NewExporter(stdout.Options{PrettyPrint: false})
    if err != nil {
        log.Panicf("failed to initialize stdout exporter %v\n", err)
    }
    tp, err := sdktrace.NewProvider(sdktrace.WithSyncer(exp),
        sdktrace.WithConfig(sdktrace.Config{DefaultSampler: sdktrace.AlwaysSample()}))
    if err != nil {
        log.Panicf("failed to initialize stdout exporter %v\n", err)
    }

    global.SetTraceProvider(tp)
}
```

When we call `initTracerStdOut()` in the application code, it initializes global
trace provider which can be used for the creation of the Tracer instance in any
part of the application.

```go
func main() {

    initTracerStdOut()
    r := mux.NewRouter()
    r.HandleFunc("/", indexHandler)
    http.ListenAndServe(":8080", r)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
    tracer := global.TraceProvider().Tracer("index")
    _, span := tracer.Start(r.Context(), "test")
    fmt.Fprintf(w, "Hello World")
    span.End()
}
```

When we start this web server and the first HTTP request is sent there,
this is what we get in the console:

```json
{
    "SpanContext": {
        "TraceID":"32e936a2d17ec3c306789d1b9bf2d078",
        "SpanID":"2515276d23736f6d",
        "TraceFlags":1
    },
    "ParentSpanID":"0000000000000000",
    "SpanKind":1,
    "Name":"server1/test",
    "StartTime":"2020-02-05T12:59:39.969032441+01:00","EndTime":"2020-02-05T12:59:39.969043039+01:00",
    "Attributes":null,
    "MessageEvents":null,
    "Links":null,
    "Status":0,
    "HasRemoteParent":false,
    "DroppedAttributeCount":0,
    "DroppedMessageEventCount":0,
    "DroppedLinkCount":0,
    "ChildSpanCount":0
}
```

## Change the exporter. Profit.

Right, that's very interesting. But that's not something you want to use
in the production I guess. What's the added value, right?
And here we can leverage the modularity I was talking about. Let's say
we want to use LightStep (and I really recommend this tool!),
first of all, we need to prepare a new function to set the global
trace provider:

```go
package main

import (
        "log"

        "github.com/lightstep/opentelemetry-exporter-go/lightstep"
        "go.opentelemetry.io/otel/api/global"
        "go.opentelemetry.io/otel/exporter/trace/stdout"
        sdktrace "go.opentelemetry.io/otel/sdk/trace"
)


func initTracerLightstep(serviceName string, token string) {
    exporter, err := lightstep.NewExporter(
        lightstep.WithAccessToken(token),
        lightstep.WithServiceName(serviceName),
    )
    if err != nil {
        log.Panicf("failed to initialize stdout exporter %v\n", err)
    }

    tp, err := sdktrace.NewProvider(
        sdktrace.WithConfig(sdktrace.Config{
            DefaultSampler: sdktrace.AlwaysSample(),
        }),
        sdktrace.WithSyncer(exporter),
    )

    if err != nil {
        og.Panicf("failed to initialize stdout exporter %v\n", err)
    }
    global.SetTraceProvider(tp)
}
```

And then we can just call a different function in the `main` function:

```go
func main() {

    initTracerLightstep("svc", os.Getenv("LIGHTSTEP_TOKEN"))
    r := mux.NewRouter()
    r.HandleFunc("/", indexHandler)
    http.ListenAndServe(":8080", r)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
    tracer := global.TraceProvider().Tracer("index")
    _, span := tracer.Start(r.Context(), "test")
    fmt.Fprintf(w, "Hello World")
    span.End()
}
```

This is the visualized equivalent of the JSON I was showing you before:

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/2020-02-05/lightstep01.png">}}


## Wrap

I hope it was not so technical today. My goal was to show you the modularity
of tracing exporters. Also, I wanted to articulate that it really makes
sense to use tracing even on a small scale. If you are doing local development,
you can use all-in-one Jaeger installation or you can leverage free tier of
some SaaS such as [LightStep](https://lightstep.com/).

There's no good or bad solution for tracing,the key takeaway here is:

> do not underestimate tracing, do not operate your applications with zero visibility. 
> Everyone can benefit from tracing. Operations, Developers. Everyone. Use tracing!

**Next time** I'd like to cover context propagation between services and some basic tagging of spans.
Especially the propagation is really exciting topic, looking forward to sharing with you more insights.

PS I'll have an ignite talk about OpenTelemetry at [DevOps Days Prague 2020](https://www.devopsdays.cz/).
If you're attending this event, feel free to reach me and let's discuss this topic. 

