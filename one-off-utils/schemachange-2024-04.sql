ALTER TABLE packages ADD COLUMN lc_package varchar(128) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '';
ALTER TABLE primeur ADD COLUMN lc_package varchar(245) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '';
ALTER TABLE perms ADD COLUMN lc_package varchar(245) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '';
UPDATE packages SET lc_package = LOWER(package);
UPDATE primeur SET lc_package = LOWER(package);
UPDATE perms SET lc_package = LOWER(package);
ALTER TABLE packages ADD INDEX lc_package (lc_package);
ALTER TABLE primeur ADD INDEX lc_package (lc_package);
ALTER TABLE perms ADD INDEX lc_package (lc_package);
