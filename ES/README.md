# Configuración de Infraestructura de Servidor Debian: Redes, Apache, SFTP, Fail2Ban, DNS, DHCP, RAID 5+0 y Seguridad SSH
![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)  ![Apache](https://img.shields.io/badge/Apache-D22128?style=for-the-badge&logo=Apache&logoColor=white) ![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=GNU%20Bash&logoColor=white)
![SFTP](https://img.shields.io/badge/SFTP-00599C?style=for-the-badge&logo=openssh&logoColor=white)
![Fail2ban](https://img.shields.io/badge/Fail2ban-FF6C37?style=for-the-badge&logo=shield&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Windows 10](https://img.shields.io/badge/Windows_10-0078D6?style=for-the-badge&logo=windows10&logoColor=white)
![SSH](https://img.shields.io/badge/SSH-000000?style=for-the-badge&logo=openssh&logoColor=white)
![DHCP](https://img.shields.io/badge/DHCP-412991?style=for-the-badge&logo=dhcp&logoColor=white)
![DNS](https://img.shields.io/badge/DNS-1976D2?style=for-the-badge&logo=dns&logoColor=white)

**Estado del Proyecto:** en proceso  | **Rol:** Administrador de Sistemas / Ingeniero de Redes

***Idiomas***
- 🇪🇸️ Español
- [🇺🇲️ English](https://github.com/Esauflorz24/linux-server-deployment)

## Tabla de Contenidos
- [Descripción del Proyecto](#descripción-del-proyecto)
- [Gestión de Usuarios y Privilegios](#gestión-de-usuarios-y-privilegios)
- [Configuración de Redes](#configuración-de-redes)
- [Servidor DNS (BIND9)](#servidor-dns-bind9)
- [Servidor DHCP (ISC-DHCP-Server)](#servidor-dhcp-isc-dhcp-server)
- [Almacenamiento de Alto Rendimiento (RAID 5+0)](#almacenamiento-de-alto-rendimiento-raid-50)
- [Entorno Enjaulado para Transferencia de Archivos (SFTP Chroot)](#entorno-enjaulado-para-transferencia-de-archivos-sftp-chroot)
- [Fortalecimiento de Seguridad (SSH Hardening)](#fortalecimiento-de-seguridad-ssh-hardening)
- [Apache](#apache)
- [Fail2Ban](#fail2ban)
- [UFW](#ufw)
- [Pruebas y ensayos](#pruebas-y-ensayos)
- [Notas para el repositorio](#notas-para-el-repositorio)


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

## Gestión de Usuarios y Privilegios
Creamos un usuario administrador dedicado para tareas de mantenimiento, monitoreo, automatización y diagnóstico, reduciendo la dependencia del usuario `root` por motivos de seguridad.

```bash
# Creación del usuario y asignación de contraseña
useradd -m -s /bin/bash admin
passwd admin

# Asignación de privilegios de superusuario
usermod -aG sudo admin
```

---

## Configuración de Redes 
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

## Servidor DNS (BIND9)
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

### Configuración archivo `/etc/bind/db.debianserver.com`
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

### Configuración archivo `/etc/bind/db.192.168.50`
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
# Reiniciar y verificar el servicio
systemctl restart bind9
systemctl status bind9.service
```

---

## Servidor DHCP (ISC-DHCP-Server)
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
###  Definir la interfaz de escucha en `/etc/default/isc-dhcp-server`
```
INTERFACESv4="enp7s0"
```

```bash
# Reiniciar servicio
systemctl restart isc-dhcp-server.service
```

---

## Almacenamiento de Alto Rendimiento (RAID 5+0)
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

## Entorno Enjaulado para Transferencia de Archivos (SFTP Chroot)
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

# 4. Autorizar llave SSH manualmente para el usuario SFTP
# Como el usuario tiene /bin/false, no se puede usar ssh-copy-id. 
# LA LLAVE PUBLICA (CREADA EN LA MAQUINA CLIENTE) DEBE PEGARSE MANUALMENTE

# 5. Crear el directorio oculto ssh en el home del usuario
mkdir -p /home/ftpuser/.ssh

# 6. Creamos el archivo de las llaves autorizadas
touch /home/ftpuser/.ssh/authorized_keys

# 7. aqui debes abrir el archivo con nano y pegar la llave publica del cliente
nano /home/ftpuser/.ssh/authorized_keys

# 8. Asignamos permisos estrictos requeridos por el servicio SSH
chown -R ftpuser:ftpuser /home/ftpuser/.ssh
chmod 700 /home/ftpuser/.ssh
chmod 600 /home/ftpuser/.ssh/authorized_keys

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

## Fortalecimiento de Seguridad (SSH Hardening)
Incrementamos la seguridad del acceso remoto al servidor utilizando autenticación mediante criptografía (ED25519), mitigando ataques de fuerza bruta.

```bash
# 1. Generación de par de llaves criptográficas de alta seguridad
ssh-keygen -t ed25519 -C "admin_keys"

# 2. Exportar la llave pública al servidor remoto
ssh-copy-id admin@192.168.122.104

> NOTA: El comando ssh-copy-id solo funciona para usuarios con acceso a terminal. 
> Para usuarios con /bin/false (como ftpuser), la llave debe copiarse 
> manualmente en /home/usuario/.ssh/authorized_keys.

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
Permitimos el acceso solo a los usuarios admin y ftpuser
```sshd-config
AllowUsers admin ftpuser
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



___
## Apache
Instalamos y habilitamos un servidor web. El cual, proporcionara información al usuario final.

Instalamos el servicio 
```bash
apt install apache2 -y
```
Verificamos si esta activo 
```bash
systemctl status apache2 --no-pager
```

---
## Fail2Ban
Añadimos una capa extra de seguridad a SSH y apache, con fail2ban diversos ataques no tendrán mucho sentido

### SSH

```bash
# Instalamos el paquete
apt install fail2ban

# Creamos el archivo sshd.local
>/etc/fail2ban/jail.d/sshd.local

```

### Añadimos las siguientes lineas al archivo `/etc/fail2ban/jail.d/sshd.local`

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
# La documentación de fail2ban recomienda hacer todos los cambios en el archivo jail.local

>/etc/fail2ban/jail.local
```

### Agregamos las siguientes reglas en `/etc/fail2ban/jail.local`
```
# Bloquea intentos de adivinar contraseñas (si usas autenticación básica en Apache)
[apache-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 3

# Bloquea bots conocidos por buscar vulnerabilidades o hacer spam
[apache-badbots]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
bantime  = 48h
maxretry = 1

# Bloquea IPs que buscan scripts maliciosos (ej. .php que no existen)
[apache-noscript]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 3

# Bloquea intentos de desbordamiento de búfer (ataques complejos)
[apache-overflows]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

# Bloquea a quienes buscan directorios /home ocultos
[apache-nohome]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2
```

### Iniciamos y habilitamos el servicio

```bash
systemctl enable fail2ban && systemctl start fail2ban
```


### Para verificar el estatus 
```bash
fail2ban-client status
```


___
## UFW 
Con UFW habilitaremos los puertos solamente para los servicios necesarios. Adicional a eso, activaremos las reglas de enrutamiento entre redes y a nivel de kernel.
```bash
# instalamos el paquete
apt install ufw -y
```

### Asignamos la siguiente regla para NAT en `/etc/ufw/before.rules`
```
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o enp1s0 -j MASQUERADE
COMMIT
```

### Permitimos los servicios locales

```bash
# SSH
ufw allow 2222/tcp

# Permitir DNS y DHCP solo desde la interfaz de red interna (LAN - enp7s0)
# Esto evita exponer tus servicios a la WAN (enp1s0)

ufw allow in on enp7s0 to any port 53
ufw allow in on enp7s0 to any port 67 proto udp

# Apache2
ufw allow in on enp7s0 to any app 'Apache Full'
```

### Habilitamos el enrutamiento entre las tarjetas de red

```bash
# Permitir tráfico desde la LAN a la WAN
ufw route allow in on enp7s0 out on enp1s0
```
### Habilitamos el enrutamiento a nivel de kernel en el archivo `/etc/ufw/sysctl.conf` descomentanto la siguiente linea

```
net/ipv4/ip_forward=1
```


### Deshabilitamos y detenemos netfilter-persistent
```bash
systemctl disable netfilter-persistent
systemctl stop netfilter-persistent

```
### Recargamos el firewall
```bash
ufw disable
ufw enable
```


### Recargamos fail2ban
```bash
systemctl restart fail2ban
```

___

## Pruebas y ensayos
La implementación se validó utilizando dos maquinas clientes: Windows 10 y Ubuntu 25.10 dentro de la misma red virtual, Los casos de pruebas exitosos incluyeron
1. Enrutamiento entre dos interfazes de red 
2. Asignación dinámica de IP y asignación de sufijo DNS mediante DHCP
3. Enmascaramiento NAT, donde las solicitudes provenientes de los clientes de la red aislada son traducidas y enviadas hacia internet mediante el servidor 
4. DNS exitoso mediante pruebas con el comando `ping` y `nslookup`
5. Acceso remoto seguro mediante "SSH hardening"
6. Transferencia segura de archivos mediante SFTP al arreglo RAID 50
7. Visualización correcta de la página web interna alojada en Apache.

___

## Notas para el repositorio
*Las capturas de pantalla que muestran:*
*  *Resolución DNS*
*  *Acceso de SFTP*
*  *Acceso SSH*
*  *Asignacion de IPs mediante DHCP*
*  *Servidor web apache2*
*  *Subida de archivos al arreglo RAID 50*

*Se han archivado en el directorio `docs/client.pdf`*

*De igual manera la configuracion de SFTP y SSH se encuentran en `docs/SFTP.pdf` y `docs/SSH.pdf`*

*Los archivos de configuracion de SSH, DHCP, DNS, Fail2Ban, Netplan se encuentran en el directorio `configs/`*

