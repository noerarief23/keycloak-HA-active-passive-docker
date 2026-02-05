# Implementation Plan

- [x] 1. Create HAProxy directory structure and configuration files


  - Create `haproxy/` directory with subdirectories for certs, errors, and scripts
  - Create base `haproxy.cfg` configuration file with global and defaults sections
  - Create `.gitignore` file to exclude sensitive certificate files
  - _Requirements: 7.1, 7.3, 8.3_




- [x] 2. Implement HAProxy core configuration

  - [x] 2.1 Configure global and defaults sections in haproxy.cfg

    - Set up logging to stdout with appropriate format
    - Configure SSL/TLS defaults with secure ciphers and TLS 1.2+ only
    - Set connection limits and timeouts


    - Configure stats socket for runtime API
    - _Requirements: 4.5, 7.1_


  - [ ] 2.2 Implement HTTP/HTTPS frontends for Keycloak
    - Create HTTP frontend on port 80 with redirect to HTTPS

    - Create HTTPS frontend on port 443 with SSL termination
    - Configure X-Forwarded-For headers and security headers
    - Set up request logging with detailed format
    - _Requirements: 1.3, 1.4, 2.1, 4.1, 4.2, 4.4, 9.1_

  - [x] 2.3 Implement PostgreSQL TCP frontend

    - Create TCP frontend on port 5432
    - Configure connection and client timeouts for database connections
    - Set up PostgreSQL-specific logging format
    - _Requirements: 1.5, 3.1, 9.2_

  - [x] 2.4 Implement statistics frontend


    - Create stats frontend on port 8404
    - Configure HTTP basic authentication using environment variables




    - Enable stats page with auto-refresh
    - Enable Prometheus metrics endpoint
    - _Requirements: 1.6, 5.1, 5.4_

- [ ] 3. Implement backend configurations with health checks
  - [x] 3.1 Configure Keycloak backend with HTTP health checks


    - Define backend with roundrobin load balancing
    - Add primary server with IP 172.20.0.11:8080
    - Add replica server with IP 172.20.0.21:8080 as backup
    - Configure HTTP health check to `/health/ready` endpoint
    - Set health check parameters: inter 5s, fall 3, rise 2





    - _Requirements: 2.2, 2.3, 2.4, 2.5, 6.1, 6.2, 6.3_

  - [ ] 3.2 Configure PostgreSQL backend with pgsql-check
    - Define backend with TCP mode and roundrobin balancing


    - Add primary PostgreSQL server (configurable IP:5432)
    - Add replica PostgreSQL server (configurable IP:5433) as backup
    - Configure native pgsql-check with dedicated check user
    - Set health check parameters: inter 3s, fall 3, rise 2
    - _Requirements: 3.2, 3.3, 3.4, 3.5, 6.1, 6.2, 6.3_



- [-] 4. Create Docker Compose configuration for HAProxy



  - [ ] 4.1 Create docker-compose-lb.yml file
    - Define HAProxy service using haproxy:2.9-alpine image
    - Configure container name and hostname
    - Set up network mode (host or bridge based on deployment)
    - _Requirements: 1.1, 8.1, 8.2_


  - [ ] 4.2 Configure volume mounts and ports
    - Mount haproxy.cfg as read-only
    - Mount certs directory as read-only
    - Mount errors directory as read-only
    - Expose ports 80, 443, 5432, and 8404
    - _Requirements: 1.3, 1.4, 1.5, 1.6, 8.3, 8.4_

  - [ ] 4.3 Add environment variables and health checks
    - Define HAPROXY_STATS_USER and HAPROXY_STATS_PASSWORD environment variables
    - Create container health check using HAProxy stats socket
    - Configure restart policy
    - _Requirements: 7.4, 8.5_

- [x] 5. Create SSL certificate generation and management scripts

  - [x] 5.1 Create generate-cert.sh script for self-signed certificates

    - Generate RSA private key and self-signed certificate
    - Combine certificate and key into PEM format
    - Generate DH parameters for forward secrecy
    - Set appropriate file permissions (600)
    - _Requirements: 4.3, 10.2_

  - [x] 5.2 Create certificate installation documentation

    - Document self-signed certificate generation process
    - Document Let's Encrypt certificate installation
    - Document certificate renewal procedures
    - Document certificate format requirements

    - _Requirements: 4.3, 10.2_

- [x] 6. Create custom error pages

  - Create custom HTTP error pages for codes 400, 403, 408, 500, 502, 503, 504
  - Design error pages with consistent branding and helpful messages
  - Include retry instructions for 502/503 errors
  - _Requirements: 2.1_

- [x] 7. Implement operational scripts



  - [x] 7.1 Create test-failover.sh script


    - Script to stop primary services and verify failover
    - Check HAProxy stats for backend status changes
    - Verify traffic routes to backup servers
    - Measure failover time
    - _Requirements: 6.1, 6.2, 6.3, 10.5_



  - [ ] 7.2 Create check-backends.sh script
    - Query HAProxy stats API for backend health
    - Display current status of all servers
    - Show health check results and timing
    - Alert on any DOWN backends
    - _Requirements: 5.2, 5.3, 10.4_

- [x] 8. Create environment configuration files




  - [ ] 8.1 Create .env.lb.example file
    - Define HAPROXY_STATS_USER with example value
    - Define HAPROXY_STATS_PASSWORD with placeholder
    - Define PRIMARY_SERVER_IP and REPLICA_SERVER_IP variables
    - Add comments explaining each variable


    - _Requirements: 7.4_

  - [x] 8.2 Update main .env files to include HAProxy variables

    - Add HAProxy-related variables to existing .env.primary.example
    - Add HAProxy-related variables to existing .env.replica.example
    - Document the relationship between HAProxy and backend servers
    - _Requirements: 7.4_

- [-] 9. Implement logging configuration



  - Configure HAProxy to log all HTTP requests with detailed information
  - Configure HAProxy to log PostgreSQL connection attempts
  - Configure HAProxy to log health check state changes
  - Set up log format to include client IP, response codes, and timing
  - _Requirements: 5.5, 6.4, 9.1, 9.2, 9.3, 9.4, 9.5_


- [ ] 10. Create comprehensive documentation
  - [ ] 10.1 Create HAPROXY.md deployment guide
    - Document prerequisites and server requirements
    - Provide step-by-step deployment instructions
    - Include configuration examples with explanations


    - Document network and firewall requirements
    - _Requirements: 10.1_

  - [ ] 10.2 Document SSL/TLS certificate management
    - Self-signed certificate generation for testing
    - Let's Encrypt certificate installation for production
    - Certificate renewal procedures
    - Troubleshooting certificate issues
    - _Requirements: 10.2_

  - [ ] 10.3 Create troubleshooting guide
    - Common HAProxy issues and solutions
    - Health check failure diagnosis
    - Backend connectivity problems
    - SSL/TLS configuration issues
    - Performance tuning tips
    - _Requirements: 10.3_

  - [ ] 10.4 Document monitoring and metrics
    - How to access and interpret stats page
    - Key metrics to monitor
    - Setting up Prometheus scraping
    - Creating alerts for critical conditions
    - _Requirements: 10.4_

  - [ ] 10.5 Create failover testing procedures
    - Step-by-step failover test scenarios
    - Expected behavior during failover
    - Verification steps after failover
    - Failback procedures
    - _Requirements: 10.5_

  - [ ] 10.6 Update main README.md
    - Add HAProxy to architecture diagram
    - Update quick start guide to include HAProxy deployment
    - Add HAProxy to features list
    - Update network topology documentation
    - _Requirements: 10.1_

  - [ ] 10.7 Update OPERATIONS.md
    - Add HAProxy health checks to daily operations
    - Include HAProxy in backup procedures
    - Add HAProxy monitoring to weekly maintenance
    - Document HAProxy configuration changes process
    - _Requirements: 10.1_

- [ ] 11. Create validation and testing scripts
  - [ ] 11.1 Create validate-config.sh script
    - Validate HAProxy configuration syntax
    - Check SSL certificate validity
    - Verify backend connectivity
    - Test health check endpoints
    - _Requirements: 7.3_

  - [ ] 11.2 Create integration test script
    - Test HTTP connectivity through HAProxy
    - Test HTTPS connectivity with SSL verification
    - Test PostgreSQL connectivity through HAProxy
    - Test stats page authentication
    - Verify health checks are working
    - _Requirements: 2.1, 3.1, 4.1, 5.4_

  - [ ] 11.3 Create load testing script
    - Use Apache Bench or wrk for HTTP load testing
    - Test PostgreSQL connection pooling under load
    - Simulate failover during load test
    - Measure performance impact of HAProxy
    - _Requirements: 2.1, 3.1_

- [ ] 12. Implement security hardening
  - [ ] 12.1 Configure secure file permissions
    - Set haproxy.cfg to read-only (644)
    - Set SSL certificates to restricted access (600)
    - Set private keys to owner-only access (600)
    - Create .gitignore to exclude sensitive files
    - _Requirements: 4.3, 7.1_

  - [ ] 12.2 Implement security headers
    - Add Strict-Transport-Security header
    - Add X-Frame-Options header
    - Add X-Content-Type-Options header
    - Add X-XSS-Protection header
    - _Requirements: 4.5_

- [ ] 13. Create deployment automation
  - [ ] 13.1 Create deploy-haproxy.sh script
    - Check prerequisites (Docker, network connectivity)
    - Create directory structure
    - Generate or validate SSL certificates
    - Start HAProxy container
    - Verify health checks
    - Display stats page URL and credentials
    - _Requirements: 1.1, 10.1_

  - [ ] 13.2 Create rollback script
    - Stop HAProxy container
    - Backup current configuration
    - Restore previous configuration
    - Restart HAProxy
    - Verify functionality
    - _Requirements: 10.1_

- [ ] 14. Final integration and verification
  - [ ] 14.1 Deploy HAProxy on test environment
    - Set up Server C with Docker
    - Deploy HAProxy using docker-compose-lb.yml
    - Configure backend IPs for test servers
    - Verify all health checks pass
    - _Requirements: 1.1, 2.2, 3.2_

  - [ ] 14.2 Perform end-to-end testing
    - Test Keycloak login through HAProxy
    - Test PostgreSQL queries through HAProxy
    - Simulate primary Keycloak failure and verify failover
    - Simulate primary PostgreSQL failure and verify failover
    - Verify monitoring and logging work correctly
    - _Requirements: 2.3, 3.3, 6.1, 6.2, 6.3, 9.1, 9.2_

  - [ ] 14.3 Update architecture documentation
    - Update architecture diagrams to include HAProxy
    - Document new network topology
    - Update failover procedures to include HAProxy
    - Document DNS/load balancer update procedures
    - _Requirements: 10.1, 10.5_
