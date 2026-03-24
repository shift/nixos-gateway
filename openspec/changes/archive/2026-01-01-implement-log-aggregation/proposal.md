# Change: Implement Log Aggregation

## Why
The NixOS Gateway Framework currently has fragmented logging with basic local logging only. Without centralized log aggregation, it's impossible to correlate events across services, perform effective troubleshooting, or maintain compliance requirements. This leads to poor observability and makes incident response extremely difficult.

## What Changes
- Implement comprehensive log aggregation with structured JSON logging
- Add centralized log collection using Fluent Bit with Elasticsearch storage
- Create log parsers for all gateway services (DNS, DHCP, IDS, network)
- Build log search and visualization capabilities with Kibana integration
- Integrate log-based monitoring and alerting

## Impact
- Affected specs: New log-aggregation capability, enhanced monitoring
- Affected code: New log aggregation module, Fluent Bit configuration, log parsers
- Timeline: 5 weeks for comprehensive log aggregation implementation and integration