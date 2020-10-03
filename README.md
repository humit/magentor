# Magento auto-installer

This script runs on an `AWS EC2 ubuntu` instance and it automatically installs and configure an instance of `magento` using `composer` with `MariaDB` database and `nginx` and a `postfix` MTA.

# Installation
1. Copy the script to `/usr/local/bin` and make executable.

`cp magentor.sh /usr/local/bin`
`chmod a+x /usr/local/bin/magentor.sh`

2. Edit `VARIABLES` section to fit your needs (especially `magentoRepoUser` and `magentoRepoPass`)

3. Enable /etc/rc.local on `systemd`
`sudo nano /etc/systemd/system/rc-local.service`

4. Add the following lines:

```
[Unit]
 Description=/etc/rc.local Compatibility
 ConditionPathExists=/etc/rc.local

[Service]
 Type=forking
 ExecStart=/etc/rc.local start
 TimeoutSec=0
 StandardOutput=tty
 RemainAfterExit=yes
 SysVStartPriority=99

[Install]
 WantedBy=multi-user.target
```

5. Make sure /etc/rc.local is executable:

`sudo chmod +x /etc/rc.local`

6. enable rc.local service

`sudo systemctl enable rc-local`

add the following line to rc.local
`/usr/local/bin/magentor.sh`
