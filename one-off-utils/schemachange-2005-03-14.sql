alter table chapters modify chapternr int(10) unsigned not null default '0';
update chapters set shorttitle=substring(shorttitle,4);
update chapters set chapterid=substring(chapterid,4) where chapterid like '_)%';
update chapters set chapterid=substring(chapterid,5) where chapterid like '__)%';
delete from chapters where chapternr=99;
alter table mods modify chapterid int(10) unsigned not null default '0';
alter table applymod modify chapterid int(10) unsigned not null default '0';
