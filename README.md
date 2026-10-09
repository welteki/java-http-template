# OpenFaaS Java HTTP template

This repository contains a Java 21 LTS template for OpenFaaS using Vert.x and Gradle. Your function implements a Vert.x `Handler<RoutingContext>`, giving you control over the HTTP request and response, including paths, query parameters, headers and status codes.

The JVM stays running between invocations. The OpenFaaS of-watchdog forwards HTTP requests to the Vert.x server, so each invocation uses the same application process and handler instance.

| Template | Java | HTTP framework | Build tool | Base image |
| --- | --- | --- | --- | --- |
| `java21-vertx` | 21 LTS | Vert.x 5.2.1 | Gradle 9.8.1 | Eclipse Temurin / Ubuntu Noble |

## Get the template

You need Docker and `faas-cli`. Building a function does not require Java or Gradle on your machine: both are provided by the build container.

Pull the template into your function project:

```bash
mkdir java-functions
cd java-functions

faas-cli template pull https://github.com/welteki/java-http-template
faas-cli new --list
```

The available templates will include `java21-vertx`.

Create a function, replacing `ghcr.io/your-user` with your container registry prefix:

```bash
faas-cli new hello-java --lang java21-vertx --prefix ghcr.io/your-user
```

This creates the following function files alongside the downloaded `template/` directory:

```text
.
├── stack.yaml
└── hello-java
    ├── build.gradle
    └── src/main/java/com/openfaas/function/Handler.java
```

Edit `hello-java/src/main/java/com/openfaas/function/Handler.java` to implement your function. Keep the package and class name; the template provides the HTTP server and application entrypoint.

## Build and run locally

From the directory containing `stack.yaml`:

```bash
faas-cli local-run hello-java --build --port 8085
```

Leave this running and invoke the function from another terminal:

```bash
curl -i http://127.0.0.1:8085
# HTTP 200: Hello, World!

curl -i http://127.0.0.1:8085 --data-binary 'OpenFaaS'
# HTTP 200: Hello, OpenFaaS!
```

Stop the local function with Ctrl+C. Run the command again after editing the handler to rebuild it.

## Deploy to OpenFaaS

Set `OPENFAAS_URL` to your gateway and make sure `provider.gateway` in `stack.yaml` points to the same URL. Log in with `faas-cli login` if you have not already done so. Authenticate Docker to the registry used in `stack.yaml`, and make sure your OpenFaaS installation can pull the image.

```bash
export OPENFAAS_URL=https://your-openfaas-gateway

faas-cli up -f stack.yaml --tag=digest
faas-cli describe hello-java
```

`faas-cli up` builds, pushes and deploys the function. `--tag=digest` tags the image using the function source, so changes to the handler produce a new image tag.

Once the function reports `Ready`, invoke it:

```bash
printf 'OpenFaaS' | faas-cli invoke hello-java
# Hello, OpenFaaS!

curl -i "$OPENFAAS_URL/function/hello-java" --data-binary 'Java 21'
# HTTP 200: Hello, Java 21!
```

View function logs with:

```bash
faas-cli logs hello-java
```

## Example usage

### Read the request body and return text

The generated handler returns a greeting. The `Vertx` instance is passed to the handler constructor, so you can use it for web clients, database connections or other Vert.x APIs. The request body has already been buffered before `handle` is called:

```java
package com.openfaas.function;

import io.vertx.core.Vertx;
import io.vertx.ext.web.RoutingContext;

public class Handler implements io.vertx.core.Handler<RoutingContext> {
    private final Vertx vertx;

    public Handler(Vertx vertx) {
        this.vertx = vertx;
    }

    @Override
    public void handle(RoutingContext context) {
        String body = context.body().asString();
        String name = body == null || body.isBlank() ? "World" : body;
        context.response()
            .putHeader("Content-Type", "text/plain; charset=utf-8")
            .end("Hello, " + name + "!");
    }
}
```

Request bodies are limited to 1 MiB; larger bodies receive HTTP 413. Automatic file uploads are disabled. For binary input, use `context.body().buffer()` instead of converting the body to a string.

### Read request details and return JSON

Replace `Handler.java` with the following to read the method, path, query string, a header and the body. This example also sets a custom response header and HTTP status:

```java
package com.openfaas.function;

import io.vertx.core.json.JsonObject;
import io.vertx.ext.web.RoutingContext;

public class Handler implements io.vertx.core.Handler<RoutingContext> {
    @Override
    public void handle(RoutingContext context) {
        JsonObject result = new JsonObject()
            .put("method", context.request().method().name())
            .put("path", context.request().path())
            .put("name", context.queryParam("name").stream().findFirst().orElse("World"))
            .put("requestId", context.request().getHeader("X-Request-Id"))
            .put("body", context.body().asString());

        context.response()
            .setStatusCode(201)
            .putHeader("Content-Type", "application/json; charset=utf-8")
            .putHeader("X-Served-By", "java21-vertx")
            .end(result.encode());
    }
}
```

Rebuild and deploy, then invoke a path under the function URL:

```bash
faas-cli up -f stack.yaml --tag=digest

curl -i "$OPENFAAS_URL/function/hello-java/greet?name=OpenFaaS" \
    -H 'X-Request-Id: example-123' \
    --data-binary 'Hello'
```

The response has status `201`, the `X-Served-By` header, and this JSON body:

```json
{"method":"POST","path":"/greet","name":"OpenFaaS","requestId":"example-123","body":"Hello"}
```

### Return an error

To reject invalid input, replace the handler's `handle` method with:

```java
@Override
public void handle(RoutingContext context) {
    String body = context.body().asString();
    if (body == null || body.isBlank()) {
        context.response()
            .setStatusCode(400)
            .putHeader("Content-Type", "text/plain; charset=utf-8")
            .end("A request body is required");
        return;
    }

    context.response().end("Accepted: " + body);
}
```

Always end the response, or arrange for an asynchronous callback to end it. An uncaught exception in the synchronous handler is handled by Vert.x and returns HTTP 500.

### Reuse clients between invocations

The handler is created once per application process, with the `Vertx` instance passed to its constructor. You can keep reusable clients or connection pools in handler fields. Each replica has its own instance, and that state is lost when the replica stops.

Handlers run on the Vert.x event loop. Use asynchronous clients for network and database calls; do not block the event loop with `Thread.sleep`, JDBC calls or blocking HTTP clients. Request-specific data belongs in local variables or the `RoutingContext`, rather than shared handler fields.

## Dependencies

Add dependencies to `hello-java/build.gradle`. Maven Central is configured, and the Vert.x platform aligns the versions of Vert.x modules.

For example, add the Vert.x Web Client inside the existing `dependencies` block:

```groovy
implementation 'io.vertx:vertx-web-client'
```

For libraries outside the Vert.x platform, specify an explicit version. Rebuild with `faas-cli build -f stack.yaml`, or use `faas-cli up -f stack.yaml --tag=digest` to build, push and deploy together.

Java resources placed in `hello-java/src/main/resources/` are packaged in the function JAR and can be read from the classpath.

## Tests

JUnit Jupiter is configured in the generated function's `build.gradle`. Add function tests under `hello-java/src/test/java/`. Tests run during every container build, and a failing test fails the build:

```bash
faas-cli build -f stack.yaml
```

To verify the template itself, clone this repository and run:

```bash
git clone https://github.com/welteki/java-http-template
cd java-http-template
./verify.sh
```

The script scaffolds and builds a temporary function, checks HTTP invocation and health endpoints, and tests shutdown. It runs the container with a 256 MiB memory limit, a read-only root filesystem and an overridden non-root UID, then removes the temporary container, image and files.

With a local JDK 21, you can also run the template's Java build and HTTP tests directly:

```bash
cd template/java21-vertx
./gradlew build
```

## Container defaults

The image uses a multi-stage build: a Java 21 JDK compiles and tests the application, while the final image contains a Java 21 JRE and the application libraries. Gradle and the compiler are left out of the runtime image. The Gradle wrapper pins the distribution version and verifies its SHA-256 checksum.

The runtime defaults are:

| Setting | Default |
| --- | --- |
| Runtime user | UID/GID `10001:10001` |
| Watchdog | of-watchdog `0.12.3` in HTTP mode, port `8080` |
| Vert.x server | `127.0.0.1:8082` |
| Maximum JVM heap | 75% of the memory available to the JVM |
| Out-of-memory handling | Exit the JVM |
| Writable runtime files | `/tmp`, including the Vert.x cache |

The image supports a read-only root filesystem when `/tmp` is writable. For example, add the following to the `hello-java` function in `stack.yaml`:

```yaml
    readonly_root_filesystem: true
    requests:
      memory: 128Mi
    limits:
      memory: 256Mi
```

Size the memory limit for your workload, leaving room for thread stacks, direct buffers and other native memory in addition to the Java heap. To change the JVM options, set `JAVA_TOOL_OPTIONS` in the function's `environment` section. This replaces the image default; for example, to reduce the maximum heap to 60% while keeping the other defaults:

```yaml
    environment:
      JAVA_TOOL_OPTIONS: "-XX:MaxRAMPercentage=60.0 -XX:+ExitOnOutOfMemoryError -Dvertx.cacheDirBase=/tmp/.vertx"
```
