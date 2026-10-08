# Java HTTP template

Minimal OpenFaaS template using Java 21 LTS, Vert.x 5.2.1, Gradle 9.8.1 and of-watchdog 0.12.3.

From this checkout:

```sh
faas-cli new hello-java --lang java21-vertx --prefix YOUR_REGISTRY
faas-cli up -f stack.yaml --tag=digest
echo -n OpenFaaS | faas-cli invoke hello-java
# Hello, OpenFaaS!
```

Edit the generated `src/main/java/com/openfaas/function/Handler.java`; add dependencies and tests in the generated function's Gradle project. The handler receives a Vert.x `RoutingContext` with the body already buffered (1 MiB limit). Use asynchronous APIs: handlers run on the Vert.x event loop.

The container builds and tests with a JDK, then ships only application libraries and a Java 21 JRE. It runs as UID 10001, with the watchdog on port 8080 and Vert.x on loopback port 8082. A read-only root filesystem is supported when `/tmp` is writable. `JAVA_TOOL_OPTIONS` can override the default 75% maximum heap allocation and JVM options; leave room for native memory when setting container limits.

Run `./verify.sh` with Docker and faas-cli to scaffold, build, invoke and stop a temporary function container. With a local JDK 21, `cd template/java21-vertx && ./gradlew build` runs the Java build and HTTP tests.
