# Kafka Message Bus Guide

## Overview

The Kafka message bus provides reliable, scalable event streaming for domain-to-domain communication in the platform infrastructure. It enables loose coupling between services while maintaining data consistency through event-driven architecture patterns.

## Connection Parameters

### Service Configuration

- **Kafka Broker**: `kafka:29092` (internal Docker network)
- **External Access**: `localhost:9092` (from host machine)
- **Zookeeper**: `zookeeper:2181`
- **JMX Monitoring**: `localhost:9101`

### Environment Variables

```bash
# Kafka Bootstrap Servers (for service connections)
KAFKA_BOOTSTRAP_SERVERS=kafka:29092

# Alternative external connection (for development/testing)
KAFKA_EXTERNAL_BOOTSTRAP_SERVERS=localhost:9092
```

### Docker Network Configuration

Services connecting to Kafka must be on the same Docker network:

```yaml
# In your service's docker-compose.yml
services:
  your-service:
    networks:
      - platform-infrastructure

networks:
  platform-infrastructure:
    external: true
```

## Topic Configuration

### Available Topics

#### products_events
- **Purpose**: Product domain events for cross-team consumption
- **Partitions**: 3 (default)
- **Replication Factor**: 1
- **Retention**: 7 days (168 hours)
- **Cleanup Policy**: Delete

#### ratings_events  
- **Purpose**: Ratings domain events for cross-team consumption
- **Partitions**: 3 (default)
- **Replication Factor**: 1
- **Retention**: 7 days (168 hours)
- **Cleanup Policy**: Delete

### Topic Auto-Creation

Topics are automatically created when first accessed. Default configuration:
- **Partitions**: 3
- **Replication Factor**: 1
- **Retention**: 7 days
- **Compression**: Producer (recommended: snappy or lz4)

## Message Publishing Patterns

### Products Events

#### Event Types
- `product.created` - New product added to catalog
- `product.updated` - Product information modified
- `product.deleted` - Product removed from catalog
- `product.price_changed` - Product pricing updated

#### Message Format
```json
{
  "eventType": "product.created",
  "timestamp": "2024-01-01T00:00:00Z",
  "productId": "550e8400-e29b-41d4-a716-446655440000",
  "correlationId": "req-123456789",
  "version": "1.0",
  "data": {
    "name": "Premium Wireless Headphones",
    "description": "High-quality wireless headphones with noise cancellation",
    "price": 299.99,
    "category": "electronics",
    "sku": "WH-1000XM4"
  }
}
```

#### Publishing Example (Node.js)
```javascript
const { Kafka } = require('kafkajs');

const kafka = Kafka({
  clientId: 'products-service',
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS || 'kafka:29092']
});

const producer = kafka.producer();

async function publishProductEvent(eventType, productId, data) {
  await producer.send({
    topic: 'products_events',
    messages: [{
      key: productId,
      value: JSON.stringify({
        eventType,
        timestamp: new Date().toISOString(),
        productId,
        correlationId: generateCorrelationId(),
        version: '1.0',
        data
      }),
      headers: {
        'content-type': 'application/json',
        'event-type': eventType
      }
    }]
  });
}

// Usage
await publishProductEvent('product.created', productId, {
  name: 'New Product',
  description: 'Product description',
  price: 99.99
});
```

### Ratings Events

#### Event Types
- `rating.created` - New rating submitted
- `rating.updated` - Rating modified by user
- `rating.deleted` - Rating removed
- `rating.moderated` - Rating flagged/approved by moderation

#### Message Format
```json
{
  "eventType": "rating.created",
  "timestamp": "2024-01-01T00:00:00Z",
  "ratingId": "660e8400-e29b-41d4-a716-446655440001",
  "productId": "550e8400-e29b-41d4-a716-446655440000",
  "correlationId": "req-987654321",
  "version": "1.0",
  "data": {
    "userId": "770e8400-e29b-41d4-a716-446655440002",
    "score": 5,
    "comment": "Excellent product, highly recommended!",
    "verified": true
  }
}
```

#### Publishing Example (Node.js)
```javascript
async function publishRatingEvent(eventType, ratingId, productId, data) {
  await producer.send({
    topic: 'ratings_events',
    messages: [{
      key: productId, // Partition by product for ordering
      value: JSON.stringify({
        eventType,
        timestamp: new Date().toISOString(),
        ratingId,
        productId,
        correlationId: generateCorrelationId(),
        version: '1.0',
        data
      }),
      headers: {
        'content-type': 'application/json',
        'event-type': eventType
      }
    }]
  });
}
```

## Message Consumption Patterns

### Consumer Group Configuration

```javascript
const consumer = kafka.consumer({ 
  groupId: 'ratings-service-consumer',
  sessionTimeout: 30000,
  heartbeatInterval: 3000
});

await consumer.subscribe({ 
  topics: ['products_events'],
  fromBeginning: false 
});

await consumer.run({
  eachMessage: async ({ topic, partition, message }) => {
    const event = JSON.parse(message.value.toString());
    
    switch (event.eventType) {
      case 'product.created':
        await handleProductCreated(event);
        break;
      case 'product.updated':
        await handleProductUpdated(event);
        break;
      case 'product.deleted':
        await handleProductDeleted(event);
        break;
      default:
        console.log(`Unknown event type: ${event.eventType}`);
    }
  },
});
```

### Error Handling and Retry Logic

```javascript
await consumer.run({
  eachMessage: async ({ topic, partition, message }) => {
    try {
      const event = JSON.parse(message.value.toString());
      await processEvent(event);
    } catch (error) {
      console.error('Error processing message:', error);
      
      // Implement retry logic or dead letter queue
      if (error.retryable) {
        throw error; // Will be retried by Kafka
      } else {
        // Log and continue (or send to DLQ)
        await logFailedMessage(message, error);
      }
    }
  },
});
```

## Best Practices

### Message Design
1. **Include Correlation IDs**: For request tracing across services
2. **Use Semantic Versioning**: Version your message schemas
3. **Idempotent Processing**: Design consumers to handle duplicate messages
4. **Include Timestamps**: Use ISO 8601 format for all timestamps

### Partitioning Strategy
- **Products Events**: Partition by `productId` for ordering guarantees
- **Ratings Events**: Partition by `productId` to maintain rating order per product
- **Key Selection**: Use meaningful keys that distribute load evenly

### Consumer Groups
- **One Consumer Group per Service**: Each consuming service should have its own group
- **Parallel Processing**: Use multiple consumers in the same group for scalability
- **Offset Management**: Let Kafka manage offsets automatically

### Performance Optimization
```javascript
// Producer configuration for high throughput
const producer = kafka.producer({
  maxInFlightRequests: 1,
  idempotent: true,
  transactionTimeout: 30000,
  compression: 'snappy'
});

// Consumer configuration for reliability
const consumer = kafka.consumer({
  groupId: 'my-service',
  sessionTimeout: 30000,
  rebalanceTimeout: 60000,
  heartbeatInterval: 3000,
  maxBytesPerPartition: 1048576,
  minBytes: 1,
  maxBytes: 10485760,
  maxWaitTimeInMs: 5000
});
```

## Monitoring and Debugging

### Health Checks

```bash
# Check Kafka broker status
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092

# List topics
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Describe topic configuration
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --describe --topic products_events
```

### Consumer Group Monitoring

```bash
# List consumer groups
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --list

# Check consumer group status
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group ratings-service-consumer
```

### Message Inspection

```bash
# Consume messages from beginning (for debugging)
docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic products_events --from-beginning

# Produce test message
docker exec kafka kafka-console-producer --bootstrap-server localhost:9092 --topic products_events
```

### JMX Metrics

Kafka exposes JMX metrics on port 9101. Key metrics to monitor:
- `kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec`
- `kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec`
- `kafka.network:type=RequestMetrics,name=RequestsPerSec`
- `kafka.server:type=ReplicaManager,name=LeaderCount`

## Troubleshooting

### Common Issues

#### Connection Refused
```bash
# Check if Kafka is running
docker-compose ps kafka

# Check Kafka logs
docker-compose logs kafka

# Verify network connectivity
docker exec your-service nc -zv kafka 29092
```

#### Topic Not Found
```bash
# Create topic manually if auto-creation is disabled
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --create --topic your-topic --partitions 3 --replication-factor 1
```

#### Consumer Lag
```bash
# Check consumer group lag
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group your-consumer-group

# Reset consumer group offset (use with caution)
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --group your-consumer-group --reset-offsets --to-earliest --topic your-topic --execute
```

### Log Analysis

```bash
# Kafka broker logs
docker-compose logs kafka | grep ERROR

# Zookeeper logs  
docker-compose logs zookeeper | grep ERROR

# Application logs with Kafka client errors
docker-compose logs your-service | grep -i kafka
```

## Development and Testing

### Local Development Setup

1. **Start Infrastructure**:
   ```bash
   docker-compose up -d kafka zookeeper
   ```

2. **Wait for Services**:
   ```bash
   # Wait for health checks to pass
   docker-compose ps
   ```

3. **Create Test Topics** (if needed):
   ```bash
   docker exec kafka kafka-topics --bootstrap-server localhost:9092 --create --topic test-events --partitions 1 --replication-factor 1
   ```

### Integration Testing

```javascript
// Example integration test
describe('Kafka Integration', () => {
  let producer, consumer;
  
  beforeAll(async () => {
    const kafka = Kafka({
      clientId: 'test-client',
      brokers: ['localhost:9092']
    });
    
    producer = kafka.producer();
    consumer = kafka.consumer({ groupId: 'test-group' });
    
    await producer.connect();
    await consumer.connect();
  });
  
  test('should publish and consume product event', async () => {
    const testEvent = {
      eventType: 'product.created',
      productId: 'test-123',
      data: { name: 'Test Product' }
    };
    
    // Set up consumer
    const messages = [];
    await consumer.subscribe({ topics: ['products_events'] });
    await consumer.run({
      eachMessage: async ({ message }) => {
        messages.push(JSON.parse(message.value.toString()));
      }
    });
    
    // Publish event
    await producer.send({
      topic: 'products_events',
      messages: [{ value: JSON.stringify(testEvent) }]
    });
    
    // Wait and verify
    await new Promise(resolve => setTimeout(resolve, 1000));
    expect(messages).toHaveLength(1);
    expect(messages[0].eventType).toBe('product.created');
  });
});
```

## Security Considerations

### Network Security
- Kafka runs on internal Docker network by default
- External access only on localhost:9092 for development
- Production deployments should use TLS/SSL encryption

### Authentication (Future Enhancement)
- Current setup uses no authentication (suitable for internal services)
- Consider SASL/SCRAM or mTLS for production environments
- Implement ACLs for topic-level access control

### Message Security
- Sensitive data should be encrypted at the application level
- Use correlation IDs instead of sensitive identifiers in message keys
- Implement message schema validation to prevent malformed data

## Support and Resources

### Documentation Links
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [KafkaJS Client Library](https://kafka.js.org/)
- [Confluent Platform Documentation](https://docs.confluent.io/)

### Platform Team Contact
- For infrastructure issues: Contact the platform team
- For topic configuration changes: Submit a platform infrastructure request
- For performance optimization: Schedule a consultation with the platform team