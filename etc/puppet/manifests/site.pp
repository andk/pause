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
}

class pause-mysqld {
        service { mysqld:
                ensure => running,
                enable => true
        }
	file { "/etc/my.cnf":
		path => "/etc/my.cnf",
		ensure => "/home/puppet/pause/etc/my.cnf.centos6-2012",
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
        file { "/var/log/PAUSE-httpd":
                owner => "root",
                group => "root",
                mode => 755,
                ensure => directory,
        }
	file { "/var/run/httpd/deadmeat":
		# abuse of the httpd directory, it rather belongs to
		# the apache we built ourselves
		owner => apache,
		group => apache,
		mode => 755,
		ensure => directory,
	}
	file { "/home/puppet/pause-private":
		owner => puppet,
		group => puppet,
		mode => 755,
		ensure => directory,
	}
	file { "/home/puppet/pause-private/lib":
		owner => puppet,
		group => puppet,
		mode => 755,
		ensure => directory,
	}
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

class pause {
	# file { "/etc/puppet/files":
	# 	path => "/etc/puppet/files",
	# 	ensure => "/home/puppet/pause/etc/puppet/files",
	# }
	include pause-pkg
	include pause-mysqld
	include pause-munin
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
