# Debian Server Infrastructure Configuration: Networking, Apache, SFTP, Fail2Ban, DNS, DHCP, RAID 5+0, and SSH Security
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)  ![Apache](https://img.shields.io/badge/Apache-D22128?style=for-the-badge&logo=Apache&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=GNU%20Bash&logoColor=white)
![SFTP](https://img.shields.io/badge/SFTP-00599C?style=for-the-badge&logo=openssh&logoColor=white)
![Fail2ban](https://img.shields.io/badge/Fail2ban-FF6C37?style=for-the-badge&logo=shield&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Windows 10](https://img.shields.io/badge/Windows_10-0078D6?style=for-the-badge&logo=windows10&logoColor=white)
![SSH](https://img.shields.io/badge/SSH-000000?style=for-the-badge&logo=openssh&logoColor=white)
![DHCP](https://img.shields.io/badge/DHCP-412991?style=for-the-badge&logo=dhcp&logoColor=white)
![DNS](https://img.shields.io/badge/DNS-1976D2?style=for-the-badge&logo=dns&logoColor=white)

**Project Status:** in progress  | **Role:** Systems Administrator / Network Engineer


## Project Description
This document details the implementation and comprehensive configuration of a Debian Linux-based enterprise server.
The project covers everything from initial network and routing configuration,
to the implementation of critical services (DNS and DHCP), 
high-performance storage management via RAID 5+0 arrays, 
and server security hardening (SSH Hardening and chrooted SFTP environments). 

This repository serves as a technical demonstration of competencies 
in Linux systems administration, 
network services architecture, and the application of security policies.

---

## 1. User and Privilege Management
We create a dedicated administrator user for maintenance, monitoring, automation, and diagnostic tasks, reducing reliance on the `root` user for security reasons.

```bash
# User creation and password assignment
useradd -m -s /bin/bash admin
passwd admin

# Superuser privilege assignment
usermod -aG sudo admin
```

---

## 2. Network Configuration (Migration to Netplan and Systemd-networkd)
We modernized network interface management by migrating from the traditional `ifupdown` to `systemd-networkd` and `Netplan`, standardizing network configuration using YAML for greater scalability.

### Enabling modern services
```bash
# Unmask and enable systemd services for network management and DNS resolution
systemctl unmask systemd-networkd.service
systemctl enable systemd-networkd.service

# Install and configure systemd-resolved
apt install systemd-resolved -y
systemctl enable systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Disable and purge the old network manager
systemctl mask networking
apt purge ifupdown resolvconf && rm -rf /etc/network
```

### Netplan Configuration (`/etc/netplan/10-ifupdown.yaml`)
We define the external interface (`enp1s0`) via DHCP and the isolated internal interface (`enp7s0`) with a static IP for the local network (`192.168.50.1/24`).

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp1s0:
      dhcp4: true
    enp7s0:
      dhcp4: false
      addresses: [192.168.50.1/24]
```
*Apply changes with a reboot or `netplan apply`.*



---

## 4. DNS Server (BIND9)
We implemented a DNS server for local resolution (forward and reverse zones for `debianserver.com`) and to act as a cache for external requests, optimizing network traffic.

```bash
# Dependency installation
apt install bind9 bind9utils bind9-doc dnsutils
```

### Global Configuration (`/etc/bind/named.conf.options`)
```bind
acl "red_aislada" {
    127.0.0.0/8;
    192.168.50.0/24;
};
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { red_aislada; };
    listen-on { 192.168.50.1; 127.0.0.1; };
    forwarders {
        8.8.8.8;
        1.1.1.1;
    };
    forward only;
    dnssec-validation auto;
    listen-on-v6 { any; };
};
```

### Zone Declaration (`/etc/bind/named.conf.local`)
```bind
zone "debianserver.com" IN {
    type master;
    file "/etc/bind/db.debianserver.com";
};
zone "50.168.192.in-addr.arpa" IN {
    type master;
    file "/etc/bind/db.192.168.50";
};
```

### File Configuration `/etc/bind/db.debianserver.com`
```
;
; BIND reverse data file for local loopback interface
;
$TTL	604800
@	IN	SOA	ns1.debianserver.com. admin.debianserver.com. (
			      1		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;
@	IN	NS	ns1.debianserver.com.

ns1 IN	A 192.168.50.1
@	  IN	A 192.168.50.1
www IN	A 192.168.50.1
ftp IN	A 192.168.50.1
```

### File Configuration `/etc/bind/db.192.168.50`
```
;
; BIND reverse data file for local loopback interface
;
$TTL	604800
@	IN	SOA	ns1.debianserver.com. admin.debianserver.com. (
			      1		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;
@	IN	NS	ns1.debianserver.com.

1 IN PTR debianserver.com.
1 IN PTR www.debianserver.com.
1 IN PTR ftp.debianserver.com.

```


```bash
# Restart and verify the service
systemctl restart bind9
systemctl status bind9.service
```

---

## 5. DHCP Server (ISC-DHCP-Server)
We automated the assignment of IP addresses, gateway, and DNS to the client machines connected to the internal interface (`enp7s0`).

```bash
apt install isc-dhcp-server
```

### Main Configuration (`/etc/dhcp/dhcpd.conf`)
```dhcp
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.50.0 netmask 255.255.255.0 {
    range 192.168.50.20 192.168.50.100;
    option routers 192.168.50.1;
    option domain-name-servers 192.168.50.1;
}
```
### Define the listening interface in `/etc/default/isc-dhcp-server`
```
INTERFACESv4="enp7s0"
```

```bash
# Restart service
systemctl restart isc-dhcp-server.service
```

---

## 6. High-Performance Storage (RAID 5+0)
We created a robust logical volume using the `mdadm` utility to combine the advantages of parity (RAID 5 fault tolerance) and data striping (RAID 0 performance).

```bash
# mdadm installation
apt install mdadm

# 1. Creation of two base RAID 5 arrays (3 disks each)
mdadm --create --verbose /dev/md1 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd
mdadm --create --verbose /dev/md2 --level=5 --raid-devices=3 /dev/vde /dev/vdf /dev/vdg

# 2. RAID 0 Creation (Joining the two previous RAID 5 arrays)
mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 /dev/md1 /dev/md2

# 3. Formatting and Mounting
mkfs.ext4 /dev/md0
mkdir -p /mnt/raid50
mount /dev/md0 /mnt/raid50/

# 4. Persistence in /etc/fstab (Using the UUID obtained with blkid)
# UUID=88c15ba7-4b3d-49e1-aa46-b6fbaedfdc0f /mnt/raid50 ext4 defaults,nofail 0 0
```

---

## 7. Chrooted Environment for File Transfer (SFTP Chroot)
We created a secure shared file storage space by restricting user access using `chroot`, preventing them from browsing the main file system or starting terminal sessions.

```bash
# 1. Create user without shell access (/bin/false)
adduser --shell /bin/false ftpuser

# 2. Create the directory structure for the 'jail'
mkdir -p /mnt/raid50/compartido
chown root:root /mnt/raid50/compartido
chmod 755 /mnt/raid50/compartido/

# 3. Create internal directory with write permissions for the user
mkdir -p /mnt/raid50/compartido/archivos
chown ftpuser:ftpuser /mnt/raid50/compartido/archivos/
chmod 755 /mnt/raid50/compartido/archivos/

# 4. Manually authorize SSH key for the SFTP user
# Since the user has /bin/false, ssh-copy-id cannot be used. 
# THE PUBLIC KEY (CREATED ON THE CLIENT MACHINE) MUST BE PASTED MANUALLY

# 5. Create the hidden ssh directory in the user's home
mkdir -p /home/ftpuser/.ssh

# 6. We create the authorized keys file
touch /home/ftpuser/.ssh/authorized_keys

# 7. here you must open the file with nano and paste the client's public key
nano /home/ftpuser/.ssh/authorized_keys

# 8. We assign strict permissions required by the SSH service
chown -R ftpuser:ftpuser /home/ftpuser/.ssh
chmod 700 /home/ftpuser/.ssh
chmod 600 /home/ftpuser/.ssh/authorized_keys
```

### Configuration in `/etc/ssh/sshd_config`
```sshd-config
Match User ftpuser
    ForceCommand internal-sftp
    ChrootDirectory /mnt/raid50/compartido
    AllowTCPForwarding no
    AllowAgentForwarding no
    X11Forwarding no
```

---

## 8. Security Hardening (SSH Hardening)
We increased the security of remote access to the server using cryptography-based authentication (ED25519), mitigating brute force attacks.

```bash
# 1. Generation of high-security cryptographic key pair
ssh-keygen -t ed25519 -C "admin_keys"

# 2. Export the public key to the remote server
ssh-copy-id admin@192.168.122.104

> NOTE: The ssh-copy-id command only works for users with terminal access. 
> For users with /bin/false (like ftpuser), the key must be copied 
> manually to /home/user/.ssh/authorized_keys.

# 3. After configuring the public key, we create a backup copy
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# 4. After each change, we test the configuration
sshd -t

# 5. If the command shows no output, the configuration is valid. Then we restart the SSH service

systemctl restart ssh
systemctl restart sshd

```

### We edit the file `/etc/ssh/sshd_config/`

Key-based authentication is more secure compared to password authentication
```sshd-config
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

Disabled root user access
```sshd-config
PermitRootLogin no
```
(OPTIONAL) We allow root access only via SSH key
```sshd-config
PermitRootLogin prohibit-password
```
We change the default port
```sshd-config
Port 2222
```
We allow access only to the admin and ftpuser users
```sshd-config
AllowUsers admin ftpuser
```
(OPTIONAL) We allow access only by groups Ex: sshusers

***IMPORTANT: create the group and the users in it. Otherwise, there will be no access.***
```sshd-config
 AllowGroups sshusers
```
We disable empty passwords
```sshd-config
PermitEmptyPasswords no
```
We define a 30-second wait for the user to authenticate
```sshd-config
LoginGraceTime 30
```
We limit authentication attempts
```sshd-config
MaxAuthTries 3
```
We disable X11Forwarding
```sshd-config
X11Forwarding no
```
We disable the use of agents for remote servers
```sshd-config
AllowAgentForwarding no
```
We disable the use of SSH tunnels
```sshd-config
AllowTcpForwarding no
```


We allow a maximum time of 10 minutes for inactive sessions
```sshd-config
ClientAliveInterval 300
ClientAliveCountMax 2
```

We create a banner and add a message to it
```bash
>/etc/ssh/banner
echo "Authorized access only. All activity is monitored and logged." >> /etc/ssh/banner
```

We enable the banner in `/etc/ssh/sshd_config`
```sshd
Banner /etc/ssh/banner
```


### Verification
We execute the `sshd -t` command to check for syntax errors
```bash
sshd -t 
```
If the output shows no text, the configuration is fine.



___
## 9. Apache
We install and enable a web server. Which will provide information to the end user.

We install the service 
```bash
apt install apache2 -y
```
We check if it is active 
```bash
systemctl status apache2 --no-pager
```

---
## 10. Fail2Ban
We add an extra layer of security to SSH and Apache, with fail2ban various attacks will not make much sense.

### SSH

```bash
# We install the package
apt install fail2ban

# We create the sshd.local file
>/etc/fail2ban/jail.d/sshd.local

```

### We add the following lines to the file `/etc/fail2ban/jail.d/sshd.local`

```
[sshd]
enabled = true
filter = sshd
maxretry = 3
bantime = 3600
findtime = 600
port = 2222
```

### Apache


```bash
# The fail2ban documentation recommends making all changes in the jail.local file

>/etc/fail2ban/jail.local
```

### We add the following rules in `/etc/fail2ban/jail.local`
```
# Blocks attempts to guess passwords (if you use basic authentication in Apache)
[apache-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 3

# Blocks bots known for seeking vulnerabilities or spamming
[apache-badbots]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
bantime  = 48h
maxretry = 1

# Blocks IPs looking for malicious scripts (e.g. .php that do not exist)
[apache-noscript]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 3

# Blocks buffer overflow attempts (complex attacks)
[apache-overflows]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

# Blocks those looking for hidden /home directories
[apache-nohome]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2
```

### We start and enable the service

```bash
systemctl enable fail2ban && systemctl start fail2ban
```


### To check the status 
```bash
fail2ban-client status
```


___
## 11. UFW 
With UFW we will enable the ports only for the necessary services. In addition to that, we will activate the routing rules between networks and at the kernel level.
```bash
# we install the package
apt install ufw -y
```

### We assign the following NAT rule in `/etc/ufw/before.rules`
```
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o enp1s0 -j MASQUERADE
COMMIT
```

### We allow local services

```bash
# SSH
ufw allow 2222/tcp

# Allow DNS and DHCP only from the internal network interface (LAN - enp7s0)
# This prevents exposing your services to the WAN (enp1s0)

ufw allow in on enp7s0 to any port 53
ufw allow in on enp7s0 to any port 67 proto udp

# Apache2
ufw allow in on enp7s0 to any app 'Apache Full'
```

### We enable routing between the network cards

```bash
# Allow traffic from the LAN to the WAN
ufw route allow in on enp7s0 out on enp1s0
```
### We enable kernel-level routing in the `/etc/ufw/sysctl.conf` file by uncommenting the following line

```
net/ipv4/ip_forward=1
```


### We disable and stop netfilter-persistent
```bash
systemctl disable netfilter-persistent
systemctl stop netfilter-persistent

```
### We reload the firewall
```bash
ufw disable
ufw enable
```


### We reload fail2ban
```bash
systemctl restart fail2ban
```

___

## Testing and trials
The implementation was validated using two client machines: Windows 10 and Ubuntu 25.10 within the same virtual network. Successful test cases included:
1. Routing between two network interfaces 
2. Dynamic IP assignment and DNS suffix assignment via DHCP
3. NAT masquerading, where requests coming from isolated network clients are translated and sent to the internet through the server 
4. Successful DNS via tests with the `ping` and `nslookup` commands
5. Secure remote access via "SSH hardening"
6. Secure file transfer via SFTP to the RAID 50 array
7. Correct display of the internal web page hosted on Apache.

___

## Repository Notes
*The screenshots showing:*
*  *DNS Resolution*
*  *SFTP Access*
*  *SSH Access*
*  *IP Assignment via DHCP*
*  *Apache2 web server*
*  *File upload to the RAID 50 array*

*Have been archived in the `docs/client.pdf` directory.*

*Similarly, the SFTP and SSH configuration can be found in `docs/SFTP.pdf` and `docs/SSH.pdf`*

*The configuration files for SSH, DHCP, DNS, Fail2Ban, Netplan are located in the `configs/` directory*
