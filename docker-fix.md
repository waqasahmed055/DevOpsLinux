# DNS Resolution Issue in Docker Container – Troubleshooting & Resolution

## Summary

An application deployed in a Docker container encountered a database connectivity error. The issue was traced to DNS resolution failure inside the container environment. The root cause was an incompatible Docker Engine installation (EL7 packages running on an EL8 operating system). Reinstalling Docker with the correct EL8 packages resolved the issue.

---

## Issue Description

The application failed to connect to the database and returned an error indicating that the database host could not be reached. This suggested a possible network or DNS resolution problem within the container.

---

## Troubleshooting Steps

### 1. Validate DNS Resolution Inside the Container

The `getent` command was used to test DNS resolution for both a public domain and the database endpoint.

```bash
getent hosts google.com
getent hosts <database-endpoint>
```

Result:

* No output was returned.
* This indicated that DNS resolution was failing inside the container.

---

### 2. Compare Behavior with Production Environment

The same commands were executed on the production server:

```bash
getent hosts google.com
```

Result:

* DNS resolution worked correctly.
* This confirmed the issue was specific to the development environment.

---

### 3. Verify DNS Resolution on the Host Server

The same DNS tests were executed directly on the development host server (outside the container).

Result:

* DNS resolution worked successfully on the host.
* This confirmed the problem existed **only inside the Docker container**.

---

### 4. Identify Docker Engine Version Mismatch

Further investigation revealed that the Docker Engine installed on the system was from the **EL7 repository**, while the operating system was **EL8**.

This mismatch caused networking and DNS resolution issues inside Docker containers.

---

## Root Cause

Docker Engine and Docker CLI packages installed from the **EL7 repository** were incompatible with the **EL8 operating system**, which resulted in DNS resolution failures inside containers.

---

## Resolution Steps

### 1. Remove Existing Docker Packages

```bash
sudo yum remove docker-engine docker-cli
```

---

### 2. Install Correct Docker Packages for EL8

Install Docker packages compatible with the EL8 operating system.

---

### 3. Rebuild and Deploy the Application Container

After installing the correct Docker version, the container was rebuilt and deployed using the existing setup script.

```bash
./build-and-deploy.sh
```

---

## Verification

After redeploying the container:

* DNS resolution inside the container worked correctly.
* The application successfully connected to the database.
* The application was tested and confirmed to be functioning normally.

---

## Key Takeaways

* Always ensure Docker packages match the underlying OS version.
* When facing connectivity issues inside containers, verify DNS resolution both inside and outside the container.
* Comparing behavior with a working environment can help quickly isolate the root cause.
