```markdown
# Oracle OS Management Hub (OSMH) - Policy Advisor Setup Guide

This guide explains how to enable **Oracle OS Management Hub** using the **Policy Advisor** in OCI Console. The advisor automatically creates required user groups, dynamic group, and IAM policies.

---

## Prerequisites

- OCI Tenancy Administrator access or a user with the following **tenancy-level permissions**:
  ```plaintext
  manage dynamic-groups in tenancy
  manage groups in tenancy
  manage policies in tenancy
  ```
- Access to the OCI Console.

---

## Step-by-Step: Running the Policy Advisor

### 1. Select the Correct Identity Domain

1. Open the OCI Console.
2. Click the **navigation menu** (top left) → **Identity & Security** → **Identity** → **Domains**.
3. Select the domain where you want the groups to be created (usually **Default** domain).
4. Note the domain name — you will need it later if using manual policies.

> **Important**: All groups and users must be in the **same Identity Domain**.

### 2. Run Policy Advisor on Root Compartment (Recommended First)

1. Go to **Observability & Management** → **OS Management Hub** → **Overview**.
2. Under **List Scope**, select **root** (tenancy) compartment.
3. Click **Run Policy Advisor**.
4. Review the detected issues → Click **Next**.
5. Review the actions (groups, dynamic group, policy) → Click **Setup**.
6. Confirm the setup.

### 3. Run Policy Advisor on Your VM / Target Compartment

1. Still in **OS Management Hub** → **Overview**.
2. Under **List Scope**, change to your target compartment (where your VMs/instances are located).
3. Click **Run Policy Advisor** again.
4. Follow the same steps: Review → **Next** → **Setup**.

> **Note**: You must repeat this for **every compartment** (and child compartment) that contains instances you want to manage with OS Management Hub. Dynamic groups do **not** support inheritance.

### 4. Add Users to Groups

1. Go to **Identity & Security** → **Identity** → **Domains** → Select the domain used above.
2. Click **Groups**.
3. Open the group **`osmh-admins`**:
   - Add users who should **manage** patching, groups, updates, etc. (e.g., your admin team).
4. Open the group **`osmh-operators`** (optional):
   - Add users who only need **read/view** access to reports and status.

**Recommendation**: Add your own user account to `osmh-admins` first.

---

## What the Policy Advisor Creates

| Resource            | Name                  | Purpose |
|---------------------|-----------------------|--------|
| User Group          | `osmh-admins`         | Full management of OSMH |
| User Group          | `osmh-operators`      | Read-only access |
| Dynamic Group       | `osmh-instances`      | Identifies your instances |
| Policy              | `osmh-policies`       | All required permissions |

---

## Best Practices

- Run Policy Advisor on **Root** first, then on all instance compartments.
- Use the same dynamic group (`osmh-instances`) across compartments.
- After setup, proceed with:
  1. Adding Software Sources (including Extended Support).
  2. Creating Groups and Registration Profiles.
  3. Registering instances.

---

## Troubleshooting

- **Authorization Failed**: Missing tenancy-level manage permissions.
- **Users not visible**: Check that users and groups are in the **same Identity Domain**.
- **Dynamic group missing compartments**: Rerun advisor in that compartment.

---

**Document maintained by:** [Your Name/Team]  
**Last Updated:** `{{ date }}`

For full official documentation, visit: [OS Management Hub Policy Advisor](https://docs.oracle.com/en-us/iaas/osmh/doc/policy-advisor.htm)
```
