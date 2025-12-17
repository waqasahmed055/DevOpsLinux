#!/usr/bin/expect -f
#
# Fully non-interactive solution using EXPECT
#

set timeout 30
log_user 1

# ================= VARIABLES =================
set ADMIN_USER "server-a"
set ADMIN_PASS "AdminUserPasswordHere"

set ANSIBLE_USER "ansible"
set NEW_PASS "abc@123"

set SERVERS {
  10.50.54.9
  10.50.54.10
}
# =============================================

proc change_and_verify {server} {
  global ADMIN_USER ADMIN_PASS ANSIBLE_USER NEW_PASS

  puts "\nProcessing $server"

  # ---- SSH LOGIN ----
  spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $ADMIN_USER@$server

  expect {
    "(yes/no)" {
      send "yes\r"
      exp_continue
    }
    "*assword:" {
      send "$ADMIN_PASS\r"
    }
    timeout {
      puts "ERROR: SSH timeout on $server"
      return 1
    }
  }

  # ---- SUDO + PASSWORD CHANGE ----
  expect {
    "$ " {}
    "# " {}
  }

  send "sudo passwd $ANSIBLE_USER\r"

  expect {
    "*assword*" {
      send "$ADMIN_PASS\r"
    }
  }

  expect {
    "New password:" {
      send "$NEW_PASS\r"
    }
  }

  expect {
    "Retype new password:" {
      send "$NEW_PASS\r"
    }
  }

  expect {
    "*successfully*" {}
    timeout {
      puts "ERROR: passwd failed on $server"
      return 1
    }
  }

  # ---- EXIT ADMIN SESSION ----
  send "exit\r"
  expect eof

  # ---- VERIFY ANSIBLE LOGIN ----
  spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $ANSIBLE_USER@$server

  expect {
    "(yes/no)" {
      send "yes\r"
      exp_continue
    }
    "*assword:" {
      send "$NEW_PASS\r"
    }
    timeout {
      puts "ERROR: SSH verify timeout on $server"
      return 1
    }
  }

  expect {
    "$ " {
      puts "SUCCESS: $server"
      send "exit\r"
      return 0
    }
    timeout {
      puts "ERROR: SSH verify failed on $server"
      return 1
    }
  }
}

# ================= MAIN =================
foreach server $SERVERS {
  if {[change_and_verify $server] != 0} {
    puts "FAILED: $server"
  }
}
