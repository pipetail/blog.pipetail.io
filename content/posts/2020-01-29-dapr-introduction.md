---
title: "DAPR: introduction to Distributed Application Runtime"
date: 2020-01-29T20:00:00+01:00
draft: false
images:
  - images/2020-01-29-dapr-introduction-title.png
authors:
  - stepan-vrany
tags:
  - microservices
  - kubernetes
---

At the moment, there are no doubts that transformation to the new
architectural pattern, microservices architecture, is happening.
Today, I don't want to emphasize that microservices architecture does
not solve everything. This transformation is happening and my
role here is to show you some possible ways how to minimize the struggle.

I'm not a software architect, but I can name few things I've seen when
I was helping clients with their projects:

- communication is complex
- management of application state is difficult
- when working with microservices, you need to tinker a lot with libraries or SDKs to achieve some architectural patterns (and you might end up with huge bunch of libraries)
- sometimes, you accidentally create ugly vendor lock-in

## Abstraction is the key

What if you can offload some of these concerns to the underlying
platform so you can keep the codebase small, lean and vendor-agnostic?

Well, that's exactly what DAPR does. It is able to handle
all the complicated logic, the application itself communicates
only with simple HTTP or gRPC interfaces.

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/0*3bULO0vBHIV2DKX6.png">}}

Note the blue blocks in the diagram. These blocks represent
the DAPR runtime. As we are talking about Kubernetes
native framework, DAPR runtime is represented by sidecar container.

Look at the following diagram. As DAPR runs in the same pod,
it shares the same network stack with the application container.

{{< figure src="https://blog-vrany-dev-assets.s3.eu-central-1.amazonaws.com/Dapr-7-e1571188815226.png">}}

Therefore all the DAPR-related communication is realized via
`localhost` or `127.0.0.1`. The configuration itself is handled
via `Components`, a custom resource created
together with DAPR control services. Following Component
describes the configuration for the Pub/Sub messaging using
[NATS](https://nats.io/).

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: messagebus
  namespace: sample-app
spec:
  type: pubsub.nats
  metadata:
  - name: natsURL
    value: "nats-client.nats-system.svc.cluster.local:4222"
```

When we create this component, DAPR then configures sidecars so
we can use the given Component via HTTP or gRPC abstraction. 

The injecting of the sidecars is controlled by Pod annotations,
for instance, the following set of annotations is saying that we
want to inject a DAPR sidecar and we want to identify this service
as `backend` and it's listening on TCP port `8080`.

```yaml
          annotations:
            dapr.io/enabled: "true"
            dapr.io/id: "backend"
            dapr.io/port: "8080"
```

Anyways, you can learn more about the key concepts from the
[official documentation](https://github.com/dapr/docs).
It does not cover all the parts but still, it's pretty extensive.

So now we can skip the theory and proceed to some fun stuff!

## Talk is cheap, show me the code

Today we're going to build a simple application with three main
components: frontend, backend, and worker. The whole application
will be doing pretty much nothing, but it should be enough
to get some idea about the concept of DAPR pub/sub model.

## Frontend

You can find the whole frontend service
[here](https://github.com/vranystepan/cncf-meetup-dapr-example-01/tree/master/frontend),
I know literally nothing about the frontend development so I've
chosen Vue framework cause the Internet is full of good examples
for this tool. 

The frontend bit has just a few form components and a few lines
of Javascript code. The function is obvious, take values
from the form components and send them to `/api/v1/order` endpoint.

```html
    <script>
        new Vue({
            el: '#example-1',
            data: {
                customerId: null,
                articleId: null,
                status: null,
            },
            methods: {
                submitOrder: function(e){
                    e.preventDefault();
                    axios.post('/api/v1/order', {
                        customer_id: this.customerId,
                        article_id: parseInt(this.articleId),
                    })
                    .then(result => {
                        this.status = "ok";
                        console.log(result);
                    })
                    .catch(error => {
                        this.status = "nok";
                    });
                },
            }
        })
    </script>
```

> In the base platform, we are using Traefik Ingress controller
> so we can route traffic based on the request path easily.
> Check `garden.yml` files for further details.

## Backend

With the knowledge of the frontend service, it's pretty obvious
what's the role of backend service: receive the message on 
given HTTP endpoint. When we receive the order, we want to send it
for further asynchronous processing via the message broker.

For this purpose, I've created a simple function which sends  
HTTP request to the DAPR sidecar:

```go
func sendMessage(topic string, message interface{}) error {
        json, err := json.Marshal(message)
        if err != nil {
                return fmt.Errorf("could not marshal message: %s", err)
        }

        _, err = http.Post(
                fmt.Sprintf("http://localhost:3500/v1.0/publish/%s", topic),
                "application/json",
                bytes.NewBuffer(json),
        )
        if err != nil {
                return fmt.Errorf("could not send message: %s", err)
        }
        return nil
}
```

Note the URL part, the URL always has a fixed structure and it
ends with the topic name. We'll be working with this topic in
the worker part. Now we just need to send the message:

```go
        err = sendMessage("order", order)
        if err != nil {
                handleError("could not send JSON message", 500, c)
                return
        }
```

> In this example I'm using type `interface{}` for the message.
> As you can figure out, it's pretty filthy, don't do such
> dirty exercises in your code!

## Worker
And finally, we're approaching the most interesting part: worker
which is basically subscriber to the topics.

First of all, we need to advertise the subscriptions we want to
receive from the message broker. It's pretty easy, we just need
to advertise those subscriptions as JSON array at
`/dapr/subscribe`.

```go
func main() {
        r := gin.Default()
        r.GET("/dapr/subscribe", advertiseDaprSubscriptions)
        r.POST("/order", handleOrderMessage)
        r.Run()
}

func advertiseDaprSubscriptions(c *gin.Context) {
        c.JSON(200, []string{"order"})
}
```

Then, we can just implement the subscriber itself.

```go
type Message struct {
        ID string `json:"id"`
        Data Order `json:"data"`
}

type Order struct {
        ArticleID  int    `json:"article_id"`
        CustomerID string `json:"customer_id"`
}

func handleOrderMessage(c *gin.Context) {
        var message Message
        err := c.BindJSON(&message)

        if err != nil {
                handleError("could not bind POST body", 500, c)
        }

        log.Println(message)

        c.JSON(200, []string{"order"})
}
```

## Give it a spin

When we bring all services up, we can observe a couple of things.
First of all, all the pods have sidecar injected.

```
kubectl get pods -n sample-app
NAME                                    READY   STATUS    RESTARTS   AGE
backend-v-0087b5c3e9-668f87b467-n5rp8   2/2     Running   0          5m34s
frontend-v-c1135e7f5d-7d7ffc4fc-jhhpx   2/2     Running   0          5m34s
worker-v-0087b5c3e9-7698bb897d-xrz5k    2/2     Running   0          5m34s
```

And when we view worker logs, we can find that DAPR was already
checking for the desired subscriptions.

```
[GIN-debug] [WARNING] Creating an Engine instance with the Logger and Recovery middleware already attached.

[GIN-debug] [WARNING] Running in "debug" mode. Switch to "release" mode in production.
- using env:        export GIN_MODE=release
- using code:       gin.SetMode(gin.ReleaseMode)

[GIN-debug] GET    /dapr/subscribe           --> main.advertiseDaprSubscriptions (3 handlers)
[GIN-debug] POST   /order                    --> main.handleOrderMessage (3 handlers)
[GIN-debug] Environment variable PORT is undefined. Using port :8080 by default
[GIN-debug] Listening and serving HTTP on :8080
[GIN] 2020/01/29 - 14:37:05 | 404 |       1.016µs |       127.0.0.1 | GET      /dapr/config
[GIN] 2020/01/29 - 14:37:05 | 200 |      61.846µs |       127.0.0.1 | GET      /dapr/subscribe
```

So let's just open the frontend and send some payload to the backend.
When we do so, we can review the result in the worker logs:

```
2020/01/29 14:44:09 {ab2360d8-8b0c-40fb-9851-991edffe77e4 {100 stepan@vrany.name}}
[GIN] 2020/01/29 - 14:44:09 | 200 |    1.046011ms |       127.0.0.1 | POST     /order
```

Great! We've managed to process our first message with DAPR!
What an awesome waste of computing resources, right?

## Wrap

I know that everything above is just an extremely stupid and
simple example. But please think about it a little!

We have managed to create a very minimalistic code here with minimal
number of external dependencies and we can also move the whole thing
to literally anywhere, as the only fixed dependency is just
Kubernetes framework. Rest of the common parts can be handled in the
same manner, create a component and consume it as HTTP endpoints or
gRPC methods. Easy.

You can find the whole codebase in my
[GitHub repository](https://github.com/vranystepan/cncf-meetup-dapr-example-01). It contains even the recipes
for the infrastructure. Just make sure you don't
use my domain name there. Also, please don't be offended 
by my code 😬

I will be talking about this stuff tomorrow at
[Cloud Native Prague meetup #7](https://www.meetup.com/Cloud-Native-Prague/events/267687926/).
Come and let's talk about pitfalls in the development of microservices!
