# GraphQL Gateway Orchestration System

## Overview

The GraphQL Gateway provides a unified API endpoint that composes multiple domain-specific GraphQL services into a single, cohesive supergraph using **Apollo Federation v2**. This enables domain teams to develop and deploy independently while maintaining a consistent client experience.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ Web App     │  │ Mobile App  │  │ Admin Panel │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │ Single GraphQL Endpoint
                      │ http://gateway:4000/graphql
┌─────────────────────▼───────────────────────────────────────────┐
│                GraphQL Gateway (Apollo Router)                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Schema Composition    • Query Planning               │   │
│  │ • Request Routing       • Response Merging             │   │
│  │ • Health Monitoring     • Error Handling               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │ Federation Protocol
        ┌─────────────┼─────────────┬─────────────┐
        │             │             │             │
┌───────▼──────┐ ┌────▼────┐ ┌──────▼──────┐ ┌───▼────────┐
│   Products   │ │ Ratings │ │  Inventory  │ │   Future   │
│   Service    │ │ Service │ │   Service   │ │  Services  │
│   :8081      │ │  :8082  │ │    :8083    │ │   :808X    │
└──────────────┘ └─────────┘ └─────────────┘ └────────────┘
```

## 🚀 How It Works

### 1. **Schema Federation**
- Each domain service exposes a GraphQL schema with Federation directives
- The gateway automatically composes these schemas into a unified supergraph
- Shared entities (like `Product`) can be extended across multiple services

### 2. **Automatic Discovery**
- Gateway polls each service's `/_service` endpoint every 30 seconds
- Schema changes are automatically detected and composed
- No gateway restart required for schema updates

### 3. **Intelligent Query Planning**
- Gateway analyzes incoming queries and creates optimal execution plans
- Queries are automatically routed to appropriate services
- Responses from multiple services are merged seamlessly

### 4. **Entity Resolution**
- Shared entities are resolved across service boundaries
- Example: `Product` entity with data from Products, Ratings, and Inventory services

## 📋 Domain Team Integration

### Quick Start for New Services

1. **Use the Registration Script**:
   ```bash
   ./scripts/register-service.sh inventory http://inventory-service:8083 8083
   ```

2. **Manual Registration**:
   - Implement Federation in your GraphQL service
   - Add service URL to environment configuration
   - Update router configuration
   - Deploy and test

### Federation Requirements

Your service must implement:

#### Required Endpoints
```javascript
// Health check
GET /health
Response: { "status": "healthy", "service": "your-service" }

// Federation schema
GET /_service  
Response: { "sdl": "your-graphql-schema-with-federation-directives" }

// GraphQL endpoint
POST /graphql
Standard GraphQL endpoint with Federation support
```

#### Schema Example
```graphql
extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@external"])

# Define or extend entities
type Product @key(fields: "id") {
  id: ID!
  # Your domain-specific fields
  stockLevel: Int!
  isInStock: Boolean!
}

type Query {
  # Your domain-specific queries
  lowStockProducts: [Product!]!
}
```

## 🔧 Configuration

### Environment Variables
```bash
# Core services
PRODUCTS_SERVICE_URL=http://products-service:8081
RATINGS_SERVICE_URL=http://ratings-service:8082

# Add your service
YOUR_SERVICE_URL=http://your-service:8083
```

### Router Configuration (`config/router.yaml`)
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

## 🧪 Testing

### Integration Tests
```bash
# Run all tests
npm test

# Test specific components
npm test -- --testPathPattern=graphql-gateway-simple
npm test -- --testPathPattern=docker-compose-simple
```

### Manual Testing
```bash
# Test service health
curl http://your-service:8083/health

# Test Federation support
curl http://your-service:8083/_service

# Test gateway composition
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { types { name } } }"}'

# Test cross-service query
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ 
      product(id: \"1\") { 
        name          # Products Service
        price         # Products Service  
        averageRating # Ratings Service
        stockLevel    # Inventory Service
      } 
    }"
  }'
```

## 📊 Monitoring

### Health Checks
- **Gateway Health**: `GET /health` - Overall system health
- **Service Health**: Individual service health endpoints
- **Schema Composition**: Automatic validation during polling

### Observability
- Request/response logging per subgraph
- Query planning and execution metrics  
- Schema composition events
- Error tracking and alerting

### Logs
```bash
# Gateway logs
docker logs graphql-gateway

# Service-specific logs
docker logs products-service
docker logs ratings-service
```

## 🔄 Deployment Workflows

### ⚠️ Current Implementation (Requires Restart)
```bash
# 1. Start your service
npm run dev

# 2. Register with gateway (requires restart)
./scripts/register-service.sh my-service http://localhost:8083

# 3. Gateway restart needed
docker compose restart graphql-gateway
```

### ✅ Recommended: Apollo Studio (Zero Downtime)
```bash
# 1. Deploy service
kubectl apply -f my-service-deployment.yaml

# 2. Publish schema to Apollo Studio
./scripts/register-service-apollo.sh my-service http://my-service:8080 ./schema.graphql

# 3. Gateway auto-updates in ~10 seconds
# NO RESTART REQUIRED! 🎉
```

### Migration to Zero-Downtime Approach
```bash
# One-time setup
export APOLLO_KEY="your-apollo-key"
export APOLLO_GRAPH_REF="your-graph@production"

# Update gateway to use Apollo Studio
cat > config/router.yaml << EOF
supergraph:
  apollo_key: \${env.APOLLO_KEY}
  apollo_graph_ref: \${env.APOLLO_GRAPH_REF}
  poll_interval: 10s
EOF

# Restart gateway one last time
docker compose restart graphql-gateway

# Future services register without restarts!
```

## 📚 Documentation

- **[Complete Orchestration Guide](docs/graphql-gateway-orchestration.md)** - Detailed technical documentation
- **[Service Registration Example](docs/examples/new-service-registration.md)** - Step-by-step integration example
- **[Test Documentation](tests/README.md)** - Testing guide and utilities

## 🛠️ Utilities

### Scripts
- `scripts/register-service.sh` - Automated service registration
- `scripts/start-infrastructure.sh` - Start all services
- `scripts/stop-infrastructure.sh` - Stop all services
- `scripts/validate-config.sh` - Validate configurations

### Generated Test Scripts
After registration, you get a custom test script:
```bash
./test_your-service_integration.sh
```

## 🎯 Benefits

### Current Implementation
- ⚠️ **Requires Gateway Restart**: New services need gateway restart
- ✅ **Simple Setup**: Easy to understand and configure
- ✅ **No External Dependencies**: Self-contained solution

### With Apollo Studio (Recommended)
- ✅ **Zero Downtime**: No gateway restarts ever needed
- ✅ **Automatic Discovery**: Services auto-register in ~10 seconds
- ✅ **Schema Validation**: Prevents breaking changes before deployment
- ✅ **Team Collaboration**: Built-in approval workflows
- ✅ **Performance Monitoring**: Real-time metrics and analytics
- ✅ **Easy Rollbacks**: One-click schema rollbacks

### For Domain Teams
- **Independence**: Develop and deploy without coordination
- **Ownership**: Full control over your domain's schema and data
- **Flexibility**: Use any GraphQL implementation
- **Testing**: Isolated testing with mock gateway

### For Client Teams  
- **Single Endpoint**: One GraphQL API for all domains
- **Type Safety**: Full GraphQL type system across services
- **Performance**: Optimized query execution and caching
- **Consistency**: Unified error handling and response format

### For Platform Teams
- **Scalability**: Add services without gateway changes (with Apollo Studio)
- **Reliability**: Graceful handling of service failures
- **Monitoring**: Centralized observability and metrics
- **Security**: Single point for authentication and authorization

## 🚨 Troubleshooting

### Common Issues

1. **Schema Composition Failures**
   ```bash
   # Check gateway logs
   docker logs graphql-gateway
   
   # Validate service schema
   curl http://your-service:8083/_service
   ```

2. **Service Discovery Issues**
   ```bash
   # Test connectivity
   docker exec graphql-gateway wget -O- http://your-service:8083/health
   ```

3. **Query Planning Problems**
   ```bash
   # Enable debug logging
   APOLLO_ROUTER_LOG=debug docker compose up graphql-gateway
   ```

### Getting Help

1. Check the [troubleshooting guide](docs/graphql-gateway-orchestration.md#troubleshooting)
2. Review service logs and gateway logs
3. Test individual service endpoints
4. Validate Federation schema compliance

## 🔮 Future Enhancements

- **Apollo Studio Integration**: Schema registry and performance monitoring
- **Advanced Caching**: Distributed caching across subgraphs  
- **Security Policies**: Fine-grained authorization rules
- **Schema Governance**: Automated schema validation and breaking change detection
- **Performance Optimization**: Query complexity analysis and rate limiting

---

This GraphQL Gateway orchestration system enables true microservices architecture for GraphQL APIs while maintaining the developer experience of a monolithic graph. Domain teams can focus on their business logic while the platform handles the complexity of service composition and routing.