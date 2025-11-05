# Platform Infrastructure Documentation

This directory contains documentation for the platform infrastructure components.

## Available Documentation

### Database Services
- [PostgreSQL Setup and Connection Guide](./postgresql-setup.md) - Comprehensive guide for connecting to and managing PostgreSQL databases

### Message Bus Services
- [Kafka Message Bus Guide](./kafka-message-bus.md) - Complete guide for event-driven communication using Kafka

### Coming Soon
- GraphQL Gateway Guide - Documentation for unified API access
- Deployment and Operations Guide - Production deployment best practices

## Quick Start

1. **Database Connections**: See [PostgreSQL Setup Guide](./postgresql-setup.md) for connection parameters and examples
2. **Message Bus**: See [Kafka Message Bus Guide](./kafka-message-bus.md) for event publishing and consumption patterns
3. **Environment Configuration**: Check the `.env.template` file for all available configuration options
4. **Service Health**: Use `docker-compose ps` to check service status

## Getting Help

If you encounter issues with the platform infrastructure:

1. Check the service logs: `docker-compose logs [service-name]`
2. Verify service health: `docker-compose ps`
3. Review the relevant documentation in this directory
4. Contact the platform team for additional support