# Configuración de Infraestructura de Servidor Debian: Redes, Apache, SFTP, Fail2Ban, DNS, DHCP, RAID 5+0 y Seguridad SSH

**Estado del Proyecto:** en proceso  | **Rol:** Administrador de Sistemas / Ingeniero de Redes

## Descripción del Proyecto
Este documento detalla la implementación y configuración 
integral de un servidor 
empresarial basado en Debian Linux.
El proyecto abarca desde la configuración inicial de red y enrutamiento,
hasta la implementación de servicios críticos (DNS y DHCP), 
gestión de almacenamiento de alto rendimiento mediante arreglos RAID 5+0, 
y el fortalecimiento de la seguridad del 
servidor (SSH Hardening y entornos SFTP enjaulados). 

Este repositorio sirve como demostración técnica de competencias 
en administración de sistemas Linux, 
arquitectura de servicios de red y aplicación de políticas de seguridad.

---

## 1. Gestión de Usuarios y Privilegios
Creamos un usuario administrador dedicado para tareas de mantenimiento, monitoreo, automatización y diagnóstico, reduciendo la dependencia del usuario `root` por motivos de seguridad.

```bash
# Creación del usuario y asignación de contraseña
useradd -m -s /bin/bash admin
passwd admin

# Asignación de privilegios de superusuario
usermod -aG sudo admin
```

---

## 2. Configuración de Redes (Migración a Netplan y Systemd-networkd)
Modernizamos la gestión de interfaces de red migrando del tradicional `ifupdown` a `systemd-networkd` y `Netplan`, estandarizando la configuración de red mediante YAML para mayor escalabilidad.

### Habilitación de servicios modernos
```bash
# Desenmascarar y habilitar servicios de systemd para gestión de red y resolución DNS
systemctl unmask systemd-networkd.service
systemctl enable systemd-networkd.service

# Instalar y configurar systemd-resolved
apt install systemd-resolved -y
systemctl enable systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Deshabilitar y purgar el antiguo gestor de red
systemctl mask networking
apt purge ifupdown resolvconf && rm -rf /etc/network
```

### Configuración de Netplan (`/etc/netplan/10-ifupdown.yaml`)
Definimos la interfaz externa (`enp1s0`) por DHCP y la interfaz interna aislada (`enp7s0`) con una IP estática para la red local (`192.168.50.1/24`).

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
*Aplicar cambios con un reinicio o `netplan apply`.*

---

## 3. Enrutamiento y NAT (IP Forwarding & Iptables)
Convertimos el servidor en un enrutador para proporcionar salida a Internet a los clientes de la red aislada, aplicando reglas de traducción de direcciones de red (NAT).

```bash
# 1. Habilitar el reenvío de paquetes IPv4
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ipforwarding.conf
sysctl --system

# 2. Configurar reglas de enrutamiento y NAT con iptables
iptables -t nat -A POSTROUTING -o enp1s0 -j MASQUERADE
iptables -A FORWARD -i enp7s0 -o enp1s0 -j ACCEPT
iptables -A FORWARD -i enp1s0 -o enp7s0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# 3. Hacer las reglas persistentes ante reinicios
netfilter-persistent save
```

---

## 4. Servidor DNS (BIND9)
Implementamos un servidor DNS para resolución local (zonas directas e inversas para `debianserver.com`) y actuar como caché para peticiones externas, optimizando el tráfico de red.

```bash
# Instalación de dependencias
apt install bind9 bind9utils bind9-doc dnsutils
```

### Configuración Global (`/etc/bind/named.conf.options`)
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

### Declaración de Zonas (`/etc/bind/named.conf.local`)
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

*(Se configuran los archivos de zona `db.debianserver.com` y `db.192.168.50` con los registros A, NS y PTR correspondientes).*

```bash
# Reiniciar y verificar el servicio
systemctl restart bind9
systemctl status bind9.service
```

---

## 5. Servidor DHCP (ISC-DHCP-Server)
Automatizamos la asignación de direcciones IP, puerta de enlace y DNS a los equipos clientes conectados a la interfaz interna (`enp7s0`).

```bash
apt install isc-dhcp-server
```

### Configuración Principal (`/etc/dhcp/dhcpd.conf`)
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

```bash
# Definir la interfaz de escucha en /etc/default/isc-dhcp-server
# INTERFACESv4="enp7s0"

# Reiniciar servicio
systemctl restart isc-dhcp-server.service
```

---

## 6. Almacenamiento de Alto Rendimiento (RAID 5+0)
Creamos un volumen lógico robusto utilizando la utilidad `mdadm` para combinar las ventajas de paridad (tolerancia a fallos de RAID 5) y distribución de datos (rendimiento de RAID 0).

```bash
# Instalación de mdadm
apt install mdadm

# 1. Creación de dos grupos RAID 5 base (3 discos cada uno)
mdadm --create --verbose /dev/md1 --level=5 --raid-devices=3 /dev/vdb /dev/vdc /dev/vdd
mdadm --create --verbose /dev/md2 --level=5 --raid-devices=3 /dev/vde /dev/vdf /dev/vdg

# 2. Creación del RAID 0 (Uniendo los dos RAID 5 previos)
mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 /dev/md1 /dev/md2

# 3. Formateo y Montaje
mkfs.ext4 /dev/md0
mkdir -p /mnt/raid50
mount /dev/md0 /mnt/raid50/

# 4. Persistencia en /etc/fstab (Usando el UUID obtenido con blkid)
# UUID=88c15ba7-4b3d-49e1-aa46-b6fbaedfdc0f /mnt/raid50 ext4 defaults,nofail 0 0
```

---

## 7. Entorno Enjaulado para Transferencia de Archivos (SFTP Chroot)
Creamos un espacio seguro de almacenamiento de archivos compartido restringiendo el acceso del usuario mediante `chroot`, evitando que navegue por el sistema de archivos principal o inicie sesiones de terminal.

```bash
# 1. Crear usuario sin acceso a shell (/bin/false)
adduser --shell /bin/false ftpuser

# 2. Crear la estructura de directorios para la 'jaula'
mkdir -p /mnt/raid50/compartido
chown root:root /mnt/raid50/compartido
chmod 755 /mnt/raid50/compartido/

# 3. Crear directorio interno con permisos de escritura para el usuario
mkdir -p /mnt/raid50/compartido/archivos
chown ftpuser:ftpuser /mnt/raid50/compartido/archivos/
chmod 755 /mnt/raid50/compartido/archivos/
```

### Configuración en `/etc/ssh/sshd_config`
```sshd-config
Match User ftpuser
    ForceCommand internal-sftp
    ChrootDirectory /mnt/raid50/compartido
    AllowTCPForwarding no
    AllowAgentForwarding no
    X11Forwarding no
```

---

## 8. Fortalecimiento de Seguridad (SSH Hardening)
Incrementamos la seguridad del acceso remoto al servidor utilizando autenticación mediante criptografía (ED25519), mitigando ataques de fuerza bruta.

```bash
# 1. Generación de par de llaves criptográficas de alta seguridad
ssh-keygen -t ed25519 -C "admin_keys"

# 2. Exportar la llave pública al servidor remoto
ssh-copy-id admin@192.168.122.104

# 3. Despues de configurar la llave publica, creamos una copia de respaldo
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# 4. Despues de cada cambio, probamos la configuración
sshd -t

# 5. Si el comando no muestra ninguna salida, la configuración es válida. Despues reiniciamos el servicio SSH

systemctl restart ssh
systemctl restart sshd

```


### Editamos el archivo `/etc/ssh/sshd_config/`

La autenticación basada en llaves es mas segura a comparación de la autenticacion por contraseña
```sshd-config
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

Deshabilitados el acceso del usuario root
```sshd-config
PermitRootLogin no
```
(OPCIONAL) Permitirmos el acceso por root solamente por llave SSH
```sshd-config
PermitRootLogin prohibit-password
```
Cambiamos el puerto por defecto
```sshd-config
Port 2222
```
Permitimos el acceso solo al usuario admin
```sshd-config
AllowUsers admin
```
(OPCIONAL) Permitimos el acceso solo por grupos Ej:sshusers

***IMPORTANTE: crear el grupo y los usuarios en el. De lo contrario, no habra acceso.***
```sshd-config
 AllowGroups sshusers
```
Desactivamos las contraseñas vacias
```sshd-config
PermitEmptyPasswords no
```
Definimos 30 segundos de espera para que el usuario se autentique
```sshd-config
LoginGraceTime 30
```
Limitamos los intentos de autenticación
```sshd-config
MaxAuthTries 3
```
Desactivamos X11Forwarding
```sshd-config
X11Forwarding no
```
Desactivamos el uso de agentes para servidores remotos
```sshd-config
AllowAgentForwarding no
```
Desactivamos el uso de tuneles SSH
```sshd-config
AllowTcpForwarding no
```


Permitimos un tiempo maximo de 10 minutos para sesiones inactivas
```sshd-config
ClientAliveInterval 300
ClientAliveCountMax 2
```

Creamos un banner y le agregamos un mensaje
```bash
>/etc/ssh/banner
echo "Authorized access only. All activity is monitored and logged." >> /etc/ssh/banner
```

Habilitamos el banner en `/etc/ssh/sshd_config`
```sshd
Banner /etc/ssh/banner
```


### Comprobación
Ejecutamos el comando `sshd -t` para verificar si hay errores de syntaxis
```bash
sshd -t 
```
Si la salida no muestra ningun texto, la configuración esta bien.
