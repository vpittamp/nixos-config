# Specification Quality Checklist: Fix PWA URL Routing and Link Handling

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2025-12-14
**Revised**: 2025-12-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Revision Notes (2025-12-14)

### Design Philosophy Changes

**Original**: Complex system trying to intercept all links, handle auth specially, prevent loops with lock files

**Revised**: Simplified system focused on core goal - ending up in correct PWA

### Key Architecture Decisions

1. **PWAs handle their own auth** - Configure `allowedDomains` per PWA instead of external auth bypass lists
2. **Explicit routing only** - No automatic URL interception; Firefox remains default
3. **Remove complexity** - Delete link interceptor extension, lock files, auth bypass lists
4. **Add path-based routing** - New capability for same-domain PWAs (Google AI, Gmail, Calendar)

### Components to Remove

| Component | Reason |
|-----------|--------|
| `googleRedirectInterceptorExtension` | Complex, fragile, doesn't work reliably |
| `pwa-install-link-interceptor` script | No longer needed |
| Lock file loop prevention | Over-engineered; env var check sufficient |
| Auth bypass domain lists | PWAs handle auth internally |

### New Fields in pwa-sites.nix

| Field | Purpose |
|-------|---------|
| `routing_paths` | Path prefixes for same-domain differentiation |
| `auth_domains` | Auth providers this PWA needs for `allowedDomains` |

## Validation Summary

- Spec is ready for `/speckit.plan`
- Clear simplification strategy documented
- Legacy removal explicitly specified (FR-015, FR-016, FR-017)
- No backwards compatibility required per user request
