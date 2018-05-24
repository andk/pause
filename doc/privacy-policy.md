# PAUSE Privacy Policy

Version 1

This is the privacy policy for PAUSE, the Perl Authors Upload Server.
It describes how PAUSE complies with the
General Data Protection Regulation (GDPR),
and your rights as a user of PAUSE.

This document is organised into the following sections:

* **About PAUSE**: a brief overview of what PAUSE is,
  to provide context for the rest of the document.
* **Information held by PAUSE**: lists the information held by PAUSE,
  and identifies for each item whether PAUSE is a *data controller*
  or *data processor*.
* **Lawful Basis for Processing**: GDPR requires a data controller
  to explicitly define under what rights it processes personal data.
  This section does that for PAUSE.
* **Use of Information**: describes how PAUSE uses the information it holds.
* **Sharing of Information**: describes how the information held by PAUSE
  is shared with the rest of the CPAN ecosystem.
* **Your Rights**: describes what your rights are,
  and how they can be exercised.
* **Contact Us**: tells you how to get in touch with the PAUSE admins.


## About PAUSE

PAUSE is a critical component of the CPAN ecosystem.
The Comprehensive Perl Archive Network,
or [CPAN](https://cpan.org),
is a collection of reusable open source modules for the
[Perl programming language](https://perl.org).
The collection is mirrored on more than 256 servers around the world.
More information about CPAN can be found at [cpan.org](https://cpan.org).

Any Perl developer can add their own code to CPAN,
and this is done via [PAUSE](https://pause.perl.org).
To release things onto CPAN,
a Perl developer must register an account with PAUSE,
and then upload that software onto PAUSE.
More information about PAUSE can be found in the
[About PAUSE](https://pause.perl.org/pause/query?ACTION=pause_04about)
document on PAUSE itself.

PAUSE is a service provided to the Perl community,
and operated by members of that community,
known as the
[PAUSE admins](https://pause.perl.org/pause/query?ACTION=who_admin).
The processes and policies for running PAUSE are documented
in the [PAUSE Operating Model](https://github.com/andk/pause/blob/master/doc/operating-model.md).


## Information collected by PAUSE

This section lists all of the information that PAUSE may collect or generate,
related to user accounts.

The following information is collected when a Perl developer signs up
for a PAUSE account:

* The **PAUSE id** is a CPAN author's username.
  It is constructed from alphanumeric characters,
  and is typically selected by the user when they sign up for a PAUSE account.
  It may or may not relate to the person's name.
  For example, Fred Bloggs may have a PAUSE id of FREDB,
  or may choose something unrelated to his name, such as PERLDUDE.
* The user's **full name**, as they write it.
  This could be in Cyrillic, Kanji, or some other writing system,
  encoded in UTF-8. The name need not be a legal name;
  a user may choose to provide a pseudonym instead.
* **ASCII name**: is an ASCII version of the user's name,
  if they choose to give it.
* A **public email address**.
  This is an email address that the user is happy to share publicly.
* A **secret email address**. This will only be known to PAUSE,
  and will never be shared publicly.
  There are various situations where PAUSE needs to contact authors,
  so to register for an account you must provide either a public or
  private email address (you can provide both).
* An optional URL for the user's **home page**.
* The user's **motivation** for applying for a PAUSE account.
  This is sent to the PAUSE admins, but is not retained
  in the PAUSE database.
* The user's **password** (encrypted).
* PAUSE records a **timestamp** for the creation time of accounts.

For the above information, PAUSE is the data controller.


All PAUSE users have an associated cpan.org email address.
If your PAUSE id were FREDB,
then your CPAN email address would be `fredb@cpan.org`.
You can choose whether this should forward to your public email address,
your secret email address, or not forward at all
(in which case email sent to that address will bounce back to the sender).
This flag is also associated with your account.

When you upload a tarball to PAUSE, it is written to your author directory,
which is mirrored onto all CPAN mirrors.
It will remain in your author directory, and thus on CPAN,
until you delete it via the PAUSE web interface.
There are a small number of circumstances
when a file in your author directory may be remove by the PAUSE admins;
these are documented in the PAUSE Operating Model.
PAUSE records a timestamp for the date and time
when the file was uploaded and a "checksum"
(using various cryptographic digest functions) for each file uploaded.
For files uploaded to PAUSE, the uploading author is the controller,
and PAUSE is a data processor.

If a PAUSE user uploads a new module to PAUSE (one never before seen by PAUSE),
then PAUSE assigns an **indexing permission** to the user,
as described in the PAUSE operating model.

## Retention Period

By default, the information about you will be held indefinitely,
including after you pass away.
Once software is released to CPAN,
it generally stays there until it is either superseded
(for example by a release done by you, or someone you've given permission to),
or deleted from CPAN by you.

You can request that your personal data be erased,
as described below ("Right to Erasure").

## Lawful Basis for Processing

Under the GDPR,
a data controller must identify its *lawful basis for processing*
for all data for which it is a controller.
The six bases are defined in
[Article 6 of the GDPR](https://gdpr-info.eu/art-6-gdpr/).

After reviewing all six,
we have determined that PAUSE's basis is "legitimate interests",
defined in GDPR as:

> processing is necessary for the purposes of the legitimate interests
> pursued by the controller or by a third party,
> except where such interests are overridden by the interests
> or fundamental rights and freedoms of the data subject
> which require protection of personal data,
> in particular where the data subject is a child.

### Legitimate Interests Assessment

As per [Recital 47](https://gdpr-info.eu/recitals/no-47/) of the GDPR,
in selecting this we are required to perform a legitimate interests assessment,
addressing the following questions:

1. Purpose test: are you pursuing a legitimate interest?
2. Necessity test: is the processing necessary for that purpose?
3. Balancing test: do the individual's interests
   override the legitimate interest?

PAUSE's *legitimate interest* is providing a mechanism
that any and all Perl developers can use to share their modules
with the rest of the Perl community.
CPAN is a repository for sharing Perl-related files,
but it is PAUSE that provides the means for releasing files onto CPAN.

This processing is *necessary*,
because CPAN needs some mechanism
to ensure that once you've released a particular module,
then no-one else can release versions of that module under your username.
PAUSE does not do any processing beyond those needed to provide services
related to the upload and management of Perl modules,
and managing users' PAUSE accounts and associated information.

The *individual's interests* are not overridden,
as Perl developers choose whether they want to release code on CPAN,
and PAUSE doesn't do any processing that users wouldn't reasonably expect.

## Use of Information

PAUSE does the following things with the information described above
(in the section "Information collected by PAUSE"):

* When PAUSE needs to communicate with authors,
  it uses the secret email address if one has been provided,
  otherwise it will use the public email address.
* PAUSE generates a number of files that contain dumps of information
  from PAUSE's database.
  These are called indexes,
  and are generated specifically for public sharing,
  to enable other tools to work with CPAN.
  They are further described in the section "Sharing of Information" below.
* PAUSE generates a CHECKSUMS file in every directory,
  that has MD5 and SHA-256 checksums for all files in the directory.
* PAUSE checks files for size, consistency, and appropriateness etc.
* PAUSE may approach users with suggestions for deletions.

## Sharing of Information

PAUSE generates a number of indexes,
which contain information held in PAUSE's database.
All of the indexes are uploaded to the CPAN master site,
and are thus copied to all CPAN mirror sites around the world.

Only the following indexes contain information related to PAUSE users:

* The **00whois.xml** file has a list of all PAUSE user accounts.
  For each user it includes:
  the PAUSE id;
  the full name;
  the ASCII name;
  the public email address, if one has been provided;
  the URL for the user's home page, if one has been provided;
  and the timestamp when the account was created, in seconds since the epoch.
* The **02packages.details.txt** file, more commonly known as the *CPAN Index*,
  has a list of all packages on CPAN,
  and the path to the release tarball that contains
  the most recent version of that package.
  The path includes the PAUSE id of the user who released the tarball,
  but no other information related to the user.
* The **06perms.txt** file is a CSV dump
  of all the indexing permissions held by PAUSE.
  Each permission is a tuple of:
  a package name,
  a PAUSE user id,
  and a permission type
  (the indexing permissions model is defined in the PAUSE Operating Model).
* The **02authors.txt** file is a tab-separated file with each PAUSE user
  on a separate line.
  Each line has four fields:
  the PAUSE id,
  the public email address (or "CENSORED" if the user hasn't provided one),
  the full name,
  and the home page URL.
* The **01mailrc.txt** file defines mail aliases,
  that were described above (in the "Information collected by PAUSE" section).
  It has:
  the PAUSE id,
  full name,
  and public email address (if one was provided) for all PAUSE users. 

Given that a PAUSE id does not uniquely identify a natural person,
the only files that contain personal data are `00whois.xml`,
`02authors.txt`, and `01mailrc.txt`.
If you exercise your right to erasure,
then all the information that relates to you will be deleted from PAUSE,
leaving just the PAUSE id and the time of creation.
Those two items will then still appear in `00whois.xml`,
but the others will not. 

## Your Rights

As required by the GDPR,
you have the following rights related to your information held in PAUSE,
where PAUSE is the data controller
(as identified in the section "Information collected by PAUSE", above):

* **Right of access**:
  you have the right to know what data is being processed by PAUSE
  (as described in this document),
  how it is being processed
  (described in this document, and the PAUSE Operating Model),
  and how long your data will be held for (see "Retention Period", above).
* **Right to Rectification**:
  if any of the data about you is incorrect,
  you have the right to have it corrected.
  This covers your name, ASCII version of your name,
  both public and secret email addresses,
  your home page URL,
  and your password.
  All of these can be changed by yourself, using the PAUSE web interface.
  If for some reason you are unable to correct one of these,
  you can request help from the PAUSE admins
  by sending email to [`modules@perl.org`](mailto:modules@perl.org).
  The timestamp for your account creation cannot be changed,
  for hopefully obvious reasons.
* **Right to Erasure**:
  you have the right for the personal data related to you to be erased.
  This will blank out the full name,
  ASCII name,
  both email addresses,
  and home page associated with your PAUSE account.
  The PAUSE id will be retained,
  and all releases done by you will still be associated with that PAUSE id.
  All PAUSE indexing permissions associated with the account will be dropped.
  Currently you can invoke your right to erasure by emailing the PAUSE admins
  at [`modules@perl.org`](mailto:modules@perl.org).
  In the future we may provide an automatic function for this,
  if there is demand.
* **Right to Restriction of Processing**:
  you have the right to request that your personal data
  not be processed without your permission,
  for example if you think some or all of your data is inaccurate,
  or you're not happy with the processing being performed by PAUSE.
  Given the nature and purpose of PAUSE,
  your realistic options are either rectification or erasure,
  but until that is resolved,
  the PAUSE admins will not make any changes to your data.
* **Right to Data Portability**:
  you have the right to receive your personal data held by PAUSE
  in a commonly-used machine-readable format.
  If you request it, it will be provided as a JSON file.
  Currently this will be performed manually by the PAUSE admins,
  but if there's demand,
  this feature will be added to the PAUSE web interface.
* **Right to Object**:
  you have the right to object to the processing of your personal data
  by PAUSE.
  If you do so, the PAUSE admins will attempt to resolve this
  as quickly as possible,
  and no changes will be made to your account until it is resolved.
* **Right to Lodge a Complaint**: you have the right to
  lodge a complaint with a GDPR supervisory authority,
  if you believe PAUSE is processing your data
  in a way that is not compliant with this policy and/or the GDPR.

### Automated decision-making and profiling

PAUSE does not perform any automated decision-making or profiling,
that might produce legal effects concerning you,
or similarly affects you.

## Contact Us


If you have any questions about data protection and privacy,
as it applies to PAUSE, you can contact the PAUSE admins via email:

* The public mail list for the admins is
  [`modules@perl.org`](mailto:modules@perl.org).
  The only subscribers on the list are PAUSE admins,
  but all emails to this list are
  [publicly archived](https://www.nntp.perl.org/group/perl.modules).
* If you don't want your email to be publicly visible,
  you can send email to [`pause-admin@perl.org`](mailto:pause-admin@perl.org),
  which is another list for the admins,
  but not publicly archived.

## Change History

As this document is updated,
this section will record the changes made.

