alter table packages add distname varchar(128) not null default '' after dist;
create index distname on packages (distname);
