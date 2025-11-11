# End-to-End Testing Guide

This guide provides instructions for testing the complete platform infrastructure, from creating products and ratings via gRPC to querying data through the GraphQL Gateway.

## Prerequisites

Before running the tests, ensure you have:

1. **Infrastructure running**: Start with `./scripts/start-infrastructure.sh`
2. **grpcurl installed**: `brew install grpcurl` (macOS) or see [grpcurl installation](https://github.com/fullstorydev/grpcurl)
3. **curl installed**: Usually pre-installed on most systems
4. **jq installed** (optional): `brew install jq` for formatted JSON output

## Automated Testing

### Quick Test

Run the automated end-to-end test script:

```bash
./scripts/test-end-to-end.sh
```

This script will:
1. Create a product via gRPC
2. Wait for Kafka event propagation (5 seconds)
3. Submit a rating for the product via gRPC
4. Wait for Kafka event propagation (5 seconds)
5. Query the product and ratings via GraphQL Gateway
6. Display all results

**Note:** The script includes delays between operations to allow time for Kafka messages to be consumed and processed by the query services. You can customize the delay:

```bash
# Use a longer delay (10 seconds) for slower systems
EVENT_PROPAGATION_DELAY=10 ./scripts/test-end-to-end.sh

# Use a shorter delay (2 seconds) for faster systems
EVENT_PROPAGATION_DELAY=2 ./scripts/test-end-to-end.sh
```

## Manual Testing

### Step 1: Create a Product

Create a product using the Products service gRPC API:

```bash
grpcurl -plaintext \
  -proto products.proto \
  -d '{
    "name": "Wireless Mouse",
    "description": "Ergonomic wireless mouse with USB receiver"
  }' \
  localhost:50051 \
  products.ProductsCommandService/CreateProduct
```

**Expected Response:**

```json
{
  "productId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "SUCCESS"
}
```

**Save the `productId` value** - you'll need it for the next steps.

**Important:** Wait 5-10 seconds after creating the product to allow the Kafka event to be consumed by the query service before proceeding to the next step.

### Step 2: Submit a Rating

Submit a rating for the product using the Ratings service gRPC API:

```bash
grpcurl -plaintext \
  -d '{
    "product_id": "550e8400-e29b-41d4-a716-446655440000",
    "rating": 5,
    "user_id": "user-456",
    "review_text": "Excellent product! Highly recommended."
  }' \
  localhost:9090 \
  com.ratings.RatingsCommandService/SubmitRating
```

**Expected Response:**

```json
{
  "id": "rating-123",
  "productId": "550e8400-e29b-41d4-a716-446655440000",
  "rating": 5,
  "userId": "user-456",
  "reviewText": "Excellent product! Highly recommended.",
  "createdAt": "2023-11-05T10:35:00Z"
}
```

**Important:** Wait 5-10 seconds after submitting the rating to allow the Kafka event to be consumed by the query service before querying via GraphQL.

### Step 3: Query via GraphQL Gateway

Now query the product and its ratings through the GraphQL Gateway.

#### Option A: Using GraphQL Playground (Recommended)

1. Open your browser and navigate to: http://localhost:4000
2. Use the GraphQL Playground interface
3. Try the following queries:

**Query a specific product with rating information:**

```graphql
query GetProductWithRatings($productId: ID!) {
  product(id: $productId) {
    id
    name
    description
    averageRating
    reviewCount
    ratingDistribution {
      oneStar
      twoStar
      threeStar
      fourStar
      fiveStar
      total
      mostCommonRating
      hasPositiveRatings
      hasNegativeRatings
    }
  }
}
```

**Query Variables:**

```json
{
  "productId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Query top rated products:**

```graphql
query GetTopRatedProducts {
  topRatedProducts(limit: 10) {
    productId
    averageRating
    reviewCount
    ratingDistribution {
      fiveStar
      fourStar
      threeStar
      twoStar
      oneStar
      total
    }
    lastUpdated
  }
}
```

**Query rating statistics for a product:**

```graphql
query GetProductRatingStats($productId: ID!) {
  productRatingStats(productId: $productId) {
    productId
    averageRating
    reviewCount
    ratingDistribution {
      oneStar
      twoStar
      threeStar
      fourStar
      fiveStar
      total
      mostCommonRating
    }
    lastUpdated
  }
}
```

**Query overall rating statistics:**

```graphql
query GetOverallStats {
  overallRatingStats {
    totalProducts
    totalReviews
    overallAverageRating
    productsWithRatings
  }
}
```

#### Option B: Using curl

Query a specific product with rating information:

```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetProductWithRatings($productId: ID!) { product(id: $productId) { id name description averageRating reviewCount ratingDistribution { oneStar twoStar threeStar fourStar fiveStar total } } }",
    "variables": {
      "productId": "550e8400-e29b-41d4-a716-446655440000"
    }
  }' | jq '.'
```

Query top rated products:

```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetTopRatedProducts { topRatedProducts(limit: 10) { productId averageRating reviewCount lastUpdated } }"
  }' | jq '.'
```

Query rating statistics for a product:

```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetProductRatingStats($productId: ID!) { productRatingStats(productId: $productId) { productId averageRating reviewCount ratingDistribution { oneStar twoStar threeStar fourStar fiveStar total } } }",
    "variables": {
      "productId": "550e8400-e29b-41d4-a716-446655440000"
    }
  }' | jq '.'
```

## Testing Multiple Products and Ratings

### Create Multiple Products

```bash
# Product 1: Wireless Mouse
grpcurl -plaintext -proto products.proto \
  -d '{"name": "Wireless Mouse", "description": "Ergonomic wireless mouse"}' \
  localhost:50051 products.ProductsCommandService/CreateProduct

# Product 2: Mechanical Keyboard
grpcurl -plaintext -proto products.proto \
  -d '{"name": "Mechanical Keyboard", "description": "RGB mechanical keyboard"}' \
  localhost:50051 products.ProductsCommandService/CreateProduct

# Product 3: USB-C Hub
grpcurl -plaintext -proto products.proto \
  -d '{"name": "USB-C Hub", "description": "7-in-1 USB-C hub with HDMI"}' \
  localhost:50051 products.ProductsCommandService/CreateProduct
```

### Submit Multiple Ratings

```bash
# Rating 1 for Product 1
grpcurl -plaintext \
  -d '{"product_id": "PRODUCT_ID_1", "rating": 5, "user_id": "user-001", "review_text": "Excellent!"}' \
  localhost:9090 com.ratings.RatingsCommandService/SubmitRating

# Rating 2 for Product 1
grpcurl -plaintext \
  -d '{"product_id": "PRODUCT_ID_1", "rating": 4, "user_id": "user-002", "review_text": "Very good"}' \
  localhost:9090 com.ratings.RatingsCommandService/SubmitRating

# Rating 3 for Product 2
grpcurl -plaintext \
  -d '{"product_id": "PRODUCT_ID_2", "rating": 5, "user_id": "user-003", "review_text": "Amazing keyboard!"}' \
  localhost:9090 com.ratings.RatingsCommandService/SubmitRating
```

## Verifying Event Propagation

### Check Kafka Messages

If you want to verify that events are being published to Kafka:

```bash
# List Kafka topics
docker exec -it kafka kafka-topics --list --bootstrap-server localhost:9092

# Consume messages from products_events topic
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic products_events \
  --from-beginning

# Consume messages from ratings_events topic
docker exec -it kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ratings_events \
  --from-beginning
```

### Check PostgreSQL Data

Verify data in the databases:

```bash
# Connect to PostgreSQL
docker exec -it postgres psql -U platform_user -d products_db

# Query products
SELECT * FROM products;

# Exit
\q

# Connect to ratings database
docker exec -it postgres psql -U platform_user -d ratings_db

# Query ratings
SELECT * FROM ratings;

# Exit
\q
```

## Troubleshooting

### Services Not Running

If you get connection errors, check if services are running:

```bash
# Check service status
docker-compose ps

# Check service logs
docker-compose logs graphql-gateway
docker-compose logs kafka
docker-compose logs postgres
```

### gRPC Service Not Responding

**Note:** The Products service does not support gRPC reflection API, so you cannot use `grpcurl list` to check it. Instead, check if the port is open:

```bash
# Check if Products service port is open
nc -z localhost 50051 && echo "Products service is running" || echo "Products service is not running"

# For Ratings service (if it supports reflection)
grpcurl -plaintext localhost:9090 list

# Describe a service (only works with reflection API)
grpcurl -plaintext localhost:9090 describe com.ratings.RatingsCommandService
```

If you need to test the Products service without reflection, you must use the proto file:

```bash
# Test Products service with proto file
grpcurl -plaintext -proto products.proto localhost:50051 list

# Or directly call a method
grpcurl -plaintext -proto products.proto \
  -d '{"name": "Test", "description": "Test"}' \
  localhost:50051 \
  products.ProductsCommandService/CreateProduct
```

### GraphQL Gateway Not Responding

```bash
# Check if gateway is responding
# Note: Apollo Router uses / as the GraphQL endpoint, not /graphql
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{"query": "{__typename}"}'

# Expected response: {"data":{"__typename":"Query"}}

# Check if gateway is running
docker-compose logs graphql-gateway

# Check if port is open
nc -z localhost 4000 && echo "Gateway port is open" || echo "Gateway port is closed"
```

### Invalid Product ID

Make sure you're using the actual product ID returned from the CreateProduct response. Product IDs are UUIDs and must match exactly.

## Expected Results

After completing all steps, you should see:

1. ✅ Product created with a unique ID
2. ✅ Rating submitted and linked to the product
3. ✅ GraphQL queries return the product with its ratings
4. ✅ Events published to Kafka topics
5. ✅ Data persisted in PostgreSQL databases

## Next Steps

- Explore more GraphQL queries in the Playground
- Test error scenarios (invalid IDs, missing fields)
- Monitor Kafka messages for event-driven communication
- Test with multiple concurrent requests
- Implement additional services and integrate them

## Additional Resources

- [GraphQL Gateway Documentation](../README-GraphQL-Gateway.md)
- [Kafka Message Bus Documentation](./kafka-message-bus.md)
- [PostgreSQL Setup Documentation](./postgresql-setup.md)
- [Adding Services to Gateway](./adding-services-to-gateway.md)