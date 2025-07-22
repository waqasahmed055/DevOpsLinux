It looks like Apache itself is healthy (you’re getting that 302 locally, your vhost is fine) but now it’s returning **503 Service Unavailable** in the browser—which almost always means Apache tried to hand your PHP over to **php‑fpm** (via mod\_proxy\_fcgi) and the backend wasn’t there or wouldn’t talk. The fact that your error\_log didn’t show an AH01079 right away just means it hasn’t tried (or hasn’t logged yet) once php‑fpm is missing. Let’s walk through the sanity checks:

---

## 1. Make sure php‑fpm is installed & running

```bash
dnf list installed php-fpm php
```

If it’s **not** installed, do:

```bash
dnf install -y php php-fpm
systemctl enable --now php-fpm
```

Then verify:

```bash
systemctl status php-fpm
ss -xlpn | grep php-fpm
```

You should see something like:

```
unix  2      [ ACC ]     STREAM     LISTENING     12345    /run/php-fpm/www.sock
```

---

## 2. Confirm Apache is proxying PHP to the right socket

Open `/etc/httpd/conf.d/php.conf` (or wherever your PHP handler lives) and ensure you have:

```apache
<IfModule proxy_fcgi_module>
  <FilesMatch \.php$>
    SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost/"
  </FilesMatch>
</IfModule>
```

If you don’t, either add it or adjust the socket path to whatever `php-fpm` is actually listening on (check `www.conf`).

---

## 3. Check that mod\_proxy\_fcgi is loaded

Run:

```bash
httpd -M | grep proxy_fcgi
```

If you don’t see `proxy_fcgi_module (shared)`, enable it by installing:

```bash
dnf install -y mod_proxy_fcgi
```

(or ensure the Include of `/etc/httpd/conf.modules.d/00-proxy-fcgi.conf` is present) and then restart Apache:

```bash
systemctl restart httpd
```

---

## 4. Fix socket permissions (if needed)

Make sure Apache can read/write the socket:

```bash
ls -l /run/php-fpm/www.sock
```

If the owner/group isn’t `apache`, edit `/etc/php-fpm.d/www.conf` and set:

```
user = apache
group = apache
listen.owner = apache
listen.group = apache
listen.mode = 0660
```

Then:

```bash
systemctl restart php-fpm
```

---

## 5. Restart & test

```bash
systemctl restart httpd
curl -I http://localhost/index.php
```

You should get a `200 OK` (or the expected redirect), **not** a 503.

---

## 6. Reproduce & inspect the error log

If you still get 503:

1. Trigger it in your browser.
2. Immediately on the server run:

   ```bash
   tail -n 30 /var/log/httpd/error_log
   ```

   Look for lines like `AH01079: failed to make connection to backend`.

Paste those here and we’ll pinpoint the last mile.
