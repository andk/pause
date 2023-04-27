FROM debian:bullseye
WORKDIR /home/k/pause
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive DEBCONF_NOWARNINGS=yes \
    apt-get --no-install-recommends -y install \
    build-essential curl perl ssh git gpg gpg-agent openssl unzip ca-certificates \
    libssl-dev zlib1g-dev libexpat1-dev libxml2-dev libmariadb-dev-compat \
    default-mysql-client \
	golang \
    nano && \
    apt-get clean && \
	go get github.com/mailhog/mhsendmail && mv /root/go/bin/mhsendmail /usr/sbin/sendmail && \
    curl -skL --compressed https://git.io/cpm > cpm && \
    chmod +x cpm && mv cpm /usr/local/bin && \
    curl -skL --compressed https://cpanmin.us > cpanm && \
    chmod +x cpanm && mv cpanm /usr/local/bin && \
    cpanm -n IPC::Run && \
    curl -skL https://raw.githubusercontent.com/andk/pause/master/cpanfile > cpanfile && \
#    cpm install -g
    cpanm --installdeps -n .
COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
