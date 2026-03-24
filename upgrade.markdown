# GAWS Server Recovery Runbook

## Overview

During patching of GAWS servers, the system may become unresponsive after the upgrade process. In the affected cases, the servers were recovered by restoring the boot volume from a pre-upgrade backup and then rebuilding the Docker application stack.

This document records the recovery process used to bring the server back to a working state.

## Issue Summary

After patching, the server entered an unresponsive state and could not operate normally. The operating system and application environment required restoration from the previously backed-up boot volume.

## Recovery Approach

The recovery was completed using the following high-level actions:

1. Restored the pre-upgrade boot volume in OCI.
2. Replaced the current boot volume with the restored boot volume.
3. Rebuilt the Docker image from `/opt/docker`.
4. Reran the application setup using the `webrebuild.sh` script.

## Prerequisites

Before performing recovery, ensure the following are available:

* OCI access with permissions to manage boot volumes
* The pre-upgrade boot volume backup
* Access to the affected server
* Root or sudo access on the server
* Docker installed and functional
* The application files present under `/opt/docker`

## Recovery Procedure

### 1. Restore the Boot Volume in OCI

Use the OCI console or CLI to restore the boot volume taken before the upgrade.

* Locate the backup created before patching.
* Restore the boot volume from that backup.
* Verify that the restored volume is available and healthy.

### 2. Replace the Current Boot Volume

After the restored boot volume is available:

* Detach or replace the current boot volume attached to the server.
* Attach the restored boot volume in place of the failed one.
* Confirm the instance is configured to boot from the restored volume.

### 3. Boot the Server and Validate Access

* Start or reboot the server.
* Confirm the server comes online normally.
* Verify SSH or console access.
* Check basic operating system health before proceeding.

### 4. Rebuild the Docker Image

On the recovered server, go to the Docker working directory:

```bash
cd /opt/docker
```

Then rebuild the Docker image according to the environment requirements.

### 5. Run the Application Rebuild Script

After rebuilding the image, run the application setup script:

```bash
./webrebuild.sh
```

This step reinitializes the Docker-based application stack and restores the service to a working state.

## Validation Steps

After recovery, confirm the following:

* The server is responsive
* Docker containers start successfully
* The application is accessible
* No startup errors are present in logs
* The system is stable after reboot

## Outcome

This recovery process successfully resolved the issue. Restoring the pre-upgrade boot volume and rebuilding the Docker application stack returned the server to a healthy and usable state.

## Notes

* Always take a boot volume backup before applying patching changes.
* Validate recovery steps in a non-production environment where possible.
* Keep the rebuild script and Docker configuration version-controlled for future incidents.
