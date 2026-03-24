## ADDED Requirements

### Requirement: Traffic Classification
The system SHALL classify network traffic for QoS treatment.

#### Scenario: Application-Aware Classification
- **WHEN** app-aware QoS is enabled
- **THEN** traffic SHALL be classified by application/protocol

#### Scenario: Device-Based Classification
- **WHEN** device bandwidth limits are set
- **THEN** traffic SHALL be classified by source device

### Requirement: Bandwidth Management
The system SHALL enforce bandwidth limits and priorities.

#### Scenario: Rate Limiting
- **WHEN** bandwidth limits are configured
- **THEN** traffic SHALL be rate-limited to specified speeds

#### Scenario: Priority Queuing
- **WHEN** QoS policies define priorities
- **THEN** high-priority traffic SHALL be queued preferentially

### Requirement: Traffic Shaping
The system SHALL shape traffic patterns for optimal performance.

#### Scenario: Buffer Management
- **WHEN** QoS is active
- **THEN** traffic buffers SHALL be managed to prevent congestion

#### Scenario: Fair Queuing
- **WHEN** multiple flows compete
- **THEN** bandwidth SHALL be fairly distributed

### Requirement: DSCP Marking
The system SHALL mark packets with appropriate DSCP values.

#### Scenario: Service-Based Marking
- **WHEN** traffic is classified
- **THEN** packets SHALL be marked with DSCP values for QoS treatment