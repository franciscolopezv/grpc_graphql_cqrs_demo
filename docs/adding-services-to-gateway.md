# Adding Services to the GraphQL Gateway

This guide explains how to add new subgraph services to the Apollo Router gateway.

## Prerequisites

1. Your service must support Apollo Federation (expose `_service { sdl }` query)
2. Your service must be on the `platform-infrastructure` Docker network
3. Apollo Rover CLI must be installed (see installation below)

## Installing Apollo Rover

```bash
curl -sSL https://rover.apollo.dev/nix/latest | sh
export PATH="$HOME/.rover/bin:$PATH"
```

## Steps to Add a Service

### 1. Verify Federation Support

Test that your service exposes the Federation schema:

```bash
curl -X POST http://localhost:YOUR_PORT/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ _service { sdl } }"}'
```

You should see a response with the service's SDL schema.

### 2. Check Internal Port

Verify the internal port your service listens on:

```bash
docker ps --filter "name=your-service-name" --format "{{.Ports}}"
```

**Important**: Use the internal port (left side of the mapping), not the external port.
- Example: `0.0.0.0:8083->8082/tcp` means internal port is **8082**

### 3. Update Supergraph Configuration

Edit `config/supergraph-config.yaml` and add your service:

```yaml
federation_version: =2.3.0
subgraphs:
  products:
    routing_url: http://products-query-service:4000/graphql
    schema:
      subgraph_url: http://localhost:4001/graphql
  ratings:
    routing_url: http://ratings-query-service:8082/graphql
    schema:
      subgraph_url: http://localhost:8083/graphql
  your-service:  # Add your service here
    routing_url: http://your-service-name:INTERNAL_PORT/graphql
    schema:
      subgraph_url: http://localhost:EXTERNAL_PORT/graphql
```

**Key points**:
- `routing_url`: Used by the gateway to reach the service (use internal port and container name)
- `subgraph_url`: Used by Rover to fetch the schema during composition (use external port and localhost)

### 4. Compose the Supergraph Schema

Run Rover to compose the new supergraph schema:

```bash
export PATH="$HOME/.rover/bin:$PATH"
rover supergraph compose --config config/supergraph-config.yaml > config/supergraph.graphql
```

If successful, you'll see the composed schema output.

### 5. Restart the Gateway

```bash
docker restart graphql-gateway
```

Wait a few seconds for the gateway to start, then verify:

```bash
docker logs graphql-gateway --tail 10
```

You should see: `GraphQL endpoint exposed at http://0.0.0.0:4000/ 🚀`

### 6. Test the Gateway

Query your new service through the gateway:

```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{"query":"{ yourQuery { field } }"}'
```

## Troubleshooting

### "Connection refused" Error

- **Cause**: Wrong internal port in `routing_url`
- **Fix**: Check the internal port with `docker ps` and update the routing_url

### "Failed to introspect the subgraph"

- **Cause**: Service doesn't support Federation
- **Fix**: Ensure your service exposes the `_service { sdl }` query field

### "Invalid supergraph: must be a core schema"

- **Cause**: Manually edited supergraph schema
- **Fix**: Always use Rover to compose the schema, don't edit it manually

### Gateway keeps restarting

- **Cause**: CORS configuration issue or invalid schema
- **Fix**: Check `docker logs graphql-gateway` for specific errors

## Current Services

- **products**: `http://products-query-service:4000/graphql`
- **ratings**: `http://ratings-query-service:8082/graphql`

## Network Configuration

All services must be on the `platform-infrastructure` network:

```yaml
networks:
  - platform-infrastructure
```

The network is created externally and shared across all services.
