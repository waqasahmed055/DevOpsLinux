# AD Authentication Migration Update

## Summary
We have completed initial testing for direct Active Directory (AD) authentication on Linux systems.

## Completed Work
- Tested **SSSD** integration for Linux servers
- Tested **Winbind** integration for Samba servers
- Validation of authentication flow against Active Directory is complete

## Key Requirement for Migration
To ensure a **smooth migration** from the existing LDAP setup to direct AD authentication:

- POSIX attributes (UIDs/GIDs) must be mapped in Active Directory
- This ensures **consistency of UIDs and GIDs across all Linux servers**

## Impact Analysis
- **Without POSIX mapping:**
  - Possible UID/GID mismatches
  - Risk of access and permission issues
  - Impact on existing file ownership and services

- **With POSIX mapping in AD:**
  - No impact on existing setup
  - Consistent identity management across systems
  - Seamless migration experience

## Current Progress
- POSIX attribute mapping in AD has been tested by Andrew
- Successful validation performed with test users

## Next Steps
- Perform testing with:
  - Multiple users
  - Multiple groups
- Validate:
  - UID/GID consistency
  - Access control behavior
  - No regression in existing workloads

## Reference
- POSIX mapping is being implemented following official documentation https://oneuptime.com/blog/post/2026-03-04-map-ad-users-groups-posix-attributes-rhel/view
