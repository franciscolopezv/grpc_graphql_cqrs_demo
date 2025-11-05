# Dynamic Service Registration - No Gateway Restarts Required

## Problem with Current Approach

The current static configuration requires:
- Manual updates to `config/router.yaml` 
- Gateway restart for each new service
- Coordination between teams for deployments

## Solution 1: Apollo Studio Schema Registry (Recommended)

### How It Works
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Service A     │    │   Service B     │    │   Service C     │
│                 │    │                 │    │                 │
│ 1. Deploy       │    │ 1. Deploy       │    │ 1. Deploy       │
│ 2. Publish      │    │ 2. Publish      │    │ 2. Publish      │
│    Schema ──────┼────┼────Schema ──────┼────┼────Schema ──────┼───┐
└─────────────────┘    └─────────────────┘    └─────────────────┘   │
                                                                    │
                       ┌─────────────────────────────────────────────▼─┐
                       │           Apollo Studio Registry             │
                       │  • Schema Storage    • Composition           │
                       │  • Validation        • Change Detection      │
                       │  • Rollback          • Breaking Changes      │
                       └─────────────────────┬─────────────────────────┘
                                             │ 3. Auto-fetch composed schema
                       ┌─────────────────────▼─────────────────────────┐
                       │            GraphQL Gateway                    │
                       │  • No restart needed  • Hot reload           │
                       │  • Zero downtime       • Automatic discovery │
                       └───────────────────────────────────────────────┘
```

### Implementation

#### 1. Update Gateway Configuration
```yaml
# config/router.yaml - Apollo Studio mode
supergraph:
  # Use Apollo Studio instead of static file
  apollo_key: ${env.APOLLO_KEY}
  apollo_graph_ref: ${env.APOLLO_GRAPH_REF}
  # Poll interval for schema updates
  poll_interval: 10s

# Remove static subgraphs section - managed by Studio
```

#### 2. Service Registration Script
```bash
#!/bin/bash
# scripts/register-service-apollo.sh

SERVICE_NAME=$1
SERVICE_URL=$2

# 1. Deploy your service
echo "Service deployed at: $SERVICE_URL"

# 2. Publish schema to Apollo Studio
npx @apollo/rover subgraph publish ${APOLLO_GRAPH_REF} \
  --name ${SERVICE_NAME} \
  --schema ${SERVICE_NAME}/schema.graphql \
  --routing-url ${SERVICE_URL}/graphql

# 3. Gateway automatically picks up changes (no restart!)
echo "✅ Service registered! Gateway will auto-update in ~10 seconds"
```

#### 3. Service Deployment Workflow
```yaml
# .github/workflows/deploy-service.yml
name: Deploy Service
on:
  push:
    paths: ['services/inventory/**']

jobs:
  deploy:
    steps:
      - name: Deploy Service
        run: kubectl apply -f services/inventory/k8s/

      - name: Publish Schema
        run: |
          npx @apollo/rover subgraph publish ${{ secrets.APOLLO_GRAPH_REF }} \
            --name inventory \
            --schema services/inventory/schema.graphql \
            --routing-url https://inventory-service.company.com/graphql
        env:
          APOLLO_KEY: ${{ secrets.APOLLO_KEY }}
      
      # No gateway restart needed!
```

### Benefits
- ✅ **Zero Downtime**: No gateway restarts
- ✅ **Automatic Discovery**: Services auto-register
- ✅ **Schema Validation**: Prevents breaking changes
- ✅ **Rollback Support**: Easy schema rollbacks
- ✅ **Team Independence**: No coordination needed

## Solution 2: Service Discovery with Consul/Kubernetes

### How It Works
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Service A     │    │   Service B     │    │   Service C     │
│                 │    │                 │    │                 │
│ Registers with  │    │ Registers with  │    │ Registers with  │
│ Service ────────┼────┼─Service ────────┼────┼─Service ────────┼───┐
│ Discovery       │    │ Discovery       │    │ Discovery       │   │
└─────────────────┘    └─────────────────┘    └─────────────────┘   │
                                                                    │
                       ┌─────────────────────────────────────────────▼─┐
                       │     Service Discovery (Consul/K8s)           │
                       │  • Service Registry  • Health Checks         │
                       │  • DNS Resolution    • Load Balancing        │
                       └─────────────────────┬─────────────────────────┘
                                             │ Watches for changes
                       ┌─────────────────────▼─────────────────────────┐
                       │            GraphQL Gateway                    │
                       │  • Auto-discovers services                   │
                       │  • Polls /_service endpoints                 │
                       │  • Hot reloads schema                        │
                       └───────────────────────────────────────────────┘
```

### Implementation

#### 1. Gateway with Service Discovery
```yaml
# config/router.yaml - Service Discovery mode
supergraph:
  # Dynamic composition from discovered services
  introspection: true

# Service discovery configuration
service_discovery:
  consul:
    endpoint: "http://consul:8500"
    service_tag: "graphql-subgraph"
    poll_interval: 30s
  # OR Kubernetes
  kubernetes:
    namespace: "default"
    label_selector: "app.kubernetes.io/component=graphql-service"
    poll_interval: 30s
```

#### 2. Service Registration (Kubernetes)
```yaml
# services/inventory/k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-service
spec:
  template:
    metadata:
      labels:
        app.kubernetes.io/component: graphql-service  # Discovery label
        graphql.service/name: inventory
    spec:
      containers:
      - name: inventory
        image: inventory-service:latest
        ports:
        - containerPort: 8080
        env:
        - name: GRAPHQL_ENDPOINT
          value: "/graphql"
        - name: SERVICE_NAME
          value: "inventory"

---
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
  annotations:
    graphql.service/name: "inventory"
    graphql.service/endpoint: "/graphql"
spec:
  selector:
    app: inventory-service
  ports:
  - port: 8080
```

#### 3. Gateway Auto-Discovery Logic
```javascript
// Custom gateway with service discovery
const { ApolloGateway } = require('@apollo/gateway');

const gateway = new ApolloGateway({
  serviceList: [], // Start empty
  
  // Dynamic service discovery
  experimental_updateServiceDefinitions: async () => {
    // Discover services from Kubernetes API
    const services = await discoverGraphQLServices();
    
    return {
      serviceDefinitions: services.map(service => ({
        name: service.name,
        url: `http://${service.name}:${service.port}/graphql`
      })),
      isNewSchema: true
    };
  },
  
  // Poll for changes every 30 seconds
  experimental_pollInterval: 30000,
});
```

## Solution 3: Event-Driven Registration

### How It Works
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Service A     │    │   Service B     │    │   Service C     │
│                 │    │                 │    │                 │
│ Publishes       │    │ Publishes       │    │ Publishes       │
│ "SERVICE_UP" ───┼────┼─"SERVICE_UP" ───┼────┼─"SERVICE_UP" ───┼───┐
│ Event           │    │ Event           │    │ Event           │   │
└─────────────────┘    └─────────────────┘    └─────────────────┘   │
                                                                    │
                       ┌─────────────────────────────────────────────▼─┐
                       │              Event Bus (Kafka)               │
                       │  • Service Events    • Schema Changes        │
                       │  • Health Updates    • Configuration         │
                       └─────────────────────┬─────────────────────────┘
                                             │ Subscribes to events
                       ┌─────────────────────▼─────────────────────────┐
                       │            GraphQL Gateway                    │
                       │  • Listens for service events               │
                       │  • Auto-fetches schemas                     │
                       │  • Hot reloads composition                  │
                       └───────────────────────────────────────────────┘
```

### Implementation

#### 1. Service Registration via Events
```javascript
// services/inventory/src/startup.js
const kafka = require('kafkajs').kafka({
  clientId: 'inventory-service',
  brokers: ['kafka:9092']
});

async function registerService() {
  const producer = kafka.producer();
  await producer.connect();
  
  // Publish service registration event
  await producer.send({
    topic: 'graphql-service-events',
    messages: [{
      key: 'inventory',
      value: JSON.stringify({
        event: 'SERVICE_REGISTERED',
        service: {
          name: 'inventory',
          url: 'http://inventory-service:8080/graphql',
          schema_url: 'http://inventory-service:8080/_service',
          health_url: 'http://inventory-service:8080/health'
        },
        timestamp: new Date().toISOString()
      })
    }]
  });
  
  console.log('✅ Service registered with gateway');
}

// Register on startup
registerService();
```

#### 2. Gateway Event Listener
```javascript
// gateway/src/service-discovery.js
const kafka = require('kafkajs').kafka({
  clientId: 'graphql-gateway',
  brokers: ['kafka:9092']
});

class EventDrivenServiceDiscovery {
  constructor(gateway) {
    this.gateway = gateway;
    this.services = new Map();
  }
  
  async start() {
    const consumer = kafka.consumer({ groupId: 'gateway-service-discovery' });
    await consumer.connect();
    await consumer.subscribe({ topic: 'graphql-service-events' });
    
    await consumer.run({
      eachMessage: async ({ message }) => {
        const event = JSON.parse(message.value.toString());
        
        switch (event.event) {
          case 'SERVICE_REGISTERED':
            await this.addService(event.service);
            break;
          case 'SERVICE_DEREGISTERED':
            await this.removeService(event.service.name);
            break;
          case 'SCHEMA_UPDATED':
            await this.updateService(event.service);
            break;
        }
      }
    });
  }
  
  async addService(service) {
    console.log(`🔄 Adding service: ${service.name}`);
    
    // Fetch schema
    const schema = await fetch(`${service.schema_url}`).then(r => r.json());
    
    // Update gateway configuration
    this.services.set(service.name, {
      name: service.name,
      url: service.url,
      sdl: schema.sdl
    });
    
    // Trigger gateway reload
    await this.gateway.load({
      serviceList: Array.from(this.services.values())
    });
    
    console.log(`✅ Service ${service.name} added to gateway`);
  }
}
```

## Comparison of Approaches

| Approach | Restart Required? | Complexity | Production Ready? | Cost |
|----------|------------------|------------|------------------|------|
| **Static Config** | ❌ Yes | Low | ❌ No | Free |
| **Apollo Studio** | ✅ No | Medium | ✅ Yes | Paid |
| **Service Discovery** | ✅ No | High | ✅ Yes | Free |
| **Event-Driven** | ✅ No | High | ⚠️ Custom | Free |

## Recommended Implementation

For production systems, I recommend **Apollo Studio** because:

1. **Zero Downtime**: No gateway restarts ever needed
2. **Enterprise Features**: Schema validation, change management, rollbacks
3. **Team Collaboration**: Built-in approval workflows
4. **Monitoring**: Performance metrics and error tracking
5. **Proven**: Used by thousands of production systems

### Quick Migration to Apollo Studio

```bash
# 1. Set up Apollo Studio account and get API key

# 2. Update gateway configuration
cat > config/router.yaml << EOF
supergraph:
  apollo_key: \${env.APOLLO_KEY}
  apollo_graph_ref: \${env.APOLLO_GRAPH_REF}
  poll_interval: 10s

# Remove static subgraphs section
EOF

# 3. Publish existing schemas
npx @apollo/rover subgraph publish ${APOLLO_GRAPH_REF} \
  --name products \
  --schema products/schema.graphql \
  --routing-url http://products-service:8081/graphql

npx @apollo/rover subgraph publish ${APOLLO_GRAPH_REF} \
  --name ratings \
  --schema ratings/schema.graphql \
  --routing-url http://ratings-service:8082/graphql

# 4. Restart gateway once (last time!)
docker compose restart graphql-gateway

# 5. Future services register without gateway restarts!
```

This eliminates the operational burden and enables true microservices independence.