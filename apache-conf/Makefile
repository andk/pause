default:
	@echo nothing done

SSLEAY = /usr/local/ssl/bin/openssl

.SUFFIXES: .pkey .pem3 .pem .sslcnf

.sslcnf.pem3:
	[ -f "$*.pkey" ] || ${SSLEAY} genrsa -out $*.pkey 1024
	${SSLEAY} req -config $*.sslcnf -new -key $*.pkey -x509 -nodes -days 2060 -out $@

.pem3.pem:
	cat $*.pkey $< >| $@
	ln -s -f $@ `${SSLEAY} x509 -noout -hash < $@`.0
	${SSLEAY} x509 -noout -text -in $@
	@echo Please take note of the fingerprint and put it into 04pause.html
	${SSLEAY} x509 -noout -fingerprint -in $@


# memo: Fingerprint fuer pause.kbx.de bis 16.May 2009 war
# B4:96:CD:65:5C:B4:2F:2A:EC:D6:5E:5F:FC:D0:8E:0B
