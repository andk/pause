# PAUSE: The Perl Author Upload SErver

This repository lives at

    https://github.com/andk/pause

and is considered to contain all relevant programs and configuration
data for running pause.perl.org except for the TLS key and certificate
and files containing passwords or other sensitive data.

Other places with docs:

* [lib/PAUSE.pod](../lib/PAUSE.pod)

## How to set up a private PAUSE server

These instructions describe how to set up a private, or local, PAUSE
server for development and testing.

1. Provision a Debian host, preferably running Debian 12 (Bookworm)
2. Copy the `bootstrap/selfconfig-root` program to that host and run it
3. You're done!

Using Digital Ocean, you can do this all at once with the `bootstrap/mkpause`
program.

For more information on those programs, check out the [Bootstrap
README](../bootstrap/README.md).

## How to set up a new public PAUSE server

There may come a day when you need to build a new PAUSE server that's meant to
become the new official PAUSE.  Good luck!

The bootstrap system, described above, was created to make this easy.  So,
start there, using `bootstrap/selfconfig-root` to build a private PAUSE.  After
doing that, you'll need to carry out the following steps:

1.  Stop the live PAUSE using the `/etc/PAUSE.CLOSED` file and `downtime` system.
2.  Wait for PAUSE to finish indexing recent uploads.
3.  Synchronize the old PAUSE data to the new host using
    `bootstrap/import-pause-data`.  Read the program before running it, as it
    includes instructions on how to use it.
4.  Get and install a TLS certificate for `pause.perl.org`
5.  Export the private GPG key from PAUSE and import it to the new host.

    You need to know the key location, which is the `--homedir` switch in the
    `CHECKSUMS_SIGNING_ARGS` configuration option.  Use `gpg
    --export-secret-key --armor --homedir ...` and pipe it into a file.
    Transfer the file to the new host, in the same location, and use `gpg
    --import -homedir ...` to import it to the keyring.  Delete the file.
6.  [Additional steps for productionization](install-prod.md).
7.  Review the `PrivatePAUSE.pm` file on the old PAUSE host for any settings
    that may have been missed.

## More fun facts

You can fetch the current MySQL dump of the PAUSE `mod` database with from the
rsync location `pause.perl.org::pausedata/moddump.current.bz2`
or from `https://pause.perl.org/pub/PAUSE/PAUSE-data/moddump.current.bz2` --
but that second URL requires PAUSE authentication.

## Other security considerations

We practice security by visibility by giving the users as much information as
possible about the status of their requests. This is mostly done by sending
them mail about every action they take.

Another important axiom is that we disallow overwriting of files except for
pure documentation files. That way the whole CPAN cannot fall out of sync and
inconsistencies can be tracked easily. It opens us the possibility to maintain
a *backpan*, a backup of all relevant files of all times. Any attempt to
upload malicious code can thus be tracked much better.
