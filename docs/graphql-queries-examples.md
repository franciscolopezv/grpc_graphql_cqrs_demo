# GraphQL Query Examples

This document provides example GraphQL queries for the platform infrastructure gateway.

## Table of Contents

- [Product Queries](#product-queries)
- [Rating Queries](#rating-queries)
- [Combined Queries](#combined-queries)
- [Statistics Queries](#statistics-queries)

## Product Queries

### Get Product by ID

Query a single product by its ID:

```graphql
query GetProduct($productId: ID!) {
  product(id: $productId) {
    id
    name
    description
  }
}
```

**Variables:**
```json
{
  "productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"
}
```

**curl Example:**
```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetProduct($productId: ID!) { product(id: $productId) { id name description } }",
    "variables": {"productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"}
  }' | jq '.'
```

## Rating Queries

### Get Rating Statistics for a Product

Query detailed rating statistics for a specific product:

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
      hasPositiveRatings
      hasNegativeRatings
      diversityScore
    }
    lastUpdated
  }
}
```

**Variables:**
```json
{
  "productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"
}
```

**curl Example:**
```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetProductRatingStats($productId: ID!) { productRatingStats(productId: $productId) { productId averageRating reviewCount ratingDistribution { oneStar twoStar threeStar fourStar fiveStar total mostCommonRating hasPositiveRatings hasNegativeRatings diversityScore } lastUpdated } }",
    "variables": {"productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"}
  }' | jq '.'
```

### Get Top Rated Products

Query the top rated products across the platform:

```graphql
query GetTopRatedProducts($limit: Int) {
  topRatedProducts(limit: $limit) {
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

**Variables:**
```json
{
  "limit": 10
}
```

**curl Example:**
```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetTopRatedProducts($limit: Int) { topRatedProducts(limit: $limit) { productId averageRating reviewCount lastUpdated } }",
    "variables": {"limit": 10}
  }' | jq '.'
```

### Get Most Reviewed Products

Query the products with the most reviews:

```graphql
query GetMostReviewedProducts($limit: Int) {
  mostReviewedProducts(limit: $limit) {
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

**Variables:**
```json
{
  "limit": 10
}
```

## Combined Queries

### Get Product with Complete Rating Information

**This is the most comprehensive query** - it fetches both product details and complete rating statistics in a single request:

```graphql
query GetProductWithRatings($productId: ID!) {
  product(id: $productId) {
    id
    name
    description
  }
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
      hasPositiveRatings
      hasNegativeRatings
      diversityScore
    }
    lastUpdated
  }
}
```

**Variables:**
```json
{
  "productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"
}
```

**curl Example:**
```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetProductWithRatings($productId: ID!) { product(id: $productId) { id name description } productRatingStats(productId: $productId) { productId averageRating reviewCount ratingDistribution { oneStar twoStar threeStar fourStar fiveStar total mostCommonRating hasPositiveRatings hasNegativeRatings diversityScore } lastUpdated } }",
    "variables": {"productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d"}
  }' | jq '.'
```

**Example Response:**
```json
{
  "data": {
    "product": {
      "id": "691e80cf-d3d9-4edd-a966-4a4493c93f2d",
      "name": "Wireless Mouse",
      "description": "Ergonomic wireless mouse with USB receiver"
    },
    "productRatingStats": {
      "productId": "691e80cf-d3d9-4edd-a966-4a4493c93f2d",
      "averageRating": 5.0,
      "reviewCount": 1,
      "ratingDistribution": {
        "oneStar": 0,
        "twoStar": 0,
        "threeStar": 0,
        "fourStar": 0,
        "fiveStar": 1,
        "total": 1,
        "mostCommonRating": 5,
        "hasPositiveRatings": true,
        "hasNegativeRatings": false,
        "diversityScore": 0.0
      },
      "lastUpdated": "2025-11-09T16:52:52.987434Z"
    }
  }
}
```

## Statistics Queries

### Get Overall Platform Rating Statistics

Query aggregate statistics across all products:

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

**curl Example:**
```bash
curl -X POST http://localhost:4000/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "query GetOverallStats { overallRatingStats { totalProducts totalReviews overallAverageRating productsWithRatings } }"
  }' | jq '.'
```

## Understanding the Rating Distribution

The `ratingDistribution` object provides detailed breakdown of ratings:

- **oneStar** through **fiveStar**: Count of ratings for each star level
- **total**: Total number of ratings
- **mostCommonRating**: The star rating that appears most frequently (1-5)
- **hasPositiveRatings**: Boolean indicating if there are any 4 or 5 star ratings
- **hasNegativeRatings**: Boolean indicating if there are any 1 or 2 star ratings
- **diversityScore**: A measure of how diverse the ratings are (0.0 = all same rating, higher = more diverse)

## Tips for Using GraphQL Queries

### 1. Use GraphQL Playground

Open http://localhost:4000 in your browser to access the GraphQL Playground where you can:
- Explore the schema with autocomplete
- Test queries interactively
- View documentation for all available fields

### 2. Request Only What You Need

GraphQL allows you to request exactly the fields you need:

```graphql
# Minimal query - just the essentials
query GetProductBasic($productId: ID!) {
  product(id: $productId) {
    id
    name
  }
  productRatingStats(productId: $productId) {
    averageRating
    reviewCount
  }
}
```

### 3. Use Aliases for Multiple Queries

Query multiple products in a single request using aliases:

```graphql
query GetMultipleProducts {
  product1: product(id: "id-1") {
    id
    name
  }
  product2: product(id: "id-2") {
    id
    name
  }
}
```

### 4. Use Fragments for Reusable Fields

Define reusable field sets with fragments:

```graphql
fragment ProductDetails on Product {
  id
  name
  description
}

fragment RatingDetails on ProductRatingStats {
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
}

query GetProductWithRatings($productId: ID!) {
  product(id: $productId) {
    ...ProductDetails
  }
  productRatingStats(productId: $productId) {
    ...RatingDetails
  }
}
```

## Error Handling

If a product doesn't exist or there's an error, you'll receive an error response:

```json
{
  "data": {
    "product": null,
    "productRatingStats": null
  },
  "errors": [
    {
      "message": "Product not found",
      "path": ["product"]
    }
  ]
}
```

## Next Steps

- Explore the [End-to-End Testing Guide](./end-to-end-testing.md) for complete testing workflows
- Check the [GraphQL Gateway Documentation](../README-GraphQL-Gateway.md) for architecture details
- Review the [Supergraph Schema](../config/supergraph.graphql) for all available types and fields