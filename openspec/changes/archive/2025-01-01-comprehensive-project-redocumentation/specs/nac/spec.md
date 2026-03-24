## ADDED Requirements

### Requirement: 802.1X Authentication
The system SHALL support 802.1X network access control.

#### Scenario: EAP Configuration
- **WHEN** 802.1X is enabled
- **THEN** EAP authentication SHALL be configured

#### Scenario: RADIUS Integration
- **WHEN** RADIUS server is configured
- **THEN** authentication requests SHALL be forwarded

### Requirement: Time-Based Access
The system SHALL control access based on time schedules.

#### Scenario: Schedule Definition
- **WHEN** time policies are configured
- **THEN** access SHALL be granted/denied based on schedule

#### Scenario: Policy Enforcement
- **WHEN** access is requested outside allowed times
- **THEN** access SHALL be denied

### Requirement: Device Posture Assessment
The system SHALL assess device security posture.

#### Scenario: Posture Checks
- **WHEN** device connects
- **THEN** security posture SHALL be evaluated

#### Scenario: Conditional Access
- **WHEN** device fails posture check
- **THEN** access SHALL be restricted

### Requirement: Captive Portal
The system SHALL provide captive portal for guest access.

#### Scenario: Portal Configuration
- **WHEN** captive portal is enabled
- **THEN** unauthenticated users SHALL be redirected to portal

#### Scenario: Authentication Flow
- **WHEN** user authenticates via portal
- **THEN** network access SHALL be granted