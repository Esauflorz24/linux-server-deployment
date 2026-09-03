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
@	IN	A 192.168.50.1
www IN	A 192.168.50.1
ftp IN	A 192.168.50.1
