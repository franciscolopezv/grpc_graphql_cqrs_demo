# Example: Adding a New Service to the GraphQL Gateway

This example shows how the **Inventory Team** would register their new Inventory Service with the GraphQL Gateway.

## Scenario

The Inventory Team wants to add inventory tracking capabilities that extend the existing `Product` entity with stock information.

## Step 1: Implement Federation-Compatible Service

### Inventory Service Schema (inventory-service/schema.graphql)

```graphql
extend schema 
  @link(url: "https://specs.apollo.dev/federation/v2.0", 
        import: ["@key", "@external", "@requires", "@provides"])

# Extend the existing Product entity
type Product @key(fields: "id") {
  id: ID! @external
  
  # Add inventory-specific fields
  stockLevel: Int!
  reservedQuantity: Int!
  availableQuantity: Int! @requires(fields: "stockLevel reservedQuantity")
  isInStock: Boolean!
  reorderPoint: Int!
  supplier: Supplier
  lastRestocked: String
  
  # Computed field that requires product name from Products service
  stockStatus: StockStatus! @requires(fields: "name")
}

# New types specific to inventory domain
type Supplier {
  id: ID!
  name: String!
  contactEmail: String!
  leadTimeDays: Int!
}

enum StockStatus {
  IN_STOCK
  LOW_STOCK
  OUT_OF_STOCK
  DISCONTINUED
}

type InventoryAlert {
  id: ID!
  productId: ID!
  alertType: AlertType!
  message: String!
  createdAt: String!
  resolved: Boolean!
}

enum AlertType {
  LOW_STOCK
  OUT_OF_STOCK
  OVERSTOCK
  REORDER_NEEDED
}

# Inventory-specific queries
type Query {
  # Get inventory for a specific product
  productInventory(productId: ID!): Product
  
  # Get all low stock products
  lowStockProducts(threshold: Int = 10): [Product!]!
  
  # Get inventory alerts
  inventoryAlerts(resolved: Boolean = false): [InventoryAlert!]!
  
  # Get products by supplier
  productsBySupplier(supplierId: ID!): [Product!]!
  
  # Get all suppliers
  suppliers: [Supplier!]!
}

# Inventory-specific mutations
type Mutation {
  # Update stock levels
  updateStock(productId: ID!, quantity: Int!, reason: String): Product
  
  # Reserve inventory for orders
  reserveInventory(productId: ID!, quantity: Int!): Boolean!
  
  # Release reserved inventory
  releaseReservation(productId: ID!, quantity: Int!): Boolean!
  
  # Add new supplier
  addSupplier(input: SupplierInput!): Supplier!
  
  # Update reorder point
  updateReorderPoint(productId: ID!, reorderPoint: Int!): Product
}

input SupplierInput {
  name: String!
  contactEmail: String!
  leadTimeDays: Int!
}
```

### Service Implementation (inventory-service/server.js)

```javascript
const express = require('express');
const { ApolloServer } = require('@apollo/server');
const { expressMiddleware } = require('@apollo/server/express4');
const { buildSubgraphSchema } = require('@apollo/subgraph');
const { readFileSync } = require('fs');

const app = express();

// Load schema
const typeDefs = readFileSync('./schema.graphql', 'utf8');

// Sample data (in production, this would be a database)
const inventoryData = {
  '1': {
    stockLevel: 150,
    reservedQuantity: 25,
    isInStock: true,
    reorderPoint: 50,
    supplier: { id: 'SUP1', name: 'TechCorp', contactEmail: 'orders@techcorp.com', leadTimeDays: 7 },
    lastRestocked: '2024-01-15T10:00:00Z'
  },
  '2': {
    stockLevel: 5,
    reservedQuantity: 2,
    isInStock: true,
    reorderPoint: 20,
    supplier: { id: 'SUP2', name: 'GadgetCo', contactEmail: 'supply@gadgetco.com', leadTimeDays: 14 },
    lastRestocked: '2024-01-10T14:30:00Z'
  }
};

const resolvers = {
  Product: {
    // Resolver for the Product entity
    __resolveReference(product) {
      return {
        id: product.id,
        ...inventoryData[product.id]
      };
    },
    
    // Computed fields
    availableQuantity(product) {
      return product.stockLevel - product.reservedQuantity;
    },
    
    stockStatus(product) {
      const available = product.stockLevel - product.reservedQuantity;
      if (available <= 0) return 'OUT_OF_STOCK';
      if (available <= product.reorderPoint) return 'LOW_STOCK';
      return 'IN_STOCK';
    }
  },
  
  Query: {
    productInventory(_, { productId }) {
      return { id: productId, ...inventoryData[productId] };
    },
    
    lowStockProducts(_, { threshold }) {
      return Object.entries(inventoryData)
        .filter(([id, data]) => (data.stockLevel - data.reservedQuantity) <= threshold)
        .map(([id, data]) => ({ id, ...data }));
    },
    
    inventoryAlerts() {
      // Mock alerts - in production, fetch from database
      return [
        {
          id: 'ALERT1',
          productId: '2',
          alertType: 'LOW_STOCK',
          message: 'Product 2 is running low on stock',
          createdAt: '2024-01-16T09:00:00Z',
          resolved: false
        }
      ];
    },
    
    suppliers() {
      return [
        { id: 'SUP1', name: 'TechCorp', contactEmail: 'orders@techcorp.com', leadTimeDays: 7 },
        { id: 'SUP2', name: 'GadgetCo', contactEmail: 'supply@gadgetco.com', leadTimeDays: 14 }
      ];
    }
  },
  
  Mutation: {
    updateStock(_, { productId, quantity, reason }) {
      if (inventoryData[productId]) {
        inventoryData[productId].stockLevel = quantity;
        inventoryData[productId].lastRestocked = new Date().toISOString();
        return { id: productId, ...inventoryData[productId] };
      }
      throw new Error(`Product ${productId} not found`);
    },
    
    reserveInventory(_, { productId, quantity }) {
      const product = inventoryData[productId];
      if (!product) throw new Error(`Product ${productId} not found`);
      
      const available = product.stockLevel - product.reservedQuantity;
      if (available < quantity) {
        throw new Error(`Insufficient stock. Available: ${available}, Requested: ${quantity}`);
      }
      
      product.reservedQuantity += quantity;
      return true;
    }
  }
};

// Create Apollo Server with subgraph schema
const server = new ApolloServer({
  schema: buildSubgraphSchema({ typeDefs, resolvers })
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'inventory',
    timestamp: new Date().toISOString()
  });
});

// Federation service endpoint
app.get('/_service', (req, res) => {
  res.json({
    sdl: typeDefs
  });
});

async function startServer() {
  await server.start();
  
  app.use('/graphql', express.json(), expressMiddleware(server));
  
  const PORT = process.env.PORT || 8083;
  app.listen(PORT, () => {
    console.log(`🚀 Inventory Service ready at http://localhost:${PORT}/graphql`);
    console.log(`📊 Health check at http://localhost:${PORT}/health`);
  });
}

startServer().catch(error => {
  console.error('Failed to start server:', error);
});
```

## Step 2: Update Gateway Configuration

### Add Environment Variable (.env)

```bash
# Add to .env file
INVENTORY_SERVICE_URL=http://inventory-service:8083
```

### Update Router Configuration (config/router.yaml)

```yaml
# Add to subgraphs section in config/router.yaml
subgraphs:
  products:
    routing_url: ${env.PRODUCTS_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.PRODUCTS_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
    health_check:
      enabled: true
      path: /health
      interval: 30s
      timeout: 5s
  
  ratings:
    routing_url: ${env.RATINGS_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.RATINGS_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
    health_check:
      enabled: true
      path: /health
      interval: 30s
      timeout: 5s
  
  # NEW: Inventory service
  inventory:
    routing_url: ${env.INVENTORY_SERVICE_URL}/graphql
    schema:
      subgraph_url: ${env.INVENTORY_SERVICE_URL}/graphql
      poll_interval: 30s
      timeout: 10s
    health_check:
      enabled: true
      path: /health
      interval: 30s
      timeout: 5s
```

### Update Docker Compose (docker-compose.yml)

```yaml
services:
  # ... existing services ...
  
  # NEW: Inventory Service
  inventory-service:
    build:
      context: ./inventory-service
      dockerfile: Dockerfile
    hostname: inventory-service
    container_name: inventory-service
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8083:8083"
    environment:
      PORT: 8083
      DATABASE_URL: postgresql://platform_user:platform_password@postgres:5432/inventory_db
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8083/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

  # Update GraphQL Gateway to include inventory service
  graphql-gateway:
    # ... existing configuration ...
    environment:
      # ... existing environment variables ...
      INVENTORY_SERVICE_URL: ${INVENTORY_SERVICE_URL:-http://inventory-service:8083}
    depends_on:
      kafka:
        condition: service_healthy
      postgres:
        condition: service_healthy
      inventory-service:  # NEW dependency
        condition: service_healthy
```

## Step 3: Deploy and Test

### Local Development

```bash
# 1. Start the inventory service
cd inventory-service
npm install
npm start

# 2. Update environment
echo "INVENTORY_SERVICE_URL=http://localhost:8083" >> .env

# 3. Restart gateway to pick up new configuration
docker compose restart graphql-gateway

# 4. Wait for schema composition (check logs)
docker logs -f graphql-gateway

# 5. Test the composed schema
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ __schema { types { name } } }"
  }'
```

### Test Federated Queries

```bash
# Test cross-service query
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query { product(id: \"1\") { id name description price stockLevel availableQuantity isInStock stockStatus } }"
  }'
```

Expected response:
```json
{
  "data": {
    "product": {
      "id": "1",
      "name": "Product 1",           // From Products Service
      "description": "Description 1", // From Products Service  
      "price": 29.99,                // From Products Service
      "stockLevel": 150,             // From Inventory Service
      "availableQuantity": 125,      // From Inventory Service (computed)
      "isInStock": true,             // From Inventory Service
      "stockStatus": "IN_STOCK"      // From Inventory Service (computed)
    }
  }
}
```

## Step 4: Production Deployment

### Kubernetes Deployment

```yaml
# inventory-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: inventory-service
  template:
    metadata:
      labels:
        app: inventory-service
    spec:
      containers:
      - name: inventory-service
        image: your-registry/inventory-service:v1.0.0
        ports:
        - containerPort: 8083
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: inventory-db-url
        livenessProbe:
          httpGet:
            path: /health
            port: 8083
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8083
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
spec:
  selector:
    app: inventory-service
  ports:
  - port: 8083
    targetPort: 8083
```

### Update Gateway ConfigMap

```yaml
# Update gateway-config ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-config
data:
  router.yaml: |
    subgraphs:
      inventory:
        routing_url: http://inventory-service:8083/graphql
        schema:
          subgraph_url: http://inventory-service:8083/graphql
          poll_interval: 30s
```

## Step 5: Monitoring and Validation

### Schema Composition Validation

```bash
# Check if schema composed successfully
kubectl logs deployment/graphql-gateway | grep "inventory"

# Test schema introspection
kubectl port-forward service/graphql-gateway 4000:4000
curl -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __type(name: \"Product\") { fields { name type { name } } } }"}'
```

### Health Monitoring

```bash
# Check service health
curl http://inventory-service:8083/health

# Check gateway health (includes subgraph connectivity)
curl http://graphql-gateway:4000/health
```

## Benefits of This Approach

1. **Independent Development**: Inventory team can develop and deploy independently
2. **Automatic Composition**: Gateway automatically detects and composes the new schema
3. **Zero Downtime**: Schema updates happen without restarting the gateway
4. **Type Safety**: Full GraphQL type safety across service boundaries
5. **Unified API**: Clients get a single endpoint with all capabilities
6. **Performance**: Gateway optimizes queries across services

## Best Practices Demonstrated

1. **Entity Extension**: Properly extending existing `Product` entity
2. **Federation Directives**: Using `@key`, `@external`, `@requires` correctly
3. **Health Checks**: Implementing proper health endpoints
4. **Error Handling**: Graceful error handling in resolvers
5. **Schema Versioning**: Using semantic versioning for deployments
6. **Monitoring**: Comprehensive health and performance monitoring

This example shows how easy it is for domain teams to integrate with the GraphQL Gateway while maintaining independence and following federation best practices.