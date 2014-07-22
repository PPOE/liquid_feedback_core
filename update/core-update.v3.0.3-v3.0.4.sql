BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('3.0.4', 3, 0, 4))
  AS "subquery"("string", "major", "minor", "revision");

ALTER TABLE "member" ADD COLUMN "authority"       TEXT;
ALTER TABLE "member" ADD COLUMN "authority_uid"   TEXT;
ALTER TABLE "member" ADD COLUMN "authority_login" TEXT;

COMMENT ON COLUMN "member"."authority"       IS 'NULL if LiquidFeedback Core is authoritative for the member account; otherwise a string that indicates the source/authority of the external account (e.g. ''LDAP'' for an LDAP account)';
COMMENT ON COLUMN "member"."authority_uid"   IS 'Unique identifier (unique per "authority") that allows to identify an external account (e.g. even if the login name changes)';
COMMENT ON COLUMN "member"."authority_login" IS 'Login name for external accounts (field is not unique!)';

ALTER TABLE "member" ADD CONSTRAINT "authority_requires_uid_and_vice_versa" 
  CHECK ("authority" NOTNULL = "authority_uid" NOTNULL);

ALTER TABLE "member" ADD CONSTRAINT "authority_uid_unique_per_authority"
  UNIQUE ("authority", "authority_uid");

ALTER TABLE "member" ADD CONSTRAINT "authority_login_requires_authority"
  CHECK ("authority" NOTNULL OR "authority_login" ISNULL);

CREATE INDEX "member_authority_login_idx" ON "member" ("authority_login");

ALTER TABLE "session" ADD COLUMN "authority"       TEXT;
ALTER TABLE "session" ADD COLUMN "authority_uid"   TEXT; 
ALTER TABLE "session" ADD COLUMN "authority_login" TEXT;

COMMENT ON COLUMN "session"."authority"         IS 'Temporary store for "member"."authority" during member account creation';
COMMENT ON COLUMN "session"."authority_uid"     IS 'Temporary store for "member"."authority_uid" during member account creation';
COMMENT ON COLUMN "session"."authority_login"   IS 'Temporary store for "member"."authority_login" during member account creation';

COMMIT;
