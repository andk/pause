FROM perl:5.42-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libdb-dev libexpat1-dev libgetopt-long-descriptive-perl libpath-tiny-perl libsasl2-modules zlib1g-dev unzip tree vim \
    && rm -fr /var/cache/apt/* /var/lib/apt/lists/*

RUN useradd -m --shell /bin/bash pause
WORKDIR /home/pause

COPY cpanfile cpanfile
RUN cpm install -g

COPY docker-compose/setup.sh /setup.sh
RUN /setup.sh

USER pause

COPY --chown=pause docker-compose/PrivatePAUSE.pm privatelib/PrivatePAUSE.pm
COPY --chown=pause t t
COPY --chown=pause doc doc
COPY --chown=pause htdocs htdocs
COPY --chown=pause cron cron
COPY --chown=pause bin bin
COPY --chown=pause lib lib
COPY --chown=pause app_2017.psgi app_2017.psgi
COPY --chown=pause app_2026.psgi app_2026.psgi

CMD ["plackup","app_2026.psgi"]
