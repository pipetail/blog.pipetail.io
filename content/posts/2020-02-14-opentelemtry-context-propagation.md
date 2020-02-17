---
title: "Applications are not easy, tracing is: context propagation"
date: 2020-02-17T19:00:00+01:00
draft: false
images:
  - images/2020-02-09-opentelemetry-introduction-title.png
authors:
  - stepan-vrany
tags:
  - microservices
  - kubernetes
  - observability
  - tracing
---

A few weeks ago I've published my [introduction to the tracing with OpenTelemetry
instrumentation](https://blog.pipetail.io/posts/2020-02-09-opentelemetry-introduction/).
I was trying to explain there that tracing has some value even in standalone applications. It was just a recommendation, but today we're gonna talk about scenarios where tracing
is a must: distributed systems.
<!--more-->

## Motivation

In traditional standalone monoliths, everything is happening in the same process. Communication between components is pretty reliable and fast. But when we shift to a
distributed model, suddenly we have to maintain complex communication between services.

Now imagine some real-life scenario, when you see rising 500 errors at your API gateway,
the root cause can be buried deep in your distributed application. 
The API gateway is sending requests to service A, service A is
sending requests to the service B... 
What would you do now?

## Propagating trace context is the key

What if we can put execution details of the different services under the same
trace so we can observe the complete life cycle of the event from one place?
That's actually the idea of context propagation. When we're delegating some work
to other components within the distributed application, we mark such event
appropriately so the trace can be continued no matter which service is
actually executing.

This picture comes from LightStep, you can see there a trace for
the event which happened in the distributed application with two services.

{{< figure src="/images/2020-02-17/tracing1.png">}}

How was I able to continue with the same trace in the different service?

## Injecting the context

Because we're starting with the execution in the service `a`,
we're gonna use pretty much the same code as in the previous article.

```go
func indexHandler(w http.ResponseWriter, r *http.Request) {
    tracer := global.TraceProvider().Tracer("index")
    _, span := tracer.Start(r.Context(), "test")
    fmt.Fprintf(w, "Hello World")
    span.End()
}
```

But now we need to send an HTTP request to the service `b`. This is the
interesting part, we need to use the same HTTP request to transmit
the information about the trace context. Let's just add HTTP request
and see how we can inject the context with the OpenTelemetry library.

```go
func indexHandler(w http.ResponseWriter, r *http.Request) {
    tracer := global.TraceProvider().Tracer("index")
    ctx, span := tracer.Start(r.Context(), "test")

    req, _ := http.NewRequest("GET", "http://localhost:8081/", nil)
    httptrace.Inject(ctx, req)
    res, err := client.Do(req)
    if err != nil {
        http.Error(w, err.Error(), 500)
    }

    fmt.Fprintf(w, "Hello World svc1")
    span.End()
}
```

Note this part:

```go
httptrace.Inject(ctx, req)
```

We're actually modifying the HTTP request there. Curious about the content?
Me too! Let's check all the headers.

```json
{
  "Traceparent": [
    "00-e33455b57a89a9660afacf9fc16cfbbb-8c5d2880e8cece90-01"
  ]
}
```

You can see all the details about the context propagation in the
[official W3C documentation](https://www.w3.org/TR/trace-context/).
It's pretty straightforward, recommended read. 

## Extracting the context
Now, we just need to reverse this action and extract the context, right?
It's as easy as injecting. OpenTelemetry library for Go contains
`httptrace.Extract()` function so you can get parent span details
with a single line of code.

```go
func indexHandler(w http.ResponseWriter, r *http.Request) {
    tracer := global.TraceProvider().Tracer("index")
    _, _, spanCtx := httptrace.Extract(r.Context(), r)

    _, span := tracer.Start(
      r.Context(),
      "hello",
      trace.ChildOf(spanCtx),
    )

    fmt.Fprintf(w, "Hello World svc2")
    span.End()
}
```

## Wrap
Today we've learned that context propagation is basically about some
sort of manipulation with HTTP headers. It was pretty easy, right?
Well, that's why we called this series "Applications are not easy,
tracing is." That's just true.

Next time we're gonna show you how to add some diagnostic data to spans.
It'll be fun!

---

If you want to learn more about Go instrumentation,
please follow this [awesome blog post at the LightStep blog](https://docs.lightstep.com/otel/golang-get-started-with-opentelemetry).
