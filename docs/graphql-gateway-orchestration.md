# GraphQL Gateway Orchestration Guide

## Overview

The GraphQL Gateway uses **Apollo Federation** to compose multiple domain-specific GraphQL schemas into a unified supergraph. This allows domain teams to independently develop and deploy their GraphQL services while providing clients with a single, cohesive API endpoint.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client Apps   │    │   Mobile Apps   │    │  Web Frontend   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │    GraphQL Gateway       │
                    │   (Apollo Router)        │
                    │   Port: 4000             │
                    └─────────────┬─────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          │                      │                      │
┌─────────▼───────┐    ┌─────────▼───────┐    ┌─────────▼───────┐
│ Products Service│    │ Ratings Service │    │ Future Services │
│ Port: 8081      │    │ Port: 8082      │    │ Port: 808X      │
│ /graphql        │    │ /graphql        │    │ /graphql        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## How It Works

### 1. Federation Principles

The gateway uses **Apollo Federation v2** which allows:

- **Schema Composition**: Multiple subgraph schemas are composed into a single supergraph
- **Entity Resolution**: Shared entities (like `Product`) can be extended across services
- **Query Planning**: The gateway automatically routes parts of queries to appropriate services
- **Response Merging**: Results from multiple services are combined into a single response

### 2. Schema Registration Process

Domain teams register their schemas through two mechanisms:

#### A. Static Configuration (Current Implementation)
```yaml
# config/router.yaml
subgraphs:
  products:
    routing_url: ${env.PRODUCTS_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.PRODUCTS_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
  
  ratings:
    routing_url: ${env.RATINGS_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.RATINGS_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
```

#### B. Dynamic Schema Polling
The gateway automatically:
1. Polls each subgraph's `/_service` endpoint every 30 seconds
2. Retrieves the latest SDL (Schema Definition Language)
3. Recomposes the supergraph when schemas change
4. Updates routing without downtime

## Domain Team Integration Guide

### Step 1: Implement Federation in Your Service

Your GraphQL service must support Apollo Federation:

```graphql
# Example Products Service Schema
extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

type Product @key(fields: "id") {
  id: ID!
  name: String!
  description: String
  price: Float
  category: String
}

type Query {
  product(id: ID!): Product
  products(limit: Int = 10): [Product!]!
}
```

### Step 2: Add Required Federation Endpoints

Your service must expose:

```javascript
// /_service endpoint - returns your schema SDL
app.get('/_service', (req, res) => {
  res.json({
    sdl: `
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"])
      
      type Product @key(fields: "id") {
        id: ID!
        name: String!
        description: String
      }
      
      type Query {
        product(id: ID!): Product
        products: [Product!]!
      }
    `
  });
});

// /health endpoint - for health checks
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'products' });
});
```

### Step 3: Register Your Service

#### Option A: Environment Configuration
Add your service to the environment configuration:

```bash
# .env
PRODUCTS_SERVICE_URL=http://products-service:8081
RATINGS_SERVICE_URL=http://ratings-service:8082
YOUR_SERVICE_URL=http://your-service:8083
```

#### Option B: Update Router Configuration
Add your subgraph to `config/router.yaml`:

```yaml
subgraphs:
  your-service:
    routing_url: ${env.YOUR_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.YOUR_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
    health_check:
      enabled: true
      path: /health
      interval: 30s
      timeout: 5s
```

### Step 4: Entity Extension (Optional)

If your service extends existing entities:

```graphql
# Ratings Service extending Product entity
extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@external"])

type Product @key(fields: "id") {
  id: ID! @external
  averageRating: Float
  reviewCount: Int
  ratingDistribution: RatingDistribution
}

type RatingDistribution {
  oneStar: Int!
  twoStar: Int!
  threeStar: Int!
  fourStar: Int!
  fiveStar: Int!
  total: Int!
}
```

## Schema Composition Examples

### Basic Entity Definition
```graphql
# Products Service
type Product @key(fields: "id") {
  id: ID!
  name: String!
  description: String
  price: Float
}
```

### Entity Extension
```graphql
# Ratings Service
type Product @key(fields: "id") {
  id: ID! @external
  averageRating: Float
  reviewCount: Int
}
```

### Composed Result
Clients can query both services seamlessly:
```graphql
query {
  product(id: "1") {
    # From Products Service
    id
    name
    description
    price
    
    # From Ratings Service
    averageRating
    reviewCount
  }
}
```

## Deployment Workflows

### 1. Development Workflow

```bash
# 1. Start your service locally
npm run dev  # Your service on port 8083

# 2. Update environment variables
echo "YOUR_SERVICE_URL=http://localhost:8083" >> .env

# 3. Update router configuration
# Add your service to config/router.yaml

# 4. Restart the gateway
docker compose restart graphql-gateway

# 5. Test schema composition
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { types { name } } }"}'
```

### 2. Production Deployment

```bash
# 1. Deploy your service
kubectl apply -f your-service-deployment.yaml

# 2. Update gateway configuration
kubectl patch configmap gateway-config --patch '
data:
  router.yaml: |
    subgraphs:
      your-service:
        routing_url: http://your-service:8080/graphql
        schema:
          subgraph_url: http://your-service:8080/graphql
'

# 3. Gateway automatically detects and composes new schema
# No restart required!
```

## Advanced Features

### 1. Schema Validation

The gateway validates schemas during composition:

```bash
# Test schema composition locally
docker run --rm -v $(pwd)/config:/config \
  apollographql/rover:latest \
  supergraph compose --config /config/supergraph.yaml
```

### 2. Query Planning

The gateway creates optimal query plans:

```graphql
# Client Query
query {
  product(id: "1") {
    name        # → Products Service
    price       # → Products Service
    avgRating   # → Ratings Service
  }
}

# Gateway creates 2 parallel requests:
# 1. Products Service: { product(id: "1") { name price } }
# 2. Ratings Service: { product(id: "1") { avgRating } }
```

### 3. Error Handling

The gateway handles partial failures gracefully:

```json
{
  "data": {
    "product": {
      "name": "Product 1",
      "price": 29.99,
      "avgRating": null
    }
  },
  "errors": [
    {
      "message": "Ratings service unavailable",
      "path": ["product", "avgRating"],
      "extensions": {
        "code": "SUBGRAPH_REQUEST_ERROR"
      }
    }
  ]
}
```

## Monitoring and Observability

### 1. Health Checks

```bash
# Gateway health
curl http://localhost:4000/health

# Individual service health
curl http://localhost:8081/health  # Products
curl http://localhost:8082/health  # Ratings
```

### 2. Schema Introspection

```graphql
# Check composed schema
query {
  __schema {
    types {
      name
      fields {
        name
        type {
          name
        }
      }
    }
  }
}
```

### 3. Metrics and Logging

The gateway provides detailed metrics:
- Request latency per subgraph
- Error rates and types
- Schema composition events
- Query planning performance

## Best Practices for Domain Teams

### 1. Schema Design
- Use meaningful entity keys (`@key(fields: "id")`)
- Keep schemas focused on your domain
- Avoid cross-domain dependencies
- Use consistent naming conventions

### 2. Versioning
- Use semantic versioning for schema changes
- Test schema composition before deployment
- Coordinate breaking changes across teams

### 3. Performance
- Implement efficient resolvers
- Use DataLoader for N+1 query prevention
- Monitor subgraph response times
- Implement proper caching strategies

### 4. Error Handling
- Return meaningful error messages
- Implement proper health checks
- Handle partial failures gracefully
- Use appropriate HTTP status codes

## Troubleshooting

### Common Issues

1. **Schema Composition Failures**
   ```bash
   # Check gateway logs
   docker logs graphql-gateway
   
   # Validate individual schemas
   curl http://your-service:8080/_service
   ```

2. **Service Discovery Issues**
   ```bash
   # Check network connectivity
   docker exec graphql-gateway wget -O- http://your-service:8080/health
   ```

3. **Query Planning Problems**
   ```bash
   # Enable query planning logs
   APOLLO_ROUTER_LOG=debug docker compose up graphql-gateway
   ```

This orchestration approach allows domain teams to work independently while maintaining a unified API experience for clients.