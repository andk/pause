
# The PAUSE Operating Model

## Version 2


This document defines the operating model under which
the PAUSE service is provided to the Perl community.
These rules and principles are in some cases implemented in PAUSE itself,
but for the most part define how the PAUSE admins run PAUSE,
and resolve any conflicts that arise.

We also hope this document will standardise some terminology
that has evolved over the 20+ years of CPAN and PAUSE.

In writing this document,
we have identified some changes we will be making to PAUSE,
to support the operating model.
Where something isn't yet implemented,
that is explicitly mentioned.

## 1. Background

### 1.1. Principles

Before we get into the specifics,
there are a number of principles that underpin the rest of this document,
and we believe,
the CPAN community in general:

* Respect for other members of the community, and their contributions.
* Trust that everyone is doing what they believe to be the right thing,
  and not acting out of malicious intent.
* Humility to accept that we're all human after all:
  we make mistakes and we get caught up in the heat of the moment.

And some CPAN-related principles:

* If you create a module,
  then as long as you don't infringe on anyone's rights
  or include offensive content,
  then you get to decide what happens to your module.
* CPAN and PAUSE are provided as a service to the community.
  As long as you participate constructively,
  the PAUSE admins are here to help you,
  and not get in your way.
  If you repeatedly try to spoil CPAN for others,
  you will eventually be banned from contributing.

Put more simply: don't be a jerk.

If there is ever confusion,
ambiguity or conflict between the principles and specific,
documented guidelines or rules,
then the principles &mdash; as interpreted by PAUSE administrators &mdash;
take precedence.

### 1.2. Basic Terminology

CPAN is a collection of files that is mirrored across hundreds of sites:

* There is a CPAN master site.
  All other CPAN servers are mirrors either of the master site,
  or of other mirrors.
* Most of the files on CPAN reside in author-specific directories
  (e.g. Tim Bunce's files are in `https://cpan.org/authors/id/T/TI/TIMB`).


PAUSE provides the mechanism for authors to upload files to CPAN:

* For the most part, it is PAUSE that determines what gets on CPAN, and where.
* Ultimate ownership of, and decision-making authority over,
  PAUSE lies with Andreas König (ANDK on PAUSE/CPAN).
  He delegates day-to-day operations to the PAUSE admins.
  If the admins don't agree on some issue
  and cannot come up with a way to resolve it,
  Andreas is the tie-breaker.
  Andreas is one of the PAUSE admins.

Notes:

* Indexing permissions, defined in §3, relate to packages
  (referring to Perl 5 packages).
  Most packages are released to CPAN as modules,
  but a module can contain more than one package.
  A distribution might contain multiple modules and packages.
  Throughout this document, where the term "module" is used,
  you can read that as "one or more packages that might be released together
  in a single distribution".
* This version of this document applies exclusively to Perl 5 distributions.
  Support for Perl 6 is still being worked out.

## 2. Contributing to CPAN

Mostly CPAN is about sharing Perl 5 modules,
which are released in distributions.
Each release of a distribution typically contains one or more modules
(and may contain other things, such as scripts, data files, and other content).
If you want to share modules you've developed, on CPAN,
you do so via PAUSE, the Perl Authors Upload Service.

### 2.1. Getting a PAUSE account

To get an author directory you must register for an account with PAUSE.

* This involves filling in a form,
  part of which involves stating why you want the account.
* The PAUSE admins have to approve account requests.
  This is largely a formality,
  but this step is there to prevent offensive or excessively
  silly user names and other forms of abuse.
  Account approval or rejection is solely at the discretion of PAUSE admins.
  For example, if you tried to register a username that is a known trademark,
  it would not be approved.
* When you get a PAUSE account, you also get a cpan.org email address.
  If your PAUSE ID is DUMBLEDORE,
  then your CPAN email address will be `dumbledore@cpan.org`;
  this CPAN address will forward to a personal email address of your choosing.

If you repeatedly act against the interests of PAUSE or CPAN
&mdash; for example by violating one or more of the principles above &mdash;
your PAUSE account may be revoked.


### 2.2. Uploading files to PAUSE (and thus CPAN)


Anyone can upload anything to their author directories.
Although you can upload anything,
CPAN is meant for Perl things, and currently,
for distributions containing CPAN modules and/or applications.
Please don't abuse this.


* The files you upload are yours and remain in your directory
  until you delete them.
  When you delete them,
  they will eventually be removed from all regular CPAN mirrors.
* You may only upload files for which you have a right to distribute.
  This generally means either:
  (a) You created them, so own the copyright; or
  (b) Someone else created them,
  and shared them under a license that gives you the right to distribute them.
* BackPAN sites
  (for example
  [backpan.perl.org](http://backpan.perl.org) and
  [backpan.cpantesters.org](http://backpan.cpantesters.org))
  are a special type of CPAN mirror:
  they are archives of everything that has ever been released to CPAN.
  Deleting a file from your author directory will not result in it
  being removed from BackPAN sites.
* If a portion of your upload is offensive, illegal,
  or infringes on someone else's legal rights,
  the PAUSE admins may delete a file from your author directory.
  Where appropriate,
  the PAUSE admins may try to remove it from BackPAN sites as well
  (but we cannot guarantee this,
  as we do not (and cannot) enumerate all BackPAN servers).
  We will not delete things from BackPAN if your reason is something like
  "oh that's embarrassing, please delete it for me".
* Given the nature of CPAN and the purpose of PAUSE,
  your uploading of a file is interpreted as implicit permission to mirror,
  distribute, and process that file and its contents.
  We [plan to update PAUSE](https://github.com/andk/pause/issues/251)
  so that users are made aware of this when they sign up for a PAUSE account.

## 3. Indexing Permissions


PAUSE generates the **CPAN Index** and other indexes:

* If you upload a module to PAUSE,
  most users will not be able to install it unless
  it is listed in the CPAN Index.
* The CPAN Index maps Perl packages to an uploaded file on CPAN,
  typically a tar or zip archive
  (i.e. it tells CPAN clients a file path on a CPAN mirror
  that provides that package).
  See entry on
  [CPAN Index](http://neilb.org/2015/09/05/cpan-glossary.html#cpan-index)
  in CPAN Glossary.
* PAUSE has ultimate control over what goes in the CPAN Index.
* Copyright of all PAUSE-generated indexes (including the CPAN Index)
  lies with Andreas König.
  Andreas will be adding explicit license statements to all such files,
  once he's selected an appropriate license.

**PAUSE indexing permissions** are tuples that are held in PAUSE's database.

* Each indexing permission identifies a single package name,
  a PAUSE user ID, and a type.
* An indexing permission says that any releases of the named package
  by the specified author can be considered for inclusion in the CPAN Index.
* The type identifies how much control the identified author
  has over indexing permissions for the package.
* There are three types &mdash; **first-come**, **co-maint**,
  and **admin** &mdash;
  and they are defined in §3.1, §3.2, and §3.3 respectively.

To reiterate:
PAUSE indexing permissions control whether the individual Perl packages
in your upload will be considered for inclusion in the CPAN Index.

* Indexing permissions do not control
  whether you can upload a given package to your author directory.
* If you do not have an indexing permission on the main module of your release
  (the module with a name that matches the distribution name,
  so module `Foo::Bar` for distribution `Foo-Bar`),
  then none of the modules in the release will be indexed,
  regardless of whether you have indexing permissions for them.
* If you have an indexing permission on the main module,
  and have indexing permissions on some but not all of the other packages
  in a release,
  then only those packages for which you have indexing permissions
  will be updated in the index.
  At the end of the indexing phase,
  PAUSE sends you an email which lets you know what packages were found,
  and which of them were indexed.
* Indexing permissions may be revoked (or transferred)
  if the name of the package is offensive, illegal,
  or infringes on someone's or some company's rights.
* Indexing permissions aren't the only factor that controls
  whether a package will be added to the index.
  The other factors are listed in §3.5. below.

Indexing permissions do not give you any control over any other author's directory:

* If you have first-come,
  grant co-maint to someone and subsequently don't like a release they do,
  you cannot delete their release, and cannot expect the PAUSE admins to.
  You can revoke the co-maint
  and then release with a higher version number.


### 3.1. First-come indexing permission


The first person to upload a package is granted
the **first-come** indexing permission by PAUSE.
The person who holds the first-come indexing permission
has control over who else has indexing permissions on that package.
Roughly 70% of modules on CPAN have a first-come
and no other indexing permission.


Having first-come indexing permission on a package means:

* You have indexing permission:
  your uploads containing that package will be eligible for indexing
  (subject to the general restrictions listed in §3 above).
* You can grant admin to others, and revoke admin
  (the "admin" indexing permission is defined in §3.2 below).
* You can grant co-maint to others, and revoke co-maint
  (the "co-maint" indexing permission is defined in §3.3 below).


Reserving a namespace in the index for future work,
for example by uploading an empty module, is discouraged.
If done repeatedly or for longer than a brief time,
admins may judge such behavior as against the interests of CPAN
and intervene to correct the situation.


#### 3.1.1. Transferring your first-come to someone else

You can transfer your first-come indexing permission to someone else,
using the PAUSE web interface.
You need the PAUSE username of the person you're transferring to
(there are also some special PAUSE usernames, discussed in §4.4 below).


Having transferred a first-come to someone else,
you cannot "undo" that transfer, so think carefully before doing this.
If you do want to reverse a transfer, you have two options:

* Convince the PAUSE admins that you accidentally transferred first-come
  either (a) on the wrong package, or (b) to the wrong account.
* Convince the person you transferred to, to transfer it back.

When you transfer a first-come permission,
you become a co-maint on the package.
If you no longer wish to retain any permissions,
you can subsequently drop the co-maint.
When the admin permission is implemented,
transferring first-come will result in
you getting the admin indexing permission.


#### 3.1.2. Dropping your first-come indexing permission

At the moment,
if you have first-come indexing permission on a package,
PAUSE will let you give up the first-come
without transferring it to someone else.
This means the package ends up with
no-one holding a first-come indexing permission on the package.

If there are no other permissions on the package
(i.e. no admin or co-maint),
anyone can then upload a release of that package,
and they will be granted first-come.

If you drop first-come on a package,
and one or more other authors have an indexing permission on that package,
then the next person to release the package
**will not** be granted first-come by PAUSE,
regardless of whether they currently have an indexing permission.

Where a package does not have a first-come but has other permissions,
any of the people with other permissions on the package (co-maint or admin),
or even anyone else
(i.e. those who don't currently have any indexing permissions on the package),
are free to apply for first-come.
If someone requests first-come on a package,
the PAUSE admins will consider any community around the package,
and the number of downstream dependents
(the number of other CPAN distributions that rely on it).
For example,
if a module is relied on by many other CPAN distributions,
then the PAUSE admins will not transfer first-come
to someone who doesn't have much Perl and CPAN experience.
Once the admin permission is implemented,
the PAUSE admins will generally grant admin if appropriate,
and not first-come.

Think carefully before giving up first-come permissions,
especially if (a) other people have admin or co-maint permissions,
and/or (b) other modules on CPAN rely on the package.

In the near future,
we plan to modify PAUSE so that
"giving up your first-come indexing permission"
will result in first-come being transferred to the special user **`ADOPTME`**
(described in §4.5.1 below),
if other people have admin or co-maint permissions.
This makes the situation clearer to everyone.

At some point after that we may change PAUSE so that
when giving up a first-come permission,
you're informed who else has permissions,
and given the option of transferring first-come to one of them. 


### 3.2. Admin indexing permission

The **admin** indexing permission doesn't exist yet.
It [will be added to PAUSE](https://github.com/andk/pause/issues/253),
hopefully soon.

Having admin indexing permission on a package will mean:

* You have indexing permission:
  your uploads containing that package will be considered for indexing.
* You can grant co-maint to others, and revoke co-maint.
* You cannot grant or revoke either admin or first come.
  Other admins cannot revoke your admin permission.
* You can give up your admin permission.
  When you do so you will be given co-maint;
  if you don't want any indexing permissions on the package,
  you'll then need to drop the co-maint.
* You cannot transfer your admin permission to another PAUSE user.
* Only the first-come can revoke your admin permission.

At the moment,
if the original author of a distribution wants to let someone else
grant co-maints to project members,
the only way they can do this is by transferring their first-come permission.
The admin permission solves this problem:
the original author can retain first-come,
and give one or more team members the admin permission.

### 3.3. Co-maint indexing permission

Having **co-maint** on a package means:

* You have indexing permission:
  your uploads containing that package will be considered for indexing.
* You cannot grant or revoke any indexing permissions.
* You can give up your co-maint permission.
* You cannot transfer your co-maint permission to anyone else.

### 3.4. Listing indexing permissions

There are a number of ways you can look at
the indexing permissions held by PAUSE.

#### 3.4.1. Viewing permissions online

You can look at indexing permissions using the **View Permissions** tool
in the PAUSE web interface.
By default this will show you all of your indexing permissions,
but you can also look for all permissions on a given package,
or all permissions for a given PAUSE ID.

#### 3.4.2. 06perms.txt

Four times an hour PAUSE dumps a copy of all indexing permissions
into a file called `06perms.txt`,
which you can find on any CPAN mirror in `$CPAN/modules/06perms.txt`.
It has a header,
followed by a single blank line,
and then a list of the indexing permissions, one per line.

Each line has three columns, separated by commas:

* Package name
* PAUSE ID
* Type, which will currently be one of '**f**' (for first-come),
  or '**c**' (for co-maint).

Here are the entries for the
[HTTP::Tiny](https://metacpan.org/pod/HTTP::Tiny) module:

    HTTP::Tiny,CHANSEN,c
    HTTP::Tiny,DAGOLDEN,f

### 3.5. Factors considering in the indexing phase

In addition to the indexing permissions introduced above,
the following factors are considered when deciding whether
one or all of the packages in a release will be included in the index:

* Is the upload a developer release?
  If PAUSE determines that an upload is a developer release (see §3.6. below),
  then none of the packages in the release are considered for indexing.
* Does the `$VERSION` of the package identify it as a developer version?
  If the upload wasn't identified as a developer release,
  but the `$VERSION` contains an underscore,
  then the package will not be indexed.
* Does the person uploading have an indexing permission on the *main module*
  for the distribution? If not, then none of the other modules in the
  release will be considered.
* Does the person uploading have an indexing permission on each package?
* The version number for a package must be non-decreasing:
  if you release 1.01,
  then 1.03 and subsequently release 1.02,
  the 1.02 version will not be indexed.
* The metadata for a distribution (`META.yml` or `META.json`)
  can exclude certain packages from indexing,
  with the [**`no_index`**](https://metacpan.org/pod/CPAN::Meta::Spec#no_index) directive.
* The [**`provides`**](https://metacpan.org/pod/CPAN::Meta::Spec#provides)
  directive,
  if it appears in a release's metadata,
  provides a list of package names,
  and a version number for each one.
  If there is a **`provides`** directive,
  PAUSE will trust that, and not inspect the source code.
  If a package is included in your release,
  but not listed in the provides section of the metadata,
  then it will not be indexed by PAUSE.
* In the source of the module,
  if there is a newline character between "`package`" and the package name,
  then PAUSE will take this as a hint to not consider the module for indexing
  (this was a hack put in place before the **`no_index`** directive
  was available,
  but given it is used by many distributions on CPAN,
  it will be respected for the forseeable future).
* If an error (in PAUSE) happens during indexing,
  then one or more packages in a distribution may end up not being indexed.
  You will generally be informed about this in an email you receive from PAUSE.
  If this happens,
  the first thing you should try is asking PAUSE to re-index your release,
  using the "Force reindexing" section of the PAUSE web interface.


### 3.6. Developer releases

Developer releases are a mechanism for sharing test releases on CPAN,
without the release being added to the index.
PAUSE classifies an upload as a developer release
if the name of the uploaded file matches either of the following:

* **`/\d\.\d+_\d/`**
* **`/-TRIAL[0-9]*/`** immediately followed by the file extension
  (such as .zip, .tar.gz, .tgz, etc).


Developer releases aren't considered for indexing,
so you'll only get the first email from PAUSE,
which acknowledges the upload.
The second email gives the results of indexing,
and so isn't sent for developer releases.

Automated smoke testers for CPAN
(bots which run tests on everything uploaded to CPAN)
will usually test developer releases,
so you'll get notice from CPAN Testers of any test failures.
This is the main reason for uploading developer releases
(you might also ask people to test your release as well).

As noted above,
if an upload is not identified as a developer release,
but one of the packages has an underscore in the `$VERSION` number,
then *just that package* will be classified as a developer release,
and the package will not be considered for indexing.
You almost certainly shouldn't use this feature,
as you'll end up with two different releases
of your distribution appearing in the index.

## 4. Dealing with PAUSE indexing issues

### 4.1 Unresponsive CPAN authors

In a number of the clauses below,
we refer to *unresponsive* authors.
An author is classified as unresponsive if all of the following apply:

* Email to their CPAN email address either bounces, or isn't replied to.
* You have made reasonable efforts to contact the author
  using other email addresses or media:
   * Check the documentation for their CPAN releases
     to look for alternate email addresses.
   * Can you find them on social media
     (for example, but not limited to, LinkedIn or Twitter)?
   * Ask on IRC or on the module-authors@perl.org mailing list
     if anyone has a working email address.
* It has been at least several weeks since your first email to the author.
  The exact time you're expected to wait might vary from author to author.
  For example, if an author has been fairly active in the last year or so,
  then you'll probably be expected to wait a bit longer.
  But if an author hasn't released anything in the last 10 years, say,
  then several weeks will be fine.

If you, as an author,
are planning on being uncontactable for more than a month,
you might consider letting the PAUSE admins know.


### 4.2. Requesting an indexing permission transfer


Occasionally you might find a problem with a module you're using,
but the current maintainer appears to no longer be working on it.
and you end up running your own patched version.
If you're interested in getting co-maint so you can upload a fixed release,
you should first contact the current first-come,
or package admins,
if it has any (once that feature has been implemented).
If you don't get a response,
you may ask the PAUSE admins to give you co-maint on the relevant package(s),
so you can do a new release.

If the current maintainer(s) for a package are unresponsive
for an extended period,
PAUSE admins may, at their discretion,
grant new or enhanced permissions to allow bug fixes
and new development to be indexed on CPAN.
When asking PAUSE admins for permissions because someone is unresponsive:

* You must show due diligence of trying to track the person down.
* You must allow at least several weeks (people go on holiday, get sick, etc.).
* The PAUSE admins may do extra tracking down or request you to do so.

If you have been granted permissions by the PAUSE admins
due to an unresponsive author,
if that author eventually reappears / responds,
you may lose any permission(s) granted by the PAUSE admins,
or have them downgraded.

If the current maintainer(s) for a package *are* responsive,
but you don't like what they're doing with it,
the PAUSE admins will not consider requests for a permissions transfer/upgrade. 

> For example:
a group of users of a module don't like the direction the first-come,
or admin, or co-maint is now taking the module in,
you cannot petition the PAUSE admins for a take-over
"for the good of the community".
There is a clearly defined option available:
fork the module, and presumably the community around it,
and take your fork in the direction you want.

If the first-come isn't responsive,
but the module is clearly documented as feature complete,
then do not ask for indexing permissions
so you can release changes to the interface.
If you only want to update the distribution
to follow modern CPAN / packaging conventions
(e.g. to ensure it includes metadata files),
or to address a security issue,
then the PAUSE admins *may* consider a permissions request.
Such modules will be considered on a case-by-case basis.

If you have co-maint for a package,
and a history of releases,
you may ask the PAUSE admins for admin indexing permission on the package.
This is presumably so you can grant co-maint to others who want to help you.

* If the package has a first-come,
  you must demonstrate that they are unresponsive.
* If the package doesn't have a first-come,
  but has other admins (e.g. first-come permissions were dropped),
  then either you must demonstrate that they're unresponsive,
  or that they're all happy for you to have admin.
* If the package doesn't have a first-come or any other admins,
  but has one or more other co-maints,
  then you must demonstrate that they're either (a) unresponsive,
  or (b) happy for you to be elevated to admin.
  This is to prevent one member of a team
  taking a distribution in a direction
  that other team members disagree with.

If you do not have co-maint for a package,
you may ask the PAUSE admins for co-maint indexing permission on the package.
This is presumably so you can make new, indexed releases to CPAN.

* If the package has a first-come and/or admin,
  you must demonstrate that they are all unresponsive.
* If the package doesn’t have a first-come or admin,
  but does have other co-maints,
  then either you must demonstrate that they’re unresponsive,
  or that they’re all happy for you to have co-maint.
* PAUSE admins will take into account your existing involvement in the package
  (e.g. bug reports, pull requests, etc.)
  in deciding whether to add you as new co-maint.
  PAUSE admins will also consider the number of downstream dependents,
  with a higher bar for highly-depended-upon packages.

Once the admin permission is implemented,
the PAUSE admins will never transfer first-come permissions
from an existing account to another.

* Except for special accounts **ADOPTME**, **HANDOFF**, and **NEEDHELP**,
  which are described in §4.5 below.
* Except for addressing unreasonable “reserved” permissions,
  as described in §3.1 above.

### 4.3. Resolving disagreements over indexing permissions

The PAUSE admins will not override the wishes of the first-come where:

* The same person has always held first-come, or
* When first-come was transferred,
  it was clear that the original first-come intended
  to transfer total control over the indexing permissions for the package,
  as opposed to some cases,
  where the first-come made a pragmatic decision to
  transfer the first-come permission so that
  someone else could assign co-maints to collaborators.

If you disagree with the first-come,
you can always fork the package,
if the license permits that.

In the past,
if the originator of a module wanted to let someone else
grant co-maint permissions,
the only way they could do this was by
transferring the first-come indexing permission.
This is why we're introducing the admin indexing permission:
once that is implemented,
we hope there won't be any ambiguity about
transferring first-come indexing permissions.


Borrowing from the [perlpolicy](https://perldoc.perl.org/perlpolicy.html)
document:

* The PAUSE admins recognise that respect for ownership of code,
  respect for artistic control, proper credit,
  and active effort to prevent unintentional code skew or communication gaps
  is vital to the health of the community and CPAN itself.
* Members of a community should not normally have to resort to rules and laws
  to deal with each other, and this document,
  although it contains rules so as to be clear,
  is about an attitude and general approach.
* The first step in any dispute should be open communication,
  respect for opposing views, and an attempt at a compromise.
* In nearly every circumstance nothing more will be necessary,
  and certainly no more drastic measure should be used until
  every avenue of communication and discussion has failed.

If a community grows around a distribution / package,
we encourage the first-come author and community to develop guidelines
for indexing permissions and succession
to avoid future surprises or direction changes to the project.
PAUSE admins may, on request by a first-come author,
but at their own discretion,
assist a community in establishing collective ownership
over first-come permissions and collective governance over admin permissions.

* e.g. the original author may transfer first-come to a community account
  and keep only admin permissions
* PAUSE admins will create/revoke admin permissions at the community’s
  request following whatever governance procedures the community has established
* Disputes over admin/co-maint indexing permissions
  should be resolved within that community, whenever possible
* If community governance fails,
  the community may ask PAUSE admins to help mediate conflict
* In very rare situations, when mediation fails,
  the PAUSE admins may decide that they need to take direct action
  to resolve a governance failure.
  This should be a last resort and will take into account
  the collective PAUSE admins’ view of the best outcome for the Perl community.
  Any such decision will be directly reviewed and approved by
  Andreas König before action is taken.


### 4.4. Freezing indexing permissions for a module

If, as first-come,
you do not want indexing permissions transferred / granted
to another person without your explicit permission,
you can record this:

* Give co-maint to the **NOXFER** user.
  If your distribution contains multiple modules,
  you only need to give co-maint to NOXFER on the main module.
  If it's not clear what the main module is,
  then err on the side of giving it to all modules in the distribution.
* Consider adding a section to the documentation,
  with your policy on indexing permissions.
  Many users are more likely to see this rather than the NOXFER permission.

The PAUSE admins will honour the NOXFER permission:
if someone asks for co-maint on a package that has NOXFER on it,
then the PAUSE admins will only do this with the express permission
of the first-come.
There is one exception to the above:

* If a module is widely used,
  and a security issue is identified,
  and the author is unresponsive (as defined in §4.1),
  then the PAUSE admins may give co-maint,
  following the process in §4.3,
  but only to deal with the security issue.

As an author,
you should think carefully before doing this,
and ensure your statement is unambiguous,
and lets the PAUSE admins know what to do if
(1) you're not contactable,
(2) you lose interest in Perl/CPAN, or
(3) are incapacitated or pass away.

### 4.5. Special PAUSE usernames

There are a number of special PAUSE usernames
that have a particular interpretation and/or tooling support.

If you come across a situation not covered in §4.5.1 through §4.5.5,
please contact the PAUSE admins (modules@perl.org) for clarification.


#### 4.5.1. ADOPTME

If a package has **ADOPTME as first-come**,
you can email the PAUSE admins and ask for first-come to be given to you

* If you really have no further interest in a package,
  you can transfer your first-come to ADOPTME.
* PAUSE admins will use their judgement in transferring first-come,
  similar to the criteria for adding a new co-maint,
  with a higher bar for highly-depended-upon packages,
  as described in §4.2.

A package having **ADOPTME as co-maint** indicates
an (already verified) unresponsive author.

* You can request indexing permission on it without waiting a month
* If you're not interested in one of your packages,
  you can give co-maint to ADOPTME to flag its availability.
  If someone applies to the PAUSE admins for co-maint,
  the admins may consider
  how many other CPAN distributions are dependent on it.

You can find modules with ADOPTME as first-come or co-maint at this URL:

> https://rt.cpan.org/Public/Dist/ByMaintainer.html?Name=ADOPTME




#### 4.5.2. HANDOFF

Giving **co-maint to HANDOFF**
indicates that you're open to someone else asking for your
first-come permissions,
but that you wish to decide on any such request.

In the past,
original authors of packages have transferred their first-come permission
to subsequent maintainers,
as that was the only way they could grant co-maint to others.
Once the admin permission is available,
such original authors can ask the PAUSE admins to give them back first-come,
and grant admin to the present first-come.
Where the history for a package isn't clearly documented,
the PAUSE admins will resolve the situation on a case-by-case basis,
first hoping that the relevant parties can resolve without intervention.

You can find modules with HANDOFF at this URL:

> https://rt.cpan.org/Public/Dist/ByMaintainer.html?Name=HANDOFF




#### 4.5.3. NEEDHELP

If you would like additional volunteers
to help you work on a particular module,
you can grant **co-maint to NEEDHELP**.

You can find modules where
the author is currently looking for help with this URL:

> https://rt.cpan.org/Public/Dist/ByMaintainer.html?Name=NEEDHELP


#### 4.5.4. NOXFER

If you do not want the PAUSE admins to grant or transfer indexing permissions
for a package,
then grant **co-maint to NOXFER**.

You can find modules marked for no permissions transfer with this URL:

> https://rt.cpan.org/Public/Dist/ByMaintainer.html?Name=NOXFER


#### 4.5.5. P5P

This means "Perl 5 Porters",
the group that maintains and develops Perl 5.
The P5P user belongs to the current Pumpking
(the title given to the current leader of the P5P group),
and has indexing permission on all core modules.

See §4.8 below,
on what happens when a CPAN module is proposed to become a core module
(be included with Perl itself).
 

### 4.6. When a CPAN author passes away

When a CPAN author passes away,
the PAUSE admins will make the following changes:

* The name of the account has "(PAUSE Custodial Account)" appended.
* All co-maint and admin indexing permissions of that account are dropped.
* All first-come indexing permissions are transferred to ADOPTME.
  In the future,
  we would like to automatically inform any people with co-maint
  and admin indexing permissions on the same package, to
  (a) let them know, and
  (b) give them a chance to apply for the first-come.


### 4.7. Treading on another author's toes (namespaces or permissions)


Indexing permissions only control the mapping of
a package name to a CPAN filename.
However,
Perl module installation typically runs arbitrary code on the target machine.
While end-users must take ultimate responsibility for the effects of
installing CPAN modules,
PAUSE admins strongly encourage authors of indexed packages to
limit filesystem changes to files that correspond to the package names
for which they have permissions.

As a general rule,
installing an indexed distribution (i.e. tarball, zip file),
should not change post-install module loading for any package
that is not indexed to that distribution:

* Installing your module(s) should not result in changes to
  someone else's modules that might already be installed,
  either by changing them or removing them.
* The one exception to the above is where that's the whole raison d'être
  of your module.
  In that case it should be clearly documented as such,
  and the installation process should get explicit user confirmation
  that they wish to proceed with this.
  The documentation and name of your module should be respectful.
* If your distribution is deemed to be performing a stealth attack on
  another distribution,
  it will be removed from the CPAN Index.
  If you're not sure,
  discuss it on relevant email lists
  (e.g. cpan-workers@cpan.org, and any mailing list for the target module)
  and with the PAUSE admins (see below) before releasing it.


### 4.8. When your module is proposed to become a core module

A **core module** is one that is shipped with Perl itself.
A **dual-life module** is one that is shipped with Perl itself,
but is also released on CPAN in a standalone distribution.
Many dual-life modules started as a regular CPAN release,
then were proposed for promotion to the core.
These days that's much less likely to happen, but if it should:

* Read the section "[A Social Contract about Artistic Control](https://perldoc.perl.org/perlpolicy.html#A-Social-Contract-about-Artistic-Control)" in [perlpolicy](https://perldoc.perl.org/perlpolicy.html).
* If the Pumpking agrees with the proposal,
  it is the first-come's decision on whether the module should become dual-life.
* If the first-come says "no",
  and the license allows it,
  the Pumpking can always fork the module to a new namespace and
  release a new distribution to CPAN,
  and promote that to dual-life.
  The Pumpking and first-come may decide on this course of action together,
  for example where the first-come wants the freedom to
  make backwards incompatible changes.
* If a module becomes dual-life,
  then the first-come permission may be transferred to the P5P account
  (in which case the original author will get the indexing admin permission
  (once that's implemented), or co-maint),
  or P5P may be given co-maint
  (the special P5P PAUSE id is controlled by the Pumpking,
  and is described in §4.5.5 above).
* If you have a dual-life module,
  P5P requests that you nominate at least another trusted maintainer
  to be a liaison for P5P when the time arises and you are unavailable.

Any further discussion on core modules is within the purview of
the Perl 5 Porters group, and beyond the scope of this document.


## 5. Licensing & Copyright

### 5.1 Licensing

The PAUSE admins mostly have no part to play in licensing.

* If you upload something to PAUSE with a license specified,
  that license must give permission for the file to be copied
  to all CPAN mirrors.
  If that's not true, then your upload may end up being deleted from CPAN.
* With respect to licenses, PAUSE admins will not
   * Tell you what license to use
   * Compel you to include a license
   * Comment on the suitability or otherwise of a particular license.
* Individual PAUSE admins may give their personal opinion, if asked for.
* There is one exception to the above:
  if you upload something to PAUSE that violates the license of some or all of
  the upload, then the PAUSE admins will remove it.
  For example: If you write a Perl interface to a C library,
  and include the C library in your distribution,
  but the license for the C library explicitly disallows that.
* When uploading software to PAUSE,
  we *strongly recommend* that you always specify the license
  under which it is being distributed.
  Otherwise people will not know what they can and cannot do with it.
  Furthermore, if you haven't specified a license,
  and accept contributions from other people,
  then [things are legally muddied](https://choosealicense.com/no-license/).
  This is particularly an issue for Linux distributions, etc.:
  most distros will not include CPAN distributions that
  do not have an explicit license.
* If an upload does not include or specify any license,
  the act of uploading it does not imply any particular license.


### 5.2. Licensing vs Indexing Permissions vs Copyright

Disclaimer: none of the authors of this document are lawyers.

Previous documents about PAUSE referred to indexing permissions
in terms of "module ownership",
which has caused misunderstandings.
This is why we now refer to first-come, admin,
and co-maint as *PAUSE indexing permissions*.
Indexing permissions have nothing to do with
copyright or licensing of a module,
or ownership of the code.

Authors of an original work automatically have copyright of that work.
If you create an entirely original module and release it to CPAN,
you will be assigned first-come and will automatically have copyright.
You can, and should, decide what license you are sharing it under.

If you fork someone else's module and release it to CPAN under a new namespace,
you will be granted first-come indexing permission on that namespace,
but you must of course respect the original author's copyright per the license,
and pay close attention to the license under which
the original author shared the module.

If you fork someone else's module,
and release it under a new name,
and in some way violate their copyright and/or license,
the PAUSE admins may ask you to resolve this.
If you do not,
the PAUSE admins may eventually remove the offending release(s) from CPAN.
This could theoretically be the result of the copyright owner
asking the PAUSE admins to enforce their rights.

Further discussion on copyright and licensing
is beyond the scope of this document.
See [this presentation](https://www.pathlms.com/siam/courses/4150/sections/5826/video_presentations/42639) for a good introduction to copyright and licensing.
Most countries are [signatories](https://copyrighthouse.co.uk/copyright/countries-berne-convention.htm) of the [Berne convention](https://en.wikipedia.org/wiki/Berne_Convention),
so have the same basic copyright laws.



## 6. About the PAUSE Admins

### 6.1. PAUSE administrator responsibilities

* Dealing with applications for PAUSE accounts
* Handling situations where authors need help accessing their account
  (lost access to the email address)
* Resolving requests for transfer of indexing permissions
* Handling help requests from authors related to uploads.
  E.g., "what does this email from PAUSE mean?"
* Resolving disputes over namespace ownership, trademark infringement, etc.
  The preferred course is that the issue be resolved directly
  with the releasing author,
  but ultimately the claimant can raise it with the PAUSE admins.

### 6.2. PAUSE admin code of conduct

* Admins should act according to the policies in this document,
  holding themselves to a high standard.
* Admin actions done by PAUSE admin must be "on the record",
  by sending an email to modules@perl.org.
  (Security and identity-related actions may be exempted as appropriate).
  In the early days of CPAN, there was a "module list",
  and to get on that list you sent email to this address.
  The maintenance of that list evolved into the PAUSE admins of today. 
* Admins should not transfer package indexing permissions to themselves
  without prior notification of other admins.
  Where possible, ask another admin to make the transfer.
* When expressing opinions related to Perl,
  particularly the toolchain,
  admins should clarify whether expressing personal opinions,
  or expressing a PAUSE admin opinion.
* Regardless of the above,
  PAUSE admins are unavoidably going to be seen as
  authority and/or leadership figures,
  and should always be respectful of other members of the Perl community,
  whether acting as a PAUSE admin or not.

### 6.3. Contacting PAUSE administrators 

There are two mailing lists for the PAUSE admins:

* modules@perl.org is the public list.
  Any email sent to this address is forwarded to all of the PAUSE admins,
  and will appear in the public archive:
  http://www.nntp.perl.org/group/perl.modules/.
  Anyone can send email to this list.
  This is the official way to contact the PAUSE admins.
  Many of the admins are on IRC,
  but we prefer all requests go to the mail alias,
  so they're "on the record".
* pause-admin@perl.org is a private mailing list for the PAUSE admins.
  This is where the admins discuss issues such as early drafts of this document.

Please remember that all PAUSE admins are volunteers,
all of them are also CPAN authors as well,
and they donate their time to help CPAN.

### 6.4. Appealing PAUSE administrator decisions

In general,
decisions by a PAUSE administrator are final.
However,
should a member of the community feel that
a PAUSE admin has not acted in accordance with the principles of this document,
they should first address this directly with the PAUSE admin involved.

If this does not suffice, there are two further avenues for recourse:

* Email modules@perl.org with a description of the situation,
  the decision and a petition for relief.
  This avenue is **public** as such emails are publically archived,
  but is likely to receive a faster response
  as it is monitored by the greater body of PAUSE admins.
* Email Andreas König directly at andk@cpan.org with
  a description of the situation, etc.

### 6.5. Who are the PAUSE admins?

You can always find out who the current PAUSE admins are
via the PAUSE admin web interface:

> https://pause.perl.org/pause/query?ACTION=who_admin


### 6.6. Who picked the PAUSE admins?

The PAUSE admins are all CPAN authors who have demonstrated
a desire to help CPAN in various ways.
Typically people became a PAUSE admin because help was needed,
and the existing active admins discussed who would make a good admin.
All admins were either picked by Andreas,
or approved by Andreas from a recommendation made by another admin or admins.


### 6.7. Succession planning

Much of this document relies on
Andreas as the ultimate authority and breaker of ties.

We don't currently have a second-in-command,
or succession plan.
We will be working to improve the
[bus factor](https://en.wikipedia.org/wiki/Bus_factor).



## 7. About this document

Every edition of this document will have a version number.
The PAUSE admins will always refer to the latest version of the document.
Once published,
we only envisage incremental changes.
The principles and rules in this version are likely to be further refined,
but not radically changed.

Changes from one version to the next will be recorded here.

