package com.openfaas.function;

import io.vertx.ext.web.RoutingContext;

public class Handler implements io.vertx.core.Handler<RoutingContext> {
    @Override
    public void handle(RoutingContext context) {
        String body = context.body().asString();
        String name = body == null || body.isBlank() ? "World" : body;
        context.response()
            .putHeader("Content-Type", "text/plain; charset=utf-8")
            .end("Hello, " + name + "!");
    }
}
