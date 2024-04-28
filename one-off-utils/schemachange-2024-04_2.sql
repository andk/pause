ALTER TABLE usertable ADD COLUMN mfa_secret32 varchar(16);
ALTER TABLE usertable ADD COLUMN mfa_recovery_codes text;
