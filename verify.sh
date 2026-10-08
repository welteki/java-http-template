#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
function_name="java21-vertx-test-$(date +%s)-$$"
image="${function_name}:latest"
container=""

cleanup() {
    result=$?
    if [ -n "$container" ]; then
        if [ "$result" -ne 0 ]; then docker logs "$container"; fi
        docker rm -f "$container" >/dev/null
    fi
    docker image rm "$image" >/dev/null 2>&1 || true
    rm -rf "$work"
    exit "$result"
}
trap cleanup EXIT

cp -a "$repo/template" "$work/"
cd "$work"
OPENFAAS_PREFIX="" faas-cli new "$function_name" --lang java21-vertx
faas-cli build -f stack.yaml

# OpenFaaS can override the image UID and mount its root filesystem read-only.
container=$(docker run -d --read-only --user 12000:12000 --memory 256m --cpus 1 \
    --tmpfs /tmp:rw,nosuid,noexec,size=64m -p 127.0.0.1::8080 "$image")
address="http://$(docker port "$container" 8080/tcp)"

for attempt in $(seq 1 60); do
    test "$(docker inspect --format '{{.State.Running}}' "$container")" = "true"
    if curl --max-time 2 -fsS "$address" > response.txt 2>/dev/null; then break; fi
    sleep 1
done
test "$(cat response.txt)" = "Hello, World!"
test "$(curl -fsS "$address/nested/path?q=test" --data-binary 'OpenFaaS')" = "Hello, OpenFaaS!"
curl -fsS "$address/_/health" >/dev/null
curl -fsS "$address/_/ready" >/dev/null
test "$(docker inspect --format '{{.Config.User}}' "$image")" = "10001:10001"

docker stop --time 15 "$container" >/dev/null
# The watchdog reports Java's normal SIGTERM exit (143) as container exit 1.
case "$(docker inspect --format '{{.State.ExitCode}}' "$container")" in
    0) ;;
    1) docker logs "$container" 2>&1 | grep -q 'Forked function has terminated: exit status 143' ;;
    *) exit 1 ;;
esac
echo "Java 21 template: build, HTTP, health, non-root/read-only runtime and shutdown passed."
