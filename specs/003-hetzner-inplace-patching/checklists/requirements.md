# Specification Quality Checklist: Patch the Hetzner control plane without interrupting calls

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-03
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

## Notes

- Validated 2026-10-03 on the first pass; no iteration needed.
- Named technologies (deploy-rs, LiveKit, CloudNativePG, GRUB) are deliberately kept out of
  the spec. They belong in `plan.md`. The "Context" section names only the cloud provider and
  points at the design doc and ADR 0021 for the technical background.
- The 5 second freeze tolerance (SC-001), the 10 minute return time (US3, SC-008), the 15
  minute recovery time (US4, SC-006) and the 10 euro cost ceiling (SC-007) are defaults chosen
  from the design doc. Adjust them in `/speckit-clarify` if they are wrong.
- Three unproven points are carried as assumptions, not requirements: in-place patching on
  the current image, the small server's sufficiency, and a call surviving the control-plane
  API being unavailable. The plan must turn each into a rehearsal step.
- FR-012 and the Context link depend on `specs/004-hetzner-encrypted-volumes/`, written next.
- Confirmed by the owner on 2026-10-03: 5 second freeze tolerance (SC-001), stop and ask if the
  small server is too small (FR-011), weekday daytime for call-machine patches, and the
  encryption feature (004) lands first.
- Added 2026-10-03 after planning: a control-plane reboot needs the owner's passphrase (the state
  volume is unlocked at each boot), and a bad version must fall back to the previous one.
- Added 2026-10-03 after the analysis pass: SC-009 (call machine back within 10 minutes of its patch).
  The plan now bootstraps the edge machine before the master is patched, uses a first-patch mode, registers the
  running system as a generation before the first deploy, and unlocks the master through the edge machine or the
  public address, never by its Tailscale name.
