# PAUSE Bootstrap

This directory is a collection of programs to make it easy to stand up a
complete PAUSE instance, either for testing or for preparing a new PAUSE
instance to be used in production.

For testing, the simplest thing might be for you to use `mkpause` which has
roughly this usage.

```
--username STR (or -u)     your username; defaults to $ENV{USER}
--size STR                 slug for Digital Ocean droplet
--box-ident STR (or -i)    identifying part of box name; defaults to --username

--plenv-url STR (or -P)    URL to a tar.bz2 file to use for plenv

--certbot-staging (or -C)  use the staging version of certbot
--enable-mail (or -m)      set up postfix config for outbound mail

--destroy                  destroy the box if it does exist
```

In general, you don't need to provide any options.  If your local computer's
unix account is `hans` then you'll get a box named `hans.unpause.your-domain`,
where `your-domain` is the DigitalOcean domain you've set aside for this work.
That means you need a DigitalOcean account and an API key set in the `DO_TOKEN`
environment variable.

`mkpause` will create a VM and then copy the `selfconfig-root` program to the
VM.  It will run `selfconfig-root` as the root user.  That program will install
a bunch of apt packages, configure the firewall, create non-root users, and
then run the program `selfconfig-pause` as the new `pause` user.  When that's
done, cronjobs and systemd services will be installed and running, and you'll
be able to log into the web interface.

**Admin user**:  The bootstrap program will also create an admin account in
PAUSE for you, with the username and password both set to the value of
`--username`.  This is useful for testing, but if you're preparing a new PAUSE
instance, make sure you delete it.

**certbot**:  By default, certbot will generate a real, trusted certificate for
the new VM.  That's useful to test with your web browser without security
alerts.  The down side is that you can only generate a limited number of Let's
Encrypt certificates before being rate limited.  Pass `--certbot-staging` to
use the staging certbot server.  This is a real certificate, but isn't trusted
by default in common certificate roots, so your browser will complain.  On the
other hand, you can generate quite a lot of them without being rate-limited.

**plenv**:  The bootstrap process will default to building perl from source and
installing all of PAUSE's depenedencies using `cpanm`.  On our usual VM size,
this takes around ten minutes.  It's useful to save a copy of the
`~pause/.plenv` as an archive file so avoid waiting on build and install.  Put
that archive, as a `tar.bz2` file, somewhere on the web, and then provide the
URL to it as the `--plenv-url` option.  As of 2024-04-26, a workable archive
can be found at https://dot-plenv.nyc3.digitaloceanspaces.com/dot-plenv.tar.bz2

