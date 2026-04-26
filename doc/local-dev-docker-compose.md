
# Local development using docker-compose

To make local development easier, we now provide a container based setup orchestrated using `docker compose`. This setup is for local development only, **do not** use it for a production or even staging environment!

## Prerequisites

You will need:

* docker with `docker compose`

## Overview

* `docker compose up`
* Go to `http://pause.localhost:8080`
  * It might happen that your browser redirects to `https://pause.localhost:8080`, which won't work. If this happens, adjust the protocol in the browser address bar and reload.
* Login with userid `testuser`, password `test`
* Play around with it!
* Read mail sent by PAUSE at `http://localhost:8025`
* `docker compose down`

The setup will persist after `docker compose down`.

## Running

### Start

To start the whole stack, do

`docker compose up`

This should fetch or build the required containers, set up an empty database and start the web app (`pause`) and `paused`.

If you have changed the `Containerfile` or `cpanfile`, rebuild the image first:

`docker compose up --build`

To see less output, list the specific services you want to see, eg

`docker compose up pause paused`

### Access the container(s)

* If the container is already running (started via `up`):
  * `docker compose exec {{container-name}} {{comand}}`
  * eg `docker compose exec pause bash`
* If it is not running:
  * `docker compose run --rm -ti {{container-name}} {{command}}`
  * `docker compose run --rm -ti paused cat /etc/passwd`

To inspect files inside the container, access the container and look around there.

To copy files from the container to the host (eg for more detailed analysis), copy it to `/pause-run/tmp`, which is mounted to `docker-compose/tmp/`:

```
~/perl/pause$ d-c exec pause bash
pause@bb2bd8edaad0:~$ echo "Hello" > /pause-run/tmp/foo
pause@bb2bd8edaad0:~$ exit
~/perl/pause$ ls docker-compose/tmp/
foo
```

### Stop

`docker compose down`

### Resetting

The current setup persists data between restarts. This applies to the DB and to files stored in `/data/pause` and `/pause-run`.

To reset those files (for a complete fresh start), do:

```
docker compose stop
docker compose down
docker volume rm pause_mysql_db    # deletes the database
docker volume rm pause_pause_data  # deletes /data
docker volume rm pause_pause_run   # deletes /pause-run
```

The next `docker compose up` will set up a fresh database and empty directories.

## Services

### pause

The `pause` Plack app (currently `app_2017`) providing the web interface. Runs on port 5000 inside the container. But you should use the `nginx` proxy (see below).

### paused

The PAUSE daemon handling uploads. Logs to `/pause-run/log/paused.log`.

To tail the log from the host, do:

`docker compose exec paused tail -f /pause-run/log/paused.log`

### mysql

The mysql database server. It contains the PAUSE schema, 3 test users, but no further data. Data will persist between restart of the service.

To connect to the database from the host, do:

`docker compose exec mysql mysql -uroot -ptest pause`

To reset the DB, stop all services (`docker compose down`) and delete the volume:

`docker volume rm pause_mysql_db`

### nginx

A nginx frontend proxy. Currently only for serving static files, but could be used in the future to terminate some semi-fake SSL for testing.

### mail

An instance of [mailpit](https://mailpit.axllent.org/). This is a combined SMTP server (listening on port 1025 for incoming email) and webmail (on port 8025). `pause` can send email to `mailpit`, and you can read the mail on `http://localhost:8025`. No mail will actually leave your system!


