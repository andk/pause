# Productionization

This document contains additional instructions/notes for how to turn a
PAUSE installed with the `boostrap` scripts into a production
machine.  Start at [installing-pause](installing-pause.md);

## Adjust TLS Certificates

Bootstrap only sets a single hostname.  You may want certificates for
multiple hostnames.  (i.e. `pause.perl.org` and
`server3.mydomain.com`)

```shell
# certbot --nginx -d server3.mydomain.com,pause.perl.org \
          --agree-tos -n --email pause@pause.perl.org
# systemctl reload nginx
```

## Configure DKIM

Create a DKIM key:

```shell
apt install -y opendkim
opendkim-genkey \
    --directory=/etc/dkimkeys \
    --domain=pause.perl.org \
    --selector=1 \
    --nosubdomains
```

(Best practice is to rotate these keys from time to time.  Do that by
choosing a different selector.)

Add the /etc/dkimkeys/1.txt content to DNS.

Configure postfix:

```shell
postconf smtpd_milters=inet:localhost:8891
postconf non_smtpd_milters=$smtpd_milters
```

Configure `/etc/opendkim.conf`:

```
Domain   pause.perl.org, pause3.develooper.com
Selector 1
KeyFile  /etc/dkimkeys/1.private
Socket   inet:8891@localhost
LogWhy Yes
```

Restart servers:

```shell
service opendkim restart
service postfix reload
```

## Monitoring

Install node exporter.

```shell
apt -y install prometheus-node-exporter
```

Consider
[nginx-prometheus-exporter](https://github.com/nginxinc/nginx-prometheus-exporter).

Actual monitoring rules are not specfied here, because they're
configured on a different server.

Things you may want to monitor and/or alert on:

* disk usage
* traffic levels
* process counts

Add this block to the nginx config to get some basic status: (Also
required for nginx-prometheus-exporter.)

```
server {
  listen 127.0.0.1:8751;
  location = /stub_status {
     stub_status;
  }
  location = / {
     return 404;
  }
}
```

## Additional Configuration

### Fail2ban

Default fail2ban bantime is very short. Make it longer:

```
fail2ban-client start sshd
fail2ban-client set sshd bantime 86400
```

Make sure that fail2ban is reading logs.  Run `fail2ban-client status
sshd`.  If it's not failing any IPs, that's a sign it's not working.
The default backend of `auto` normally works, but may get confused if
`/var/log/auth.log` exists.  If deleting `/var/log/auth.log` doesn't
work, or you want to force it to always read the journal... in
`/etc/fail2ban/jail.conf`:

```
[DEFAULT]
backend = systemd
```

### Package upgrades

Automatic security upgrades are a good idea, and probably outweigh
the risks.

```
dpkg-reconfigure -plow unattended-upgrades
```

