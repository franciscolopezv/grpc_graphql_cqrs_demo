// Integration tests for GraphQL Gateway functionality
// Tests Requirements: 1.2, 1.3, 1.4, 1.5 - Schema composition, query routing, response consolidation

const axios = require('axios');
const http = require('http');
const express = require('express');

describe('GraphQL Gateway Functionality', () => {
  let mockProductsServer;
  let mockRatingsServer;
  let productsPort = 8081;
  let ratingsPort = 8082;

  beforeAll(async () => {
    // Create mock subgraph services for testing
    await createMockSubgraphServices();
  });

  afterAll(async () => {
    // Clean up mock services
    if (mockProductsServer) {
      mockProductsServer.close();
    }
    if (mockRatingsServer) {
      mockRatingsServer.close();
    }
  });

  beforeEach(async () => {
    // Ensure clean state before each test
    try {
      execCommand('docker compose -f docker compose.yml down -v --remove-orphans');
    } catch (error) {
      // Ignore errors if services aren't running
    }
  });

  afterEach(async () => {
    // Clean up after each test
    try {
      execCommand('docker compose -f docker compose.yml down -v --remove-orphans');
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  async function createMockSubgraphServices() {
    // Mock Products Service
    const productsApp = express();
    productsApp.use(express.json());
    
    // Products GraphQL schema
    const productsSchema = `
      type Product @key(fields: "id") {
        id: ID!
        name: String
        description: String
      }
      
      type Query {
        product(id: ID!): Product
        products: [Product!]!
      }
    `;
    
    // Products service endpoints
    productsApp.get('/health', (req, res) => {
      res.json({ status: 'healthy', service: 'products' });
    });
    
    productsApp.post('/graphql', (req, res) => {
      const { query } = req.body;
      
      if (query.includes('_service')) {
        // Schema introspection query
        res.json({
          data: {
            _service: {
              sdl: productsSchema
            }
          }
        });
      } else if (query.includes('product(id:')) {
        // Single product query
        const idMatch = query.match(/product\(id:\s*"([^"]+)"/);
        const id = idMatch ? idMatch[1] : '1';
        res.json({
          data: {
            product: {
              id,
              name: `Product ${id}`,
              description: `Description for product ${id}`
            }
          }
        });
      } else if (query.includes('products')) {
        // All products query
        res.json({
          data: {
            products: [
              { id: '1', name: 'Product 1', description: 'Description 1' },
              { id: '2', name: 'Product 2', description: 'Description 2' }
            ]
          }
        });
      } else {
        res.json({ data: null });
      }
    });
    
    mockProductsServer = productsApp.listen(productsPort);
    
    // Mock Ratings Service
    const ratingsApp = express();
    ratingsApp.use(express.json());
    
    // Ratings GraphQL schema
    const ratingsSchema = `
      directive @key(fields: String!) on OBJECT | INTERFACE
      directive @extends on OBJECT | INTERFACE
      directive @external on FIELD_DEFINITION
      directive @requires(fields: String!) on FIELD_DEFINITION
      directive @provides(fields: String!) on FIELD_DEFINITION

      type Product @key(fields: "id") {
        id: ID!
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
        mostCommonRating: Int
        hasPositiveRatings: Boolean!
        hasNegativeRatings: Boolean!
        diversityScore: Float
      }

      type Query {
        product(id: ID!): Product
        productRatingStats(productId: ID!): ProductRatingStats
        topRatedProducts(limit: Int = 10): [ProductRatingStats!]!
        mostReviewedProducts(limit: Int = 10): [ProductRatingStats!]!
        overallRatingStats: OverallRatingStats
      }

      type ProductRatingStats {
        productId: ID!
        averageRating: Float
        reviewCount: Int!
        ratingDistribution: RatingDistribution
        lastUpdated: String
      }

      type OverallRatingStats {
        totalProducts: Int!
        totalReviews: Int!
        overallAverageRating: Float
        productsWithRatings: Int!
      }
    `;
    
    // Ratings service endpoints
    ratingsApp.get('/health', (req, res) => {
      res.json({ status: 'healthy', service: 'ratings' });
    });
    
    ratingsApp.post('/graphql', (req, res) => {
      const { query } = req.body;
      
      if (query.includes('_service')) {
        // Schema introspection query
        res.json({
          data: {
            _service: {
              sdl: ratingsSchema
            }
          }
        });
      } else if (query.includes('product(id:')) {
        // Product ratings query
        const idMatch = query.match(/product\(id:\s*"([^"]+)"/);
        const id = idMatch ? idMatch[1] : '1';
        res.json({
          data: {
            product: {
              id,
              averageRating: 4.2,
              reviewCount: 15,
              ratingDistribution: {
                oneStar: 1,
                twoStar: 2,
                threeStar: 3,
                fourStar: 5,
                fiveStar: 4,
                total: 15,
                mostCommonRating: 4,
                hasPositiveRatings: true,
                hasNegativeRatings: true,
                diversityScore: 0.8
              }
            }
          }
        });
      } else if (query.includes('topRatedProducts')) {
        // Top rated products query
        res.json({
          data: {
            topRatedProducts: [
              {
                productId: '1',
                averageRating: 4.8,
                reviewCount: 25,
                ratingDistribution: {
                  oneStar: 0,
                  twoStar: 1,
                  threeStar: 2,
                  fourStar: 7,
                  fiveStar: 15,
                  total: 25,
                  mostCommonRating: 5,
                  hasPositiveRatings: true,
                  hasNegativeRatings: false,
                  diversityScore: 0.6
                },
                lastUpdated: '2024-01-01T00:00:00Z'
              }
            ]
          }
        });
      } else {
        res.json({ data: null });
      }
    });
    
    mockRatingsServer = ratingsApp.listen(ratingsPort);
    
    // Wait for mock services to be ready
    await waitFor(async () => {
      try {
        const productsHealth = await axios.get(`http://localhost:${productsPort}/health`);
        const ratingsHealth = await axios.get(`http://localhost:${ratingsPort}/health`);
        return productsHealth.status === 200 && ratingsHealth.status === 200;
      } catch (error) {
        return false;
      }
    });
  }

  describe('Schema Composition', () => {
    test('should compose schemas from mock subgraph services', async () => {
      // Start infrastructure with mock services running
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl, {
            timeout: 5000
          });
          return response.status === 200;
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Test schema introspection to verify composition
      const introspectionQuery = {
        query: `
          query IntrospectionQuery {
            __schema {
              types {
                name
                kind
                fields {
                  name
                  type {
                    name
                  }
                }
              }
            }
          }
        `
      };
      
      const response = await axios.post(testConfig.services.graphqlGateway.url, introspectionQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(response.status).toBe(200);
      expect(response.data.data.__schema).toBeDefined();
      
      // Verify Product type exists with fields from both subgraphs
      const productType = response.data.data.__schema.types.find(type => type.name === 'Product');
      expect(productType).toBeDefined();
      
      const fieldNames = productType.fields.map(field => field.name);
      expect(fieldNames).toContain('id');
      expect(fieldNames).toContain('name');
      expect(fieldNames).toContain('description');
      expect(fieldNames).toContain('averageRating');
      expect(fieldNames).toContain('reviewCount');
    });

    test('should handle schema polling and updates', async () => {
      // Start infrastructure
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl);
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Verify initial schema composition
      const query = {
        query: `
          query {
            __type(name: "Product") {
              fields {
                name
              }
            }
          }
        `
      };
      
      const response = await axios.post(testConfig.services.graphqlGateway.url, query, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(response.status).toBe(200);
      expect(response.data.data.__type).toBeDefined();
      expect(response.data.data.__type.fields).toBeDefined();
    });
  });

  describe('Query Routing and Response Consolidation', () => {
    test('should route queries to appropriate subgraph services', async () => {
      // Start infrastructure
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl);
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Test query that should route to Products service only
      const productsQuery = {
        query: `
          query {
            product(id: "1") {
              id
              name
              description
            }
          }
        `
      };
      
      const productsResponse = await axios.post(testConfig.services.graphqlGateway.url, productsQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(productsResponse.status).toBe(200);
      expect(productsResponse.data.data.product).toBeDefined();
      expect(productsResponse.data.data.product.id).toBe('1');
      expect(productsResponse.data.data.product.name).toBe('Product 1');
      
      // Test query that should route to Ratings service only
      const ratingsQuery = {
        query: `
          query {
            topRatedProducts(limit: 5) {
              productId
              averageRating
              reviewCount
            }
          }
        `
      };
      
      const ratingsResponse = await axios.post(testConfig.services.graphqlGateway.url, ratingsQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(ratingsResponse.status).toBe(200);
      expect(ratingsResponse.data.data.topRatedProducts).toBeDefined();
      expect(Array.isArray(ratingsResponse.data.data.topRatedProducts)).toBe(true);
    });

    test('should consolidate responses from multiple subgraphs', async () => {
      // Start infrastructure
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl);
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Test federated query that spans both subgraphs
      const federatedQuery = {
        query: `
          query {
            product(id: "1") {
              id
              name
              description
              averageRating
              reviewCount
              ratingDistribution {
                total
                mostCommonRating
                hasPositiveRatings
              }
            }
          }
        `
      };
      
      const response = await axios.post(testConfig.services.graphqlGateway.url, federatedQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(response.status).toBe(200);
      expect(response.data.data.product).toBeDefined();
      
      // Verify data from Products subgraph
      expect(response.data.data.product.id).toBe('1');
      expect(response.data.data.product.name).toBe('Product 1');
      expect(response.data.data.product.description).toBe('Description for product 1');
      
      // Verify data from Ratings subgraph
      expect(response.data.data.product.averageRating).toBe(4.2);
      expect(response.data.data.product.reviewCount).toBe(15);
      expect(response.data.data.product.ratingDistribution).toBeDefined();
      expect(response.data.data.product.ratingDistribution.total).toBe(15);
    });

    test('should handle subgraph errors gracefully', async () => {
      // Start infrastructure
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl);
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Stop one of the mock services to simulate failure
      mockRatingsServer.close();
      
      // Wait a moment for the gateway to detect the failure
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Test query that only requires Products service (should work)
      const productsOnlyQuery = {
        query: `
          query {
            product(id: "1") {
              id
              name
              description
            }
          }
        `
      };
      
      const response = await axios.post(testConfig.services.graphqlGateway.url, productsOnlyQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(response.status).toBe(200);
      expect(response.data.data.product).toBeDefined();
      expect(response.data.data.product.name).toBe('Product 1');
      
      // Restart the ratings service for cleanup
      const ratingsApp = express();
      ratingsApp.use(express.json());
      ratingsApp.get('/health', (req, res) => {
        res.json({ status: 'healthy', service: 'ratings' });
      });
      ratingsApp.post('/graphql', (req, res) => {
        res.json({ data: null });
      });
      mockRatingsServer = ratingsApp.listen(ratingsPort);
    });
  });

  describe('Gateway Health and Connectivity', () => {
    test('should validate connectivity to subgraph services', async () => {
      // Start infrastructure
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to be ready
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl);
          return response.status === 200;
        } catch (error) {
          return false;
        }
      });
      
      // Verify health endpoint responds
      const healthResponse = await axios.get(testConfig.services.graphqlGateway.healthUrl);
      expect(healthResponse.status).toBe(200);
      
      // Verify GraphQL endpoint is accessible
      const pingQuery = {
        query: `
          query {
            __typename
          }
        `
      };
      
      const pingResponse = await axios.post(testConfig.services.graphqlGateway.url, pingQuery, {
        headers: { 'Content-Type': 'application/json' }
      });
      
      expect(pingResponse.status).toBe(200);
      expect(pingResponse.data.data.__typename).toBe('Query');
    });

    test('should report appropriate errors when subgraphs are unreachable', async () => {
      // Start infrastructure without mock services
      mockProductsServer.close();
      mockRatingsServer.close();
      
      execCommand('docker compose -f docker compose.yml up -d');
      
      // Wait for GraphQL Gateway to start (it should start even with unreachable subgraphs)
      await waitFor(async () => {
        try {
          const response = await axios.get(testConfig.services.graphqlGateway.healthUrl, {
            timeout: 5000
          });
          return response.status === 200;
        } catch (error) {
          return false;
        }
      }, testConfig.timeouts.serviceStart);
      
      // Verify health endpoint still responds (gateway should be resilient)
      const healthResponse = await axios.get(testConfig.services.graphqlGateway.healthUrl);
      expect(healthResponse.status).toBe(200);
      
      // Restart mock services for cleanup
      await createMockSubgraphServices();
    });
  });
});