# Duo Authentication Setup Guide (Linux)

This document provides step-by-step instructions to install and configure **Duo Authentication** on a target Linux server using configuration copied from an existing OCI jumpbox.

---

## **1. Install Duo Package**

Follow the official Duo documentation to install the Duo Unix package:

🔗 **[https://duo.com/docs/duounix#install-from-linux-packages](https://duo.com/docs/duounix#install-from-linux-packages)**

---

## **2. Copy Duo Configuration Files**

On the **OCI jumpbox**, copy the contents of:

```
/etc/duo/*
```

Paste these files into the **target server** in the same location:

```
/etc/duo/
```

---

## **3. Copy PAM Configuration Files**

Navigate to the PAM configuration directory:

```bash
cd /etc/pam.d
```

Copy the content of the following files from the **jumpbox** to the **target server**:

* `password-auth`
* `sshd`
* `system-auth`

Ensure that the contents match exactly.

---

## **4. Verify SSH Configuration**

Check the SSH server configuration on the **target server**:

```bash
cat /etc/ssh/sshd_config
```

Ensure the following parameters are present:

```
UsePAM yes
ChallengeResponseAuthentication yes
UseDNS no
```

Update `sshd_config` if required.

---

## **5. Restart SSHD and Test Duo Login**

Restart the SSH daemon:

```bash
sudo systemctl restart sshd
```

Then attempt logging in again to verify Duo authentication is working.

---

## **6. Important Safety Step**

Before making authentication changes, **always open at least two root shells**.
If anything goes wrong, you will still have an active session to fix the issue.

---

If you want, I can also add formatting, warnings, notes, diagrams, or convert this into a full GitHub wiki page.
