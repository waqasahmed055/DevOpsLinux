# GAWS Server Upgrade Runbook

## Overview

This document outlines the standard procedure for upgrading GAWS servers. The process ensures minimal disruption by validating changes in the development environment before proceeding to production.

---

## Upgrade Strategy

1. **Development First**

   * Always perform the upgrade on the **DEV environment first**.
   * Once completed, hand over to **Jackson for testing and validation**.

2. **Production Rollout**

   * Proceed only after confirmation from Jackson.
   * Schedule the production upgrade during **early morning hours** to minimize impact.

---

## Upgrade Steps (Applicable for DEV and PROD)

Follow the steps below for both environments:

### 1. Patch the Server

* Apply the required system patches using standard patching procedures.

### 2. Reboot the Server

* Reboot the server to ensure patches take effect.

### 3. Verify Docker Status

* Check that Docker is running:

  ```bash
  systemctl status docker
  ```
* Ensure no critical errors are present.

### 4. Remove Existing Container

* Identify the running container:

  ```bash
  docker ps
  ```
* Stop and remove the container:

  ```bash
  docker stop <container-id>
  docker rm <container-id>
  ```

### 5. Rebuild Container

* Use the deployment script to rebuild the container:

  ```bash
  ./deploy.sh
  ```

### 6. Validate Container

* Confirm the container is up and running:

  ```bash
  docker ps
  ```

### 7. Perform Connectivity Checks

* Access the container shell:

  ```bash
  docker exec -it <container-id> sh
  ```

* Run DNS resolution test:

  ```bash
  getent hosts google.com
  ```

* Run network connectivity test:

  ```bash
  curl google.com
  ```

* **Expected Result:**

  * Both commands should return valid responses.
  * If successful, it confirms the server patching and networking are functioning correctly.

---

## Validation

* After completing the steps:

  * Notify **Jackson** for testing.
  * Ensure full application validation is completed before moving forward.

---

## Notes

* Do **not** proceed to production without successful DEV validation.
* Ensure rollback procedures are ready before starting production upgrade.
* Monitor logs post-upgrade for any anomalies.


If you want, I can convert this into a Confluence-ready format or add a rollback section as well.
