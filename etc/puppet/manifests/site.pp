class pause-pkg {
	package { munin        : ensure => installed }
	package { zsh          : ensure => installed }
	package { gnupg        : ensure => installed }
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

class pause {
	include pause-pkg
	include pause-mysqld
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
