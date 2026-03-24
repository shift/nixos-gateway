## ADDED Requirements

### Requirement: DNS Server Configuration
The system SHALL configure Knot DNS server for authoritative DNS zones.

#### Scenario: Forward Zone Creation
- **WHEN** DNS configuration includes host records
- **THEN** forward DNS zones SHALL be created with A/AAAA records

#### Scenario: Reverse Zone Creation
- **WHEN** hosts have IP addresses configured
- **THEN** reverse DNS zones SHALL be created with PTR records

### Requirement: DNS Resolution Service
The system SHALL provide DNS resolution using Knot Resolver.

#### Scenario: Recursive Resolution
- **WHEN** clients query for external domains
- **THEN** the resolver SHALL recursively resolve and cache responses

#### Scenario: Local Zone Resolution
- **WHEN** clients query for local domain names
- **THEN** authoritative answers SHALL be provided from local zones

### Requirement: DNS Monitoring
The system SHALL collect DNS query metrics and logs.

#### Scenario: Query Logging
- **WHEN** DNS queries are processed
- **THEN** queries SHALL be logged with dnscollector for analysis