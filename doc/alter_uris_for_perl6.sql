alter table uris add column is_perl6 tinyint not null default 0;
alter table uris add unique key useridbaseis_perl6 (userid,basename,is_perl6);
alter table uris drop key useridbase;
update uris set is_perl6 = 1 where uriid like '%/Perl6/%';
