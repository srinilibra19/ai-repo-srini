# Active Story Handoff
Last updated : 2026-03-25
Story        : US-E3-004 — HikariCP connection pool configuration
Status       : COMPLETE
Sprint       : 3

## Acceptance Criteria Status
- [x] spring.datasource.hikari.maximum-pool-size=20
- [x] spring.datasource.hikari.minimum-idle=5
- [x] spring.datasource.hikari.connection-timeout=30000
- [x] spring.datasource.hikari.idle-timeout=600000
- [x] spring.datasource.hikari.max-lifetime=1800000
- [x] spring.datasource.hikari.keepalive-time=300000
- [x] Pool metrics exposed via Spring Boot Actuator and scraped by ADOT
- [x] Connection string uses RDS Proxy endpoint in production (application-aws.yml)

## Sub-task Status
- [x] ST-01: HikariCP pool sizing in application.yml → DONE
- [x] ST-02: Pool metrics config in application.yml → DONE
- [x] ST-03: application-aws.yml with RDS Proxy datasource → DONE

## Files Created / Modified
| File Path | Status | Notes |
|-----------|--------|-------|
| src/main/resources/application.yml | MODIFIED | HikariCP block replaced with AC values + keepalive-time + metrics comment |
| src/main/resources/application-aws.yml | DONE | Created — RDS Proxy JDBC URL, sslmode=require, all env-var refs, Solace prod props |

## Next Story
US-E5-002 — JCSMP FlowReceiver with mTLS configuration
Per Path B: E3-004 → E5-002

## Context to Load on Resume
1. dev-journal/CURRENT.md (already reading)
2. src/main/resources/application-aws.yml — understand Solace prod property names already defined
3. src/main/resources/application.yml — understand base Solace config already in place
CLAUDE.md sections needed: Solace/JCSMP standards, Java/Spring Boot standards, Security standards
