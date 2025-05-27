# 📄 Postfix Configuration for SMTP Relay Authentication

This guide outlines how to configure **Postfix** to relay email through an SMTP server with authentication. This is particularly useful for migrating syslog email notifications or outbound mail to an authenticated relay server.

---

## 🔧 Step 1: Create the Relay Authentication File

Open or create the file `/etc/postfix/relayhost-auth`:

```bash
sudo vi /etc/postfix/relayhost-auth
```

Add the following content (replace placeholders):

```
[smtp1.dcs.uncw.edu]    username:password
```

* `smtp1.dcs.uncw.edu`: The SMTP relay server hostname.
* `username:password`: The credentials of the service account used to authenticate.

---

## 🔐 Step 2: Generate the Corresponding Hash File

Postfix requires a `.db` file created from the plain-text file:

```bash
sudo postmap /etc/postfix/relayhost-auth
```

This creates the `/etc/postfix/relayhost-auth.db` file. You **must regenerate** this file every time you edit `relayhost-auth`.

---

## 🔒 Step 3: Secure the Authentication Files

Restrict file access so only root can read them:

```bash
sudo chmod 600 /etc/postfix/relayhost-auth /etc/postfix/relayhost-auth.db
```

---

## ⚙️ Step 4: Configure Postfix to Use the Relay Host

Edit the Postfix configuration file:

```bash
sudo vi /etc/postfix/main.cf
```

Add or update the following lines:

```ini
relayhost = [smtp1.dcs.uncw.edu]
smtp_tls_security_level = encrypt
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/relayhost-auth
smtp_sasl_security_options = noanonymous
```

---

## 🔄 Step 5: Restart Postfix

To apply the configuration changes, restart the Postfix service:

```bash
sudo systemctl restart postfix
```

---

## 🧪 Step 6: Verify Postfix is Working

### Check logs for any issues:

```bash
sudo tail -f /var/log/mail.log
```

Look for successful delivery logs or authentication issues.

### Send a test email:

Install mail utilities if not already present:

```bash
sudo apt install mailutils  # Ubuntu/Debian
# or
sudo yum install mailx      # CentOS/RHEL
```

Then send a test:

```bash
echo "This is a test email" | mail -s "Test Subject" your.email@example.com
```

Monitor the logs to ensure the mail is sent via the relay server.

---

## ✅ Notes

* If you change the password or the relay host entry, regenerate the `.db` file:

  ```bash
  sudo postmap /etc/postfix/relayhost-auth
  sudo systemctl restart postfix
  ```
