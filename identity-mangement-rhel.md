# Authentication Integration for Red Hat Systems with Microsoft Entra ID

This README provides an overview of two approaches for integrating authentication in Red Hat Enterprise Linux (RHEL) environments with Microsoft Entra ID (formerly Azure Active Directory). The goal is to enable user login using Entra ID credentials, replacing or augmenting an existing old OpenLDAP setup with 389 Directory Server.

The information is based on official Red Hat documentation (e.g., access.redhat.com solutions and guides) and Microsoft Learn resources. Two wiki-style sections detail each approach, followed by a comparison and benefits.

## Wiki 1: Direct Integration with Microsoft Entra ID

### Overview
Direct integration allows RHEL systems to authenticate users against Microsoft Entra ID without an intermediate identity provider like Red Hat IdM. This can be achieved through Microsoft Entra Domain Services (for LDAP/Kerberos compatibility) or emerging direct SSO features.

### Steps (High-Level, Based on Red Hat and Microsoft Docs)
1. **Enable Entra Domain Services (if using LDAP path)**:
   - Provision Microsoft Entra Domain Services in Azure to expose LDAP and Kerberos endpoints.
   - Sync users from Entra ID to Domain Services.

2. **Join RHEL to Entra Domain Services**:
   - Install required packages: `sudo yum install adcli sssd authconfig krb5-workstation`.
   - Configure SSSD (System Security Services Daemon) for LDAP authentication against Entra Domain Services.
   - Use `adcli join` to join the domain: `sudo adcli join -D <domain> -U <admin>`.
   - Update `/etc/sssd/sssd.conf` with LDAP settings and restart SSSD.

3. **Direct SSO (Preview/Alternative Path)**:
   - For RHEL 9+, use Microsoft's SSO for Linux extension (tech preview in RHEL 8.10/9.5).
   - Install the package and register the device with Entra ID for credential-based sign-in.
   - Supports OpenSSH certificate-based authentication: Enable in Azure VM settings and use `az login` or similar for token-based access.

4. **Testing**:
   - Verify with `getent passwd <entra-user>` and attempt SSH login.

**Reference Docs**:
- Red Hat: [Login to RHEL using Microsoft Entra ID](https://access.redhat.com/solutions/7076188).
- Microsoft: [Join RHEL VM to Entra Domain Services](https://learn.microsoft.com/en-us/entra/identity/domain-services/join-rhel-linux-vm); [Microsoft SSO for Linux](https://learn.microsoft.com/en-us/entra/identity/devices/sso-linux).

### Considerations
- Requires Microsoft Entra P1/P2 licenses for advanced features like Conditional Access.
- Best for hybrid Azure environments; may incur costs for Domain Services.

## Wiki 2: Integration Using Red Hat Identity Management (IdM)

### Overview
Red Hat IdM provides a centralized identity solution for Linux domains, including LDAP (based on 389 Directory Server), Kerberos, DNS, and CA. It can integrate with Microsoft Entra ID as an external provider and migrate from existing OpenLDAP/389 setups.

### Steps (High-Level, Based on Red Hat Docs)
1. **Install IdM Server**:
   - On a RHEL 8/9 system: `sudo yum install ipa-server`.
   - Run `ipa-server-install` to set up the domain, including DNS and CA.

2. **Migrate from OpenLDAP/389 Directory Server**:
   - Export data from OpenLDAP/389 as LDIF.
   - Use `ipa migrate-ds` to import: `ipa migrate-ds ldap://<old-ldap-server> --bind-dn=<bind-dn> --base-dn=<base-dn>`.
   - Migrate users, groups, and POSIX attributes; handle passwords separately (e.g., force resets or use migration mode).
   - Enroll existing clients: Update to use SSSD with IdM.

3. **Integrate with Entra ID**:
   - Configure Entra as an external identity provider: Use IdM's web UI or CLI to set up OIDC/SAML federation.
   - Establish trust: `ipa idp-add entra --provider=ms-entra --client-id=<app-id> --client-secret=<secret>`.
   - Enable external auth in SSSD for pass-through to Entra.

4. **Client Enrollment**:
   - On RHEL clients: `ipa-client-install --domain=<idm-domain> --server=<idm-server>`.
   - Users log in with Entra credentials via IdM proxy.

**Reference Docs**:
- Red Hat: [Migrating from LDAP to IdM](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/migrating_to_identity_management_on_rhel_8/migrating-from-an-ldap-directory-to-idm_migrating-to-idm-from-external-sources); [Introduction to IdM](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/linux_domain_identity_authentication_and_policy_guide/introduction); [Using External Providers with IdM](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_external_red_hat_utilities_with_identity_management/assembly_using-external-identity-providers-to-authenticate-to-idm_using-external-red-hat-utilities-with-idm).

### Considerations
- IdM is included with RHEL subscriptions; no extra licensing.
- Supports migration from old OpenLDAP/389, preserving data.

## Comparison

| Aspect                  | Direct Entra Integration                          | Red Hat IdM Integration                           |
|-------------------------|--------------------------------------------------|--------------------------------------------------|
| **Setup Complexity**   | Medium (requires Azure config, packages like SSSD/adcli) | Higher (install IdM server, migration scripting) |
| **Identity Store**     | Entra ID (cloud-native)                          | IdM (on-premises/hybrid, uses 389 DS LDAP)      |
| **Migration from OpenLDAP/389** | Manual export/import or via Domain Services     | Built-in `ipa migrate-ds` tool                   |
| **Authentication Protocols** | LDAP/Kerberos via Domain Services; OIDC/SSO direct | Kerberos, LDAP; federates to Entra via OIDC/SAML |
| **Management**         | Azure portal for users; SSSD on clients          | IdM CLI/UI for Linux policies; Entra for users   |
| **Cost**               | Entra licenses + Domain Services (~$0.10/hour)  | Included in RHEL; no additional Microsoft costs  |
| **Scalability**        | Cloud-scale with Azure                           | Replica servers for high availability           |
| **Linux-Specific Features** | Basic POSIX support                              | Advanced (sudo rules, HBAC, automount)          |

## Benefits of Each Approach

### Benefits of Direct Entra Integration
- **Seamless Microsoft Ecosystem**: Leverages existing Entra ID for single sign-on across Microsoft 365, Azure VMs, and RHEL systems. Supports device registration and Intune management.
- **Simplified Cloud Focus**: No need for on-premises identity servers; ideal for Azure-heavy environments. Enables Conditional Access policies for security.
- **Lower Overhead for Small Setups**: Quick to implement with tools like adcli and SSSD; no additional Red Hat-specific management.
- **Modern Features**: Direct SSO (in preview) allows credential-less login via OpenSSH certificates, reducing password fatigue.

### Benefits of Red Hat IdM Integration
- **Linux-Optimized Management**: Provides centralized control for RHEL-specific features like sudo policies, host-based access control (HBAC), and SELinux mappings—beyond basic LDAP.
- **Easy Migration from Legacy**: Direct support for migrating OpenLDAP/389 data, minimizing disruption from your old setup.
- **Hybrid Flexibility**: Federates with Entra ID while maintaining a Linux domain; supports trusts with Active Directory for mixed environments.
- **Cost-Effective for RHEL Users**: Included in RHEL subscriptions; enhances efficiency with automation, replication, and web-based admin tools. Reduces admin overhead compared to managing raw OpenLDAP/389.
