class pause-pkg {
	package { munin        : ensure => installed }
	package { zsh          : ensure => installed }
	package { gnupg2       : ensure => installed }
	package { proftpd      : ensure => installed }
	package { chkrootkit   : ensure => installed }
	package { rkhunter     : ensure => installed }
	package { mon          : ensure => installed }
	package { mysql-server : ensure => installed }
	# we will compile our own dbd-mysql:
	package { mysql-devel  : ensure => installed }
	package { unzip        : ensure => installed }
	package { git          : ensure => installed }
	package { "gcc-c++"    : ensure => installed }
}

class pause-mysqld {
        service { mysqld:
                ensure => running,
                enable => true
        }
        file { "/var/log/mysql":
                owner => "mysql",
                group => "mysql",
                mode => 700,
                ensure => directory,
        }
	file { "/etc/my.cnf":
		path => "/etc/my.cnf",
		ensure => "/home/puppet/pause/etc/my.cnf.centos6-2012",
	}
}

class pause-munin-node {
	package { "munin-node"    : ensure => installed }
	service { "munin-node":
                ensure  => running,
                enable  => true,
                hasstatus => true,
	}
}
class pause-munin {
	package { httpd         : ensure => installed }
        file { "/var/log/munin_httpd":
                owner => "root",
                group => "root",
                mode => 755,
                ensure => directory,
        }
	file { "/etc/munin/httpd_8000.conf":
                owner => "root",
                group => "root",
                mode  => 644,
                source => "puppet:///files/etc/munin/httpd_8000.conf/pause2",
                notify => Service["munin_httpd_8000"],
        }
        service { "munin_httpd_8000":
                ensure  => running,
                enable  => true,
                require => [
                            Package["munin"],
                            File["/etc/init.d/munin_httpd_8000"],
                            File["/etc/munin/httpd_8000.conf"],
                            File["/var/log/munin_httpd"],
                            ],
                hasstatus => true,
	}
	file { "/etc/init.d/munin_httpd_8000":
		owner => root,
		group => root,
		mode => 755,
		source => "puppet:///files/etc/init.d/munin_httpd_8000",
		# require => File["/etc/puppet/files"],
		require => [
			    Package["httpd"],
			    Package["munin"],
			    ],
	}
}

class pause-apache {
        file { "/var/log/PAUSE-httpd":
                ensure => "/opt/apache/current/logs",
        }
	file { "/var/run/httpd/deadmeat":
		# abuse of the httpd directory, it rather belongs to
		# the apache we built ourselves
		owner => apache,
		group => apache,
		mode => 755,
		ensure => directory,
	}
	file { "/usr/local/apache/rundata/pause_1999":
		# abuse of an arbitrary /usr/local place, it rather
		# belonges in something like /var/lib/pause/
		owner => apache,
		group => apache,
		mode => 755,
		ensure => directory,
	}
	file { "/usr/local/apache/rundata":
		owner => apache,
		group => apache,
		mode => 755,
		ensure => directory,
	}
	file { "/usr/local/apache":
		owner => apache,
		group => apache,
		mode => 755,
		ensure => directory,
	}
	file { "/usr/local":
		owner => root,
		group => root,
		mode => 755,
		ensure => directory,
	}
	file { "/etc/init.d/PAUSE-httpd":
		path   => "/etc/init.d/PAUSE-httpd",
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/etc/init.d/PAUSE-httpd-pause-us",
	}
	file { "/opt/apache/current/conf/httpd.conf":
		path => "/opt/apache/current/conf/httpd.conf",
		ensure => "/home/puppet/pause/apache-conf/httpd.conf.pause-us-80",
	}
	service { "PAUSE-httpd":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/init.d/PAUSE-httpd"],
			    File["/opt/apache/current/conf/httpd.conf"],
			    ],
		hasstatus => true,
	}
	file { "/etc/logrotate.d/PAUSE-httpd":
		owner   => root,
		group   => root,
		mode    => 644,
		content => "/var/log/PAUSE-httpd/*log {
# will change to weekly when it works
    daily
    rotate 365
    compress
    delaycompress
    notifempty
    missingok
    sharedscripts
    dateext
    postrotate
        /etc/init.d/PAUSE-httpd reload;
    endscript
}\n",
	}
}

class pause-perlbal {
	file { "/home/puppet/pause-private":
		owner => root,
		group => root,
		mode => 700,
		ensure => directory,
	}
	# file { "/home/puppet/pause-private/lib":
	# 	owner => puppet,
	# 	group => puppet,
	# 	mode => 755,
	# 	ensure => directory,
	# }
	file { "/etc/perlbal":
		owner => root,
		group => root,
		mode => 755,
		ensure => directory,
	}
	file { "/etc/perlbal/servercerts":
		owner => root,
		group => root,
		mode => 700,
		ensure => directory,
	}
	file { "/etc/perlbal/servercerts/rapidssl.pause.perl.org.crt+chain":
		path => "/etc/perlbal/servercerts/rapidssl.pause.perl.org.crt+chain",
		ensure => "/home/puppet/pause/apache-conf/ssl.crt/rapidssl.pause.perl.org.crt+chain",
	}
	file { "/etc/perlbal/perlbal.conf":
		path => "/etc/perlbal/perlbal.conf",
		ensure => "/home/puppet/pause/etc/perlbal/perlbal.conf.pause-us",
	}
	file { "/etc/init.d/PAUSE-perlbal":
		path => "/etc/init.d/PAUSE-perlbal",
		owner => root,
		group => root,
		mode => 755,
		source => "puppet:///files/etc/init.d/PAUSE-perlbal-pause-us",
	}
	service { "PAUSE-perlbal":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/init.d/PAUSE-perlbal"],
			    File["/etc/perlbal/perlbal.conf"],
			    ],
		hasstatus => true,
	}
}

class pause-rsyncd {
	include pause-rsyncd-873
	include pause-rsyncd-8732
}
class pause-rsyncd-873 {
        file { "/etc/rsyncd.conf":
		path => "/etc/rsyncd.conf",
		owner => root,
		group => root,
		mode => 644,
		source => "puppet:///files/etc/rsyncd.conf-pause-us",
	}
	file { "/etc/init.d/PAUSE-rsyncd":
		path => "/etc/init.d/PAUSE-rsyncd",
		owner => root,
		group => root,
		mode => 755,
		source => "puppet:///files/etc/init.d/PAUSE-rsyncd-pause-us",
	}
	service { "PAUSE-rsyncd":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/init.d/PAUSE-rsyncd"],
			    File["/etc/rsyncd.conf"],
			    ],
		hasstatus => true,
	}
	include pause-rsyncd-logrotate
}
class pause-rsyncd-8732 {
        file { "/etc/rsyncd2.conf":
		path => "/etc/rsyncd2.conf",
		owner => root,
		group => root,
		mode => 644,
		source => "puppet:///files/etc/rsyncd2.conf-pause-us",
	}
	file { "/etc/init.d/PAUSE-rsyncd2":
		path => "/etc/init.d/PAUSE-rsyncd2",
		owner => root,
		group => root,
		mode => 755,
		source => "puppet:///files/etc/init.d/PAUSE-rsyncd2-pause-us",
	}
	service { "PAUSE-rsyncd2":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/init.d/PAUSE-rsyncd2"],
			    File["/etc/rsyncd2.conf"],
			    ],
		hasstatus => true,
	}
	include pause-rsyncd-logrotate      
}
class pause-rsyncd-logrotate {
	file { "/etc/logrotate.d/PAUSE-rsyncd":
		owner   => root,
		group   => root,
		mode    => 644,
		content => "/var/log/rsyncd /var/log/rsyncd2 {
# will change to weekly when it works
    weekly
    rotate 365
    compress
    delaycompress
    notifempty
    missingok
    dateext
}\n",
	}
}	
class pause-proftpd {
	# what we did manually: we made /var/ftp a symlink to
	# /home/ftp . Since centos6 makes /var/ftp the home directory
	# of the user ftp and we did not want to question this but we
	# did not have a tradition of putting the whole CPAN into the
	# var partition, this seemed like the lowest impact manual
	# tweak. --akoenig 2012-12-30
	file { "/home/ftp/incoming":
		owner => "ftp",
		group => "ftp",
		mode => 1777, # both ftp and apache write here
		ensure => directory,
	}
	file { "/home/ftp/pub":
		owner => "root",
		group => "ftp",
		mode => 755,
		ensure => directory,
	}
	file { "/home/ftp/run":
		owner => "ftp",
		group => "ftp",
		mode => 755,
		ensure => directory,
	}
	file { "/home/ftp/tmp":
		owner => "ftp",
		group => "ftp",
		mode => 755,
		ensure => directory,
	}
	file { "/etc/proftpd.conf":
		path => "/etc/proftpd.conf",
		owner => root,
		group => root,
		mode => 640,
		source => "puppet:///files/etc/proftpd.conf-pause-us",
	}
	file { "/etc/sysconfig/proftpd":
		owner => root,
		group => root,
		mode => 644,
		source => "puppet:///files/etc/sysconfig/proftpd-pause-us",
	}
	service { "proftpd":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/sysconfig/proftpd"],
			    File["/etc/proftpd.conf"],
			    ],
		hasstatus => true,		
	}
}
class pause-postfix {
	file { "/etc/aliases":
		owner => "root",
		group => "root",
		mode => 644,
		source => "puppet:///files/etc/aliases-pause-us",
	}
	file { "/etc/postfix/main.cf":
		owner => "root",
		group => "root",
		mode => 644,
		source => "puppet:///files/etc/postfix/main.cf-pause-us",
	}
        exec { subscribe-aliases:
                command => "/usr/bin/newaliases",
                logoutput => true,
                refreshonly => true,
                subscribe => File["/etc/aliases"]
        }
        exec { subscribe-postfix:
                command => "/etc/init.d/postfix reload",
                logoutput => true,
                refreshonly => true,
                subscribe => File["/etc/postfix/main.cf"]
        }
        service { "postfix":
		ensure => running,
		enable => true,
		hasstatus => true,		
	}
}
class pause-paused {
	file { "/etc/init.d/PAUSE-paused":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/etc/init.d/PAUSE-paused-pause-us",
	}
	file { "/etc/logrotate.d/mldistwatch":
		owner   => root,
		group   => root,
		mode    => 644,
		content => "/var/log/mldistwatch*log {
    daily
    rotate 365
    compress
    delaycompress
    notifempty
    missingok
    sharedscripts
    dateext
}\n",
	}
}
class pause-limits {
	file { "/etc/security/limits.conf":
		owner  => root,
		group  => root,
		mode   => 644,
		source => "puppet:///files/etc/security/limits.conf-pause-us",
	}
}
class pause-iptables {
	file { "/etc/sysconfig/iptables-config":
		owner  => root,
		group  => root,
		mode   => 644,
		source => "puppet:///files/etc/sysconfig/iptables-config-pause-us",
	}
	file { "/etc/sysconfig/iptables":
		owner  => root,
		group  => root,
		mode   => 644,
		source => "puppet:///files/etc/sysconfig/iptables-pause-us",
	}
}
class pause-mon {
	file { "/usr/lib64/mon/mon.d/freespace.monitor":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/usr/lib64/mon/mon.d/freespace.monitor",
	}
	file { "/usr/lib64/mon/mon.d/paused.monitor":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/usr/lib64/mon/mon.d/paused.monitor",
	}
	file { "/usr/lib64/mon/mon.d/rsyncd.monitor":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/usr/lib64/mon/mon.d/rsyncd.monitor",
	}
	file { "/usr/lib64/mon/mon.d/rsyncd2.monitor":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/usr/lib64/mon/mon.d/rsyncd2.monitor",
	}
	file { "/usr/lib64/mon/mon.d/rersyncrecent.monitor":
		owner  => root,
		group  => root,
		mode   => 755,
		source => "puppet:///files/usr/lib64/mon/mon.d/rersyncrecent.monitor",
	}
	file { "/etc/mon/mon.cf":
		owner  => root,
		group  => root,
		mode   => 644,
		source => "puppet:///files/etc/mon/mon.cf",
	}
	service { "mon":
		ensure => running,
                enable  => true,
                require => [
                            File["/etc/mon/mon.cf"],
			    ],
		hasstatus => true,		
	}
}
class pause {
	# file { "/etc/puppet/files":
	# 	path => "/etc/puppet/files",
	# 	ensure => "/home/puppet/pause/etc/puppet/files",
	# }
	include pause-pkg
	include pause-mysqld
	include pause-munin
	include pause-munin-node
	include pause-apache
	include pause-perlbal
	include pause-rsyncd
	include pause-proftpd
	include pause-postfix
	include pause-paused
	include pause-limits
	include pause-iptables
	include pause-mon
}

node pause2 {
	include pause
}

# Local Variables:
# mode: puppet
# coding: utf-8
# indent-tabs-mode: t
# tab-width: 8
# indent-level: 8
# puppet-indent-level: 8
# End:
