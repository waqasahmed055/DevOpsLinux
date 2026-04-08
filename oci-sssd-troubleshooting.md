# OCI 9 Troubleshooting Guide

**Fixing PATH Variable Issue After OpenJDK 21 Installation & SSSD Home Directory Creation**

## Overview

This document describes two issues encountered on **Oracle Cloud Infrastructure (OCI) 9 / Oracle Linux 9** systems and the steps taken to resolve them:

1. **OpenJDK Java 21 installation broke the `PATH` environment variable**, causing basic commands to stop working.
2. **SSSD was unable to create user home directories upon login**, preventing proper user session initialization.

These issues were identified during system configuration and resolved using the steps documented below.

---

# Issue 1 — OpenJDK 21 Installation Broke PATH Variable

## Problem

After installing **OpenJDK Java 21** on an **OCI 9** instance:

* Standard Linux commands stopped working.
* Shell sessions failed to locate binaries.
* The `PATH` environment variable was incorrectly overridden.
* The issue was traced to the `/etc/environment` file.

Example symptoms:

```bash
command not found
sudo: command not found
ls: command not found
```

---

## Root Cause

The installation or configuration process modified the `PATH` variable in:

```bash
/etc/environment
```

Instead of appending to the existing `PATH`, it overwrote it with an invalid or incomplete value.

This caused the system to lose access to essential binary directories such as:

```
/usr/bin
/bin
/usr/sbin
/sbin
```

---

## Resolution

### Step 1 — Edit `/etc/environment`

Comment out the incorrect `PATH` definition.

```bash
sudo vi /etc/environment
```

Change:

```bash
PATH=/some/incorrect/path
```

To:

```bash
# PATH=/some/incorrect/path
```

---

### Step 2 — Create Custom PATH Script

Create a custom profile script to correctly define the `PATH`.

```bash
sudo vi /etc/profile.d/custom_path.sh
```

Add:

```bash
#!/bin/bash

export PATH=$PATH:/usr/local/bin:/usr/local/sbin
```

---

### Step 3 — Set Permissions

```bash
sudo chmod +x /etc/profile.d/custom_path.sh
```

---

### Step 4 — Reload Environment

```bash
source /etc/profile
```

Or log out and log back in.

---

## Verification

```bash
echo $PATH
```

Expected output should include:

```bash
/usr/bin
/bin
/usr/sbin
/sbin
/usr/local/bin
/usr/local/sbin
```

Also verify commands:

```bash
which java
which ls
which sudo
```

---

## Best Practice

Never overwrite the `PATH` variable directly in:

```
/etc/environment
```

Instead:

* Use `/etc/profile.d/`
* Append to `PATH`
* Keep system directories intact

Recommended pattern:

```bash
export PATH=$PATH:/new/path
```

---

# Issue 2 — SSSD Unable to Create Home Directory on Login

## Problem

Users authenticated via **SSSD** were able to log in successfully, but their home directories were not created automatically.

Example symptoms:

```text
Could not chdir to home directory /home/username: No such file or directory
```

Users were logged into:

```bash
/
```

instead of:

```bash
/home/<username>
```

---

## Root Cause

The **mkhomedir feature** was not enabled in the system authentication configuration managed by `authselect`.

Without this feature:

* SSSD authenticates users
* But does not create home directories

---

## Resolution

Enable the `with-mkhomedir` feature using `authselect`.

```bash
sudo authselect enable-feature with-mkhomedir --force
```

---

## What This Command Does

It:

* Enables automatic home directory creation
* Updates PAM configuration
* Applies changes immediately

Equivalent behavior to:

```bash
pam_mkhomedir.so
```

---

## Verification

Check enabled features:

```bash
authselect current
```

Expected output:

```text
with-mkhomedir
```

---

Test login:

```bash
ssh username@server
```

Then verify:

```bash
ls /home
```

Expected:

```bash
username
```

---

## Optional Validation

Check PAM configuration:

```bash
cat /etc/pam.d/system-auth | grep mkhomedir
```

Expected:

```bash
session optional pam_mkhomedir.so
```

---

# Summary of Fixes

| Issue                      | Root Cause                           | Fix                                                        |
| -------------------------- | ------------------------------------ | ---------------------------------------------------------- |
| PATH variable broken       | Incorrect PATH in `/etc/environment` | Commented PATH and created `/etc/profile.d/custom_path.sh` |
| Home directory not created | `with-mkhomedir` not enabled         | Enabled feature via `authselect`                           |

---

# Commands Reference

```bash
# Fix PATH issue
sudo vi /etc/environment
sudo vi /etc/profile.d/custom_path.sh
sudo chmod +x /etc/profile.d/custom_path.sh
source /etc/profile

# Fix SSSD home directory issue
sudo authselect enable-feature with-mkhomedir --force

# Verify
echo $PATH
authselect current
```
