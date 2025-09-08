# Red Hat Subscription Fix

This repository contains steps and scripts to resolve issues with `yum update` and `subscription-manager refresh` on Red Hat Enterprise Linux (RHEL) 9.4, particularly when encountering 404 errors or missing repository configurations.

## Problem
- `yum update` fails due to no enabled repositories.
- `subscription-manager refresh` returns a 404 error.
- Empty or inaccessible `/etc/yum.repos.d/redhat.repo` file.

## Solution
Follow these steps to restore repository access:

1. **Clean local subscription data**:
   ```
   subscription-manager clean
   ```

2. **Register the system**:
   ```
   subscription-manager register --username=<your_redhat_username> --password=<your_redhat_password>
   ```

3. **Attach a subscription**:
   ```
   subscription-manager attach --auto
   ```

4. **Refresh repositories**:
   ```
   subscription-manager refresh
   ```

5. **Verify and update**:
   ```
   subscription-manager repos --list
   yum repolist
   yum update
   ```

## Additional Notes
- Ensure valid Red Hat credentials and an active subscription via the Customer Portal (access.redhat.com).
- Check network connectivity (`curl -v https://subscription.rhsm.redhat.com`) and configure proxy if needed in `/etc/rhsm/rhsm.conf`.
- Verify system clock (`timedatectl`) and update CA certificates (`update-ca-trust`).

## License
[MIT License](LICENSE) (or specify your preferred license)