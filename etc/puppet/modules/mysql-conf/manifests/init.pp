
class mysql-conf {
	file { "mysql_my_cnf":
		path => "/etc/my.cnf",
		owner => root,
		group => root,
		mode => 644,
		content => template("mysql-conf/my.cnf.erb"),
	}
}

# Local Variables:
# puppet-indent-level: 8
# indent-tabs-mode: t
# End:

# vim:sw=8
