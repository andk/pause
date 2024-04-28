# A Quick Tour of PAUSE's Setup

PAUSE is not incredibly complicated, but there's more to it than one daemon
process running.  This document gives some details on how it works from a high
level.

For details on how things work at a low level, you're best off looking at the
"bootstrap" installer described in [How to install PAUSE](installing-pause.md),
or at the source code.  This document might help you figure out *which* source
code to read, though.

## The Web

PAUSE's web interface is a [Mojolicious](https://mojolicious.org/) application,
known in the repository as `pause_2017`.  It runs with `plackup`.  nginx sits
between `pause_2017` and the world, mostly to provide TLS.

## The PAUSE Daemon

`paused` is the PAUSE daemon.  It runs as a systemd service.  It runs a loop,
polling the `mod.uris` table for new rows.  Rows in that table represent files
that users have asked to add to PAUSE.  Each row has a URI pointing to the file
either over HTTP or on the local filesystem, for files uploaded to PAUSE.

Once retrieved or copied into the directory (in the `authors` directory
hierarchy), the file will be indexed immediately.  That's done by running the
indexer (described in this document) with the `--pick` option, which indexes a
single file.

## The Indexer

The PAUSE index is a collection of files describing what distribution file in
the CPAN should be installed to get the offically-recognized version of a
package.  The most important index is `modules/02packages.details.txt`, which
is used by CPAN clients performing module installation.

The PAUSE *index* analyzes distribution files in user directories and may
update the index based on the file contents.  It does this by extracting the
archive, scanning its META files and Perl module files, and comparing the
packages found to the module permissions described in the `primeur` and `perms`
tables in the `mod` database.

The indexer is the program `cron/mldistwatch`, and the library
`PAUSE::mldistwatch`.  It has tests!  Writing new tests is pretty easy, and
changes to the indexer should include tests.

## The Filesystem

A PAUSE install has a bunch of different directories of note, and it's
important to know what they're for.  In the source, they should always be
referred to by the configuration variable that stores them, not by hardcoded
paths.

Here's an overview of the important file paths, with their current defaults:

* `AUTHEN_BACKUP_DIR`, default `/home/pause/db-backup`
  Backups of the password database are written here, so it shouldn't be
  published!

* `FTPPUB`, default `/data/pause/pub/PAUSE/`
  Despite the name, this is basically the root of public PAUSE data.  Anything
  here should be considered public, because it's all available over rsync.  A
  few other directories, below, are children of this directory, but you'll have
  to keep them that way by hand.  They're not relative by configuration.

* `GITROOT`, default `/data/pause/pub/PAUSE/PAUSE-git`
  This is a git repo where each update to the index files is stored and then
  pushed to GitHub.

* `INCOMING_LOC`, default `/data/pause/incoming`
  This is where newly-uploaded files are placed for later retrieval by the
  PAUSE daemon.

* `MLROOT`, default `/data/pause/pub/PAUSE/authors/id/`
  This is the "module list root", but really it's where authors' files go, when
  indexed.  This is the great majority of what we think of as "the CPAN".

* `PID_DIR`, default `/home/pause/pid/"
  This is just a directory for pidfiles for services not run by root.

* `PAUSE_LOG`, default `/home/pause/log/paused.log"
  This is where we write the PAUSE daemon logs, for now.  See the section about
  the logging for more information.

* `TMP`, default `/data/pause/tmp/`,

  A few files are written here by PAUSE while it rebuilds indexes.  It should
  probably be possible to replace with using the standard `/tmp` in time.

* the GnuPG home, default
  `/home/pause/pause-private/gnupg-pause-batch-signing-home` — This isn't stored
  in a configuration of its own, only part of `CHECKSUMS_SIGNING_ARGS` at
  present.

## Logs

PAUSE mostly logs by using the library `PAUSE::Logger`, and over time more of
it should use that.  Logging with PAUSE::Logger will send logs to `journald`
via syslog.

As much as possible, *everything* on PAUSE has been configured to use syslog,
so logs will end up in the journal.  You can use `journalctl` to review logs.

One exception, right now, is `/home/pause/log/paused.log`, where the PAUSE
daemon logs.  It logs there because the web interface can show the contents of
this file.  We'd like to replace it later, to keep a good handle on log growth.
