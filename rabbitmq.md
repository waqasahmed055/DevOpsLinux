# RabbitMQ 3.12 Installation & User Management on Oracle Linux 8.10

## 1. Prerequisites

* Oracle Linux 8.10
* `dnf` package manager
* Root or sudo access

Make sure your system is updated:

```bash
sudo dnf update -y
```

## 2. Enable RabbitMQ and Erlang Repositories

RabbitMQ requires Erlang/OTP. For RabbitMQ 3.12, Erlang 25.x is recommended.

```bash
# Enable Erlang repository
sudo dnf install -y https://github.com/rabbitmq/erlang-rpm/releases/download/v25.0/erlang-25.0-1.el8.x86_64.rpm

# Enable RabbitMQ repository
sudo dnf install -y https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.12.0/rabbitmq-server-3.12.0-1.el8.noarch.rpm
```

## 3. Install Erlang and RabbitMQ

```bash
sudo dnf install -y erlang rabbitmq-server
```

Verify version:

```bash
rabbitmqctl version
```

## 4. Start and Enable RabbitMQ Service

```bash
sudo systemctl enable rabbitmq-server --now
sudo systemctl status rabbitmq-server
```

## 5. RabbitMQ Management Plugin (Optional but Recommended)

```bash
sudo rabbitmq-plugins enable rabbitmq_management
```

This exposes the management UI at:

```
http://<server-ip>:15672
```

(Default user: `guest` / password: `guest`, accessible only from localhost by default.)

## 6. Reset or Change RabbitMQ User Password

If you need to reset/change a RabbitMQ user password (e.g., `admin`):

```bash
# Change password for existing user
sudo rabbitmqctl change_password admin NewSecurePassword123!

# Or add a new admin user
sudo rabbitmqctl add_user myadmin MySecurePassw0rd!
sudo rabbitmqctl set_user_tags myadmin administrator
sudo rabbitmqctl set_permissions -p / myadmin ".*" ".*" ".*"
```

## 7. Reset RabbitMQ Database (Clear Queues/Exchanges)

If you want to clear RabbitMQ state completely (⚠️ this deletes all queues, exchanges, bindings):

```bash
sudo systemctl stop rabbitmq-server
sudo rabbitmqctl reset
sudo systemctl start rabbitmq-server
```

---

✅ RabbitMQ 3.12 is now installed and ready on Oracle Linux 8.10.

---
