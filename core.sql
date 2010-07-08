
CREATE LANGUAGE plpgsql;  -- Triggers are implemented in PL/pgSQL

-- NOTE: In PostgreSQL every UNIQUE constraint implies creation of an index

BEGIN;

CREATE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('1.1.0', 1, 1, 0))
  AS "subquery"("string", "major", "minor", "revision");



----------------------
-- Full text search --
----------------------


CREATE FUNCTION "text_search_query"("query_text_p" TEXT)
  RETURNS TSQUERY
  LANGUAGE 'plpgsql' IMMUTABLE AS $$
    BEGIN
      RETURN plainto_tsquery('pg_catalog.simple', "query_text_p");
    END;
  $$;

COMMENT ON FUNCTION "text_search_query"(TEXT) IS 'Usage: WHERE "text_search_data" @@ "text_search_query"(''<user query>'')';


CREATE FUNCTION "highlight"
  ( "body_p"       TEXT,
    "query_text_p" TEXT )
  RETURNS TEXT
  LANGUAGE 'plpgsql' IMMUTABLE AS $$
    BEGIN
      RETURN ts_headline(
        'pg_catalog.simple',
        replace(replace("body_p", e'\\', e'\\\\'), '*', e'\\*'),
        "text_search_query"("query_text_p"),
        'StartSel=* StopSel=* HighlightAll=TRUE' );
    END;
  $$;

COMMENT ON FUNCTION "highlight"
  ( "body_p"       TEXT,
    "query_text_p" TEXT )
  IS 'For a given a user query this function encapsulates all matches with asterisks. Asterisks and backslashes being already present are preceeded with one extra backslash.';



-------------------------
-- Tables and indicies --
-------------------------


CREATE TABLE "member" (
        "id"                    SERIAL4         PRIMARY KEY,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "last_login"            TIMESTAMPTZ,
        "login"                 TEXT            UNIQUE,
        "password"              TEXT,
        "active"                BOOLEAN         NOT NULL DEFAULT TRUE,
        "admin"                 BOOLEAN         NOT NULL DEFAULT FALSE,
        "notify_email"          TEXT,
        "notify_email_unconfirmed"     TEXT,
        "notify_email_secret"          TEXT     UNIQUE,
        "notify_email_secret_expiry"   TIMESTAMPTZ,
        "notify_email_lock_expiry"     TIMESTAMPTZ,
        "password_reset_secret"        TEXT     UNIQUE,
        "password_reset_secret_expiry" TIMESTAMPTZ,
        "name"                  TEXT            NOT NULL UNIQUE,
        "identification"        TEXT            UNIQUE,
        "organizational_unit"   TEXT,
        "internal_posts"        TEXT,
        "realname"              TEXT,
        "birthday"              DATE,
        "address"               TEXT,
        "email"                 TEXT,
        "xmpp_address"          TEXT,
        "website"               TEXT,
        "phone"                 TEXT,
        "mobile_phone"          TEXT,
        "profession"            TEXT,
        "external_memberships"  TEXT,
        "external_posts"        TEXT,
        "statement"             TEXT,
        "text_search_data"      TSVECTOR );
CREATE INDEX "member_active_idx" ON "member" ("active");
CREATE INDEX "member_text_search_data_idx" ON "member" USING gin ("text_search_data");
CREATE TRIGGER "update_text_search_data"
  BEFORE INSERT OR UPDATE ON "member"
  FOR EACH ROW EXECUTE PROCEDURE
  tsvector_update_trigger('text_search_data', 'pg_catalog.simple',
    "name", "identification", "organizational_unit", "internal_posts",
    "realname", "external_memberships", "external_posts", "statement" );

COMMENT ON TABLE "member" IS 'Users of the system, e.g. members of an organization';

COMMENT ON COLUMN "member"."login"                IS 'Login name';
COMMENT ON COLUMN "member"."password"             IS 'Password (preferably as crypto-hash, depending on the frontend or access layer)';
COMMENT ON COLUMN "member"."active"               IS 'Inactive members can not login and their supports/votes are not counted by the system.';
COMMENT ON COLUMN "member"."admin"                IS 'TRUE for admins, which can administrate other users and setup policies and areas';
COMMENT ON COLUMN "member"."notify_email"         IS 'Email address where notifications of the system are sent to';
COMMENT ON COLUMN "member"."notify_email_unconfirmed"   IS 'Unconfirmed email address provided by the member to be copied into "notify_email" field after verification';
COMMENT ON COLUMN "member"."notify_email_secret"        IS 'Secret sent to the address in "notify_email_unconformed"';
COMMENT ON COLUMN "member"."notify_email_secret_expiry" IS 'Expiry date/time for "notify_email_secret"';
COMMENT ON COLUMN "member"."notify_email_lock_expiry"   IS 'Date/time until no further email confirmation mails may be sent (abuse protection)';
COMMENT ON COLUMN "member"."name"                 IS 'Distinct name of the member';
COMMENT ON COLUMN "member"."identification"       IS 'Optional identification number or code of the member';
COMMENT ON COLUMN "member"."organizational_unit"  IS 'Branch or division of the organization the member belongs to';
COMMENT ON COLUMN "member"."internal_posts"       IS 'Posts (offices) of the member inside the organization';
COMMENT ON COLUMN "member"."realname"             IS 'Real name of the member, may be identical with "name"';
COMMENT ON COLUMN "member"."email"                IS 'Published email address of the member; not used for system notifications';
COMMENT ON COLUMN "member"."external_memberships" IS 'Other organizations the member is involved in';
COMMENT ON COLUMN "member"."external_posts"       IS 'Posts (offices) outside the organization';
COMMENT ON COLUMN "member"."statement"            IS 'Freely chosen text of the member for his homepage within the system';


CREATE TABLE "member_history" (
        "id"                    SERIAL8         PRIMARY KEY,
        "member_id"             INT4            NOT NULL REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "until"                 TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "login"                 TEXT,
        "active"                BOOLEAN         NOT NULL,
        "name"                  TEXT            NOT NULL );
CREATE INDEX "member_history_member_id_idx" ON "member_history" ("member_id");

COMMENT ON TABLE "member_history" IS 'Filled by trigger; keeps information about old names, login names and active flag of members';

COMMENT ON COLUMN "member_history"."id"    IS 'Primary key, which can be used to sort entries correctly (and time warp resistant)';
COMMENT ON COLUMN "member_history"."until" IS 'Timestamp until the name and login had been valid';


CREATE TABLE "invite_code" (
        "code"                  TEXT            PRIMARY KEY,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "used"                  TIMESTAMPTZ,
        "member_id"             INT4            UNIQUE REFERENCES "member" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
        "comment"               TEXT,
        CONSTRAINT "only_used_codes_may_refer_to_member" CHECK ("used" NOTNULL OR "member_id" ISNULL) );

COMMENT ON TABLE "invite_code" IS 'Invite codes can be used once to create a new member account.';

COMMENT ON COLUMN "invite_code"."code"      IS 'Secret code';
COMMENT ON COLUMN "invite_code"."created"   IS 'Time of creation of the secret code';
COMMENT ON COLUMN "invite_code"."used"      IS 'NULL, if not used yet, otherwise tells when this code was used to create a member account';
COMMENT ON COLUMN "invite_code"."member_id" IS 'References the member whose account was created with this code';
COMMENT ON COLUMN "invite_code"."comment"   IS 'Comment on the code, which is to be used for administrative reasons only';


CREATE TABLE "setting" (
        PRIMARY KEY ("member_id", "key"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "value"                 TEXT            NOT NULL );
CREATE INDEX "setting_key_idx" ON "setting" ("key");

COMMENT ON TABLE "setting" IS 'Place to store a frontend specific setting for members as a string';

COMMENT ON COLUMN "setting"."key" IS 'Name of the setting, preceded by a frontend specific prefix';


CREATE TABLE "setting_map" (
        PRIMARY KEY ("member_id", "key", "subkey"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "subkey"                TEXT            NOT NULL,
        "value"                 TEXT            NOT NULL );
CREATE INDEX "setting_map_key_idx" ON "setting_map" ("key");

COMMENT ON TABLE "setting_map" IS 'Place to store a frontend specific setting for members as a map of key value pairs';

COMMENT ON COLUMN "setting_map"."key"    IS 'Name of the setting, preceded by a frontend specific prefix';
COMMENT ON COLUMN "setting_map"."subkey" IS 'Key of a map entry';
COMMENT ON COLUMN "setting_map"."value"  IS 'Value of a map entry';


CREATE TABLE "member_relation_setting" (
        PRIMARY KEY ("member_id", "key", "other_member_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "other_member_id"       INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "value"                 TEXT            NOT NULL );

COMMENT ON TABLE "member_relation_setting" IS 'Place to store a frontend specific setting related to relations between members as a string';


CREATE TYPE "member_image_type" AS ENUM ('photo', 'avatar');

COMMENT ON TYPE "member_image_type" IS 'Types of images for a member';


CREATE TABLE "member_image" (
        PRIMARY KEY ("member_id", "image_type", "scaled"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "image_type"            "member_image_type",
        "scaled"                BOOLEAN,
        "content_type"          TEXT,
        "data"                  BYTEA           NOT NULL );

COMMENT ON TABLE "member_image" IS 'Images of members';

COMMENT ON COLUMN "member_image"."scaled" IS 'FALSE for original image, TRUE for scaled version of the image';


CREATE TABLE "member_count" (
        "calculated"            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
        "total_count"           INT4            NOT NULL );

COMMENT ON TABLE "member_count" IS 'Contains one row which contains the total count of active(!) members and a timestamp indicating when the total member count and area member counts were calculated';

COMMENT ON COLUMN "member_count"."calculated"  IS 'timestamp indicating when the total member count and area member counts were calculated';
COMMENT ON COLUMN "member_count"."total_count" IS 'Total count of active(!) members';


CREATE TABLE "contact" (
        PRIMARY KEY ("member_id", "other_member_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "other_member_id"       INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "public"                BOOLEAN         NOT NULL DEFAULT FALSE,
        CONSTRAINT "cant_save_yourself_as_contact"
          CHECK ("member_id" != "other_member_id") );

COMMENT ON TABLE "contact" IS 'Contact lists';

COMMENT ON COLUMN "contact"."member_id"       IS 'Member having the contact list';
COMMENT ON COLUMN "contact"."other_member_id" IS 'Member referenced in the contact list';
COMMENT ON COLUMN "contact"."public"          IS 'TRUE = display contact publically';


CREATE TABLE "session" (
        "ident"                 TEXT            PRIMARY KEY,
        "additional_secret"     TEXT,
        "expiry"                TIMESTAMPTZ     NOT NULL DEFAULT now() + '24 hours',
        "member_id"             INT8            REFERENCES "member" ("id") ON DELETE SET NULL,
        "lang"                  TEXT );
CREATE INDEX "session_expiry_idx" ON "session" ("expiry");

COMMENT ON TABLE "session" IS 'Sessions, i.e. for a web-frontend';

COMMENT ON COLUMN "session"."ident"             IS 'Secret session identifier (i.e. random string)';
COMMENT ON COLUMN "session"."additional_secret" IS 'Additional field to store a secret, which can be used against CSRF attacks';
COMMENT ON COLUMN "session"."member_id"         IS 'Reference to member, who is logged in';
COMMENT ON COLUMN "session"."lang"              IS 'Language code of the selected language';


CREATE TABLE "policy" (
        "id"                    SERIAL4         PRIMARY KEY,
        "index"                 INT4            NOT NULL,
        "active"                BOOLEAN         NOT NULL DEFAULT TRUE,
        "name"                  TEXT            NOT NULL UNIQUE,
        "description"           TEXT            NOT NULL DEFAULT '',
        "admission_time"        INTERVAL        NOT NULL,
        "discussion_time"       INTERVAL        NOT NULL,
        "verification_time"     INTERVAL        NOT NULL,
        "voting_time"           INTERVAL        NOT NULL,
        "issue_quorum_num"      INT4            NOT NULL,
        "issue_quorum_den"      INT4            NOT NULL,
        "initiative_quorum_num" INT4            NOT NULL,
        "initiative_quorum_den" INT4            NOT NULL,
        "majority_num"          INT4            NOT NULL DEFAULT 1,
        "majority_den"          INT4            NOT NULL DEFAULT 2,
        "majority_strict"       BOOLEAN         NOT NULL DEFAULT TRUE );
CREATE INDEX "policy_active_idx" ON "policy" ("active");

COMMENT ON TABLE "policy" IS 'Policies for a particular proceeding type (timelimits, quorum)';

COMMENT ON COLUMN "policy"."index"                 IS 'Determines the order in listings';
COMMENT ON COLUMN "policy"."active"                IS 'TRUE = policy can be used for new issues';
COMMENT ON COLUMN "policy"."admission_time"        IS 'Maximum time an issue stays open without being "accepted"';
COMMENT ON COLUMN "policy"."discussion_time"       IS 'Regular time until an issue is "half_frozen" after being "accepted"';
COMMENT ON COLUMN "policy"."verification_time"     IS 'Regular time until an issue is "fully_frozen" after being "half_frozen"';
COMMENT ON COLUMN "policy"."voting_time"           IS 'Time after an issue is "fully_frozen" but not "closed"';
COMMENT ON COLUMN "policy"."issue_quorum_num"      IS   'Numerator of potential supporter quorum to be reached by one initiative of an issue to be "accepted"';
COMMENT ON COLUMN "policy"."issue_quorum_den"      IS 'Denominator of potential supporter quorum to be reached by one initiative of an issue to be "accepted"';
COMMENT ON COLUMN "policy"."initiative_quorum_num" IS   'Numerator of satisfied supporter quorum  to be reached by an initiative to be "admitted" for voting';
COMMENT ON COLUMN "policy"."initiative_quorum_den" IS 'Denominator of satisfied supporter quorum to be reached by an initiative to be "admitted" for voting';
COMMENT ON COLUMN "policy"."majority_num"          IS   'Numerator of fraction of majority to be reached during voting by an initiative to be aggreed upon';
COMMENT ON COLUMN "policy"."majority_den"          IS 'Denominator of fraction of majority to be reached during voting by an initiative to be aggreed upon';
COMMENT ON COLUMN "policy"."majority_strict"       IS 'If TRUE, then the majority must be strictly greater than "majority_num"/"majority_den", otherwise it may also be equal.';


CREATE TABLE "area" (
        "id"                    SERIAL4         PRIMARY KEY,
        "active"                BOOLEAN         NOT NULL DEFAULT TRUE,
        "name"                  TEXT            NOT NULL,
        "description"           TEXT            NOT NULL DEFAULT '',
        "direct_member_count"   INT4,
        "member_weight"         INT4,
        "autoreject_weight"     INT4,
        "text_search_data"      TSVECTOR );
CREATE INDEX "area_active_idx" ON "area" ("active");
CREATE INDEX "area_text_search_data_idx" ON "area" USING gin ("text_search_data");
CREATE TRIGGER "update_text_search_data"
  BEFORE INSERT OR UPDATE ON "area"
  FOR EACH ROW EXECUTE PROCEDURE
  tsvector_update_trigger('text_search_data', 'pg_catalog.simple',
    "name", "description" );

COMMENT ON TABLE "area" IS 'Subject areas';

COMMENT ON COLUMN "area"."active"              IS 'TRUE means new issues can be created in this area';
COMMENT ON COLUMN "area"."direct_member_count" IS 'Number of active members of that area (ignoring their weight), as calculated from view "area_member_count"';
COMMENT ON COLUMN "area"."member_weight"       IS 'Same as "direct_member_count" but respecting delegations';
COMMENT ON COLUMN "area"."autoreject_weight"   IS 'Sum of weight of members using the autoreject feature';


CREATE TABLE "area_setting" (
        PRIMARY KEY ("member_id", "key", "area_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "area_id"               INT4            REFERENCES "area" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "value"                 TEXT            NOT NULL );

COMMENT ON TABLE "area_setting" IS 'Place for frontend to store area specific settings of members as strings';


CREATE TABLE "allowed_policy" (
        PRIMARY KEY ("area_id", "policy_id"),
        "area_id"               INT4            REFERENCES "area" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "policy_id"             INT4            NOT NULL REFERENCES "policy" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "default_policy"        BOOLEAN         NOT NULL DEFAULT FALSE );
CREATE UNIQUE INDEX "allowed_policy_one_default_per_area_idx" ON "allowed_policy" ("area_id") WHERE "default_policy";

COMMENT ON TABLE "allowed_policy" IS 'Selects which policies can be used in each area';

COMMENT ON COLUMN "allowed_policy"."default_policy" IS 'One policy per area can be set as default.';


CREATE TYPE "snapshot_event" AS ENUM ('periodic', 'end_of_admission', 'half_freeze', 'full_freeze');

COMMENT ON TYPE "snapshot_event" IS 'Reason for snapshots: ''periodic'' = due to periodic recalculation, ''end_of_admission'' = saved state at end of admission period, ''half_freeze'' = saved state at end of discussion period, ''full_freeze'' = saved state at end of verification period';


CREATE TABLE "issue" (
        "id"                    SERIAL4         PRIMARY KEY,
        "area_id"               INT4            NOT NULL REFERENCES "area" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "policy_id"             INT4            NOT NULL REFERENCES "policy" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "accepted"              TIMESTAMPTZ,
        "half_frozen"           TIMESTAMPTZ,
        "fully_frozen"          TIMESTAMPTZ,
        "closed"                TIMESTAMPTZ,
        "ranks_available"       BOOLEAN         NOT NULL DEFAULT FALSE,
        "admission_time"        INTERVAL        NOT NULL,
        "discussion_time"       INTERVAL        NOT NULL,
        "verification_time"     INTERVAL        NOT NULL,
        "voting_time"           INTERVAL        NOT NULL,
        "snapshot"              TIMESTAMPTZ,
        "latest_snapshot_event" "snapshot_event",
        "population"            INT4,
        "vote_now"              INT4,
        "vote_later"            INT4,
        "voter_count"           INT4,
        CONSTRAINT "valid_state" CHECK (
          ("accepted" ISNULL  AND "half_frozen" ISNULL  AND "fully_frozen" ISNULL  AND "closed" ISNULL  AND "ranks_available" = FALSE) OR
          ("accepted" ISNULL  AND "half_frozen" ISNULL  AND "fully_frozen" ISNULL  AND "closed" NOTNULL AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" ISNULL  AND "fully_frozen" ISNULL  AND "closed" ISNULL  AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" ISNULL  AND "fully_frozen" ISNULL  AND "closed" NOTNULL AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" NOTNULL AND "fully_frozen" ISNULL  AND "closed" ISNULL  AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" NOTNULL AND "fully_frozen" ISNULL  AND "closed" NOTNULL AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" NOTNULL AND "fully_frozen" NOTNULL AND "closed" ISNULL  AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" NOTNULL AND "fully_frozen" NOTNULL AND "closed" NOTNULL AND "ranks_available" = FALSE) OR
          ("accepted" NOTNULL AND "half_frozen" NOTNULL AND "fully_frozen" NOTNULL AND "closed" NOTNULL AND "ranks_available" = TRUE) ),
        CONSTRAINT "state_change_order" CHECK (
          "created"      <= "accepted" AND
          "accepted"     <= "half_frozen" AND
          "half_frozen"  <= "fully_frozen" AND
          "fully_frozen" <= "closed" ),
        CONSTRAINT "last_snapshot_on_full_freeze"
          CHECK ("snapshot" = "fully_frozen"),  -- NOTE: snapshot can be set, while frozen is NULL yet
        CONSTRAINT "freeze_requires_snapshot"
          CHECK ("fully_frozen" ISNULL OR "snapshot" NOTNULL),
        CONSTRAINT "set_both_or_none_of_snapshot_and_latest_snapshot_event"
          CHECK ("snapshot" NOTNULL = "latest_snapshot_event" NOTNULL) );
CREATE INDEX "issue_area_id_idx" ON "issue" ("area_id");
CREATE INDEX "issue_policy_id_idx" ON "issue" ("policy_id");
CREATE INDEX "issue_created_idx" ON "issue" ("created");
CREATE INDEX "issue_accepted_idx" ON "issue" ("accepted");
CREATE INDEX "issue_half_frozen_idx" ON "issue" ("half_frozen");
CREATE INDEX "issue_fully_frozen_idx" ON "issue" ("fully_frozen");
CREATE INDEX "issue_closed_idx" ON "issue" ("closed");
CREATE INDEX "issue_created_idx_open" ON "issue" ("created") WHERE "closed" ISNULL;
CREATE INDEX "issue_closed_idx_canceled" ON "issue" ("closed") WHERE "fully_frozen" ISNULL;

COMMENT ON TABLE "issue" IS 'Groups of initiatives';

COMMENT ON COLUMN "issue"."accepted"              IS 'Point in time, when one initiative of issue reached the "issue_quorum"';
COMMENT ON COLUMN "issue"."half_frozen"           IS 'Point in time, when "discussion_time" has elapsed, or members voted for voting; Frontends must ensure that for half_frozen issues a) initiatives are not revoked, b) no new drafts are created, c) no initiators are added or removed.';
COMMENT ON COLUMN "issue"."fully_frozen"          IS 'Point in time, when "verification_time" has elapsed; Frontends must ensure that for fully_frozen issues additionally to the restrictions for half_frozen issues a) initiatives are not created, b) no interest is created or removed, c) no supporters are added or removed, d) no opinions are created, changed or deleted.';
COMMENT ON COLUMN "issue"."closed"                IS 'Point in time, when "admission_time" or "voting_time" have elapsed, and issue is no longer active; Frontends must ensure that for closed issues additionally to the restrictions for half_frozen and fully_frozen issues a) no voter is added or removed to/from the direct_voter table, b) no votes are added, modified or removed.';
COMMENT ON COLUMN "issue"."ranks_available"       IS 'TRUE = ranks have been calculated';
COMMENT ON COLUMN "issue"."admission_time"        IS 'Copied from "policy" table at creation of issue';
COMMENT ON COLUMN "issue"."discussion_time"       IS 'Copied from "policy" table at creation of issue';
COMMENT ON COLUMN "issue"."verification_time"     IS 'Copied from "policy" table at creation of issue';
COMMENT ON COLUMN "issue"."voting_time"           IS 'Copied from "policy" table at creation of issue';
COMMENT ON COLUMN "issue"."snapshot"              IS 'Point in time, when snapshot tables have been updated and "population", "vote_now", "vote_later" and *_count values were precalculated';
COMMENT ON COLUMN "issue"."latest_snapshot_event" IS 'Event type of latest snapshot for issue; Can be used to select the latest snapshot data in the snapshot tables';
COMMENT ON COLUMN "issue"."population"            IS 'Sum of "weight" column in table "direct_population_snapshot"';
COMMENT ON COLUMN "issue"."vote_now"              IS 'Number of votes in favor of voting now, as calculated from table "direct_interest_snapshot"';
COMMENT ON COLUMN "issue"."vote_later"            IS 'Number of votes against voting now, as calculated from table "direct_interest_snapshot"';
COMMENT ON COLUMN "issue"."voter_count"           IS 'Total number of direct and delegating voters; This value is related to the final voting, while "population" is related to snapshots before the final voting';


CREATE TABLE "issue_setting" (
        PRIMARY KEY ("member_id", "key", "issue_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "value"                 TEXT            NOT NULL );

COMMENT ON TABLE "issue_setting" IS 'Place for frontend to store issue specific settings of members as strings';


CREATE TABLE "initiative" (
        UNIQUE ("issue_id", "id"),  -- index needed for foreign-key on table "vote"
        "issue_id"              INT4            NOT NULL REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "id"                    SERIAL4         PRIMARY KEY,
        "name"                  TEXT            NOT NULL,
        "discussion_url"        TEXT,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "revoked"               TIMESTAMPTZ,
        "suggested_initiative_id" INT4          REFERENCES "initiative" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "admitted"              BOOLEAN,
        "supporter_count"                    INT4,
        "informed_supporter_count"           INT4,
        "satisfied_supporter_count"          INT4,
        "satisfied_informed_supporter_count" INT4,
        "positive_votes"        INT4,
        "negative_votes"        INT4,
        "agreed"                BOOLEAN,
        "rank"                  INT4,
        "text_search_data"      TSVECTOR,
        CONSTRAINT "non_revoked_initiatives_cant_suggest_other"
          CHECK ("revoked" NOTNULL OR "suggested_initiative_id" ISNULL),
        CONSTRAINT "revoked_initiatives_cant_be_admitted"
          CHECK ("revoked" ISNULL OR "admitted" ISNULL),
        CONSTRAINT "non_admitted_initiatives_cant_contain_voting_results"
          CHECK (("admitted" NOTNULL AND "admitted" = TRUE) OR ("positive_votes" ISNULL AND "negative_votes" ISNULL AND "agreed" ISNULL)),
        CONSTRAINT "all_or_none_of_positive_votes_negative_votes_and_agreed_must_be_null"
          CHECK ("positive_votes" NOTNULL = "negative_votes" NOTNULL AND "positive_votes" NOTNULL = "agreed" NOTNULL),
        CONSTRAINT "non_agreed_initiatives_cant_get_a_rank"
          CHECK (("agreed" NOTNULL AND "agreed" = TRUE) OR "rank" ISNULL) );
CREATE INDEX "initiative_created_idx" ON "initiative" ("created");
CREATE INDEX "initiative_revoked_idx" ON "initiative" ("revoked");
CREATE INDEX "initiative_text_search_data_idx" ON "initiative" USING gin ("text_search_data");
CREATE TRIGGER "update_text_search_data"
  BEFORE INSERT OR UPDATE ON "initiative"
  FOR EACH ROW EXECUTE PROCEDURE
  tsvector_update_trigger('text_search_data', 'pg_catalog.simple',
    "name", "discussion_url");

COMMENT ON TABLE "initiative" IS 'Group of members publishing drafts for resolutions to be passed; Frontends must ensure that initiatives of half_frozen issues are not revoked, and that initiatives of fully_frozen or closed issues are neither revoked nor created.';

COMMENT ON COLUMN "initiative"."discussion_url" IS 'URL pointing to a discussion platform for this initiative';
COMMENT ON COLUMN "initiative"."revoked"        IS 'Point in time, when one initiator decided to revoke the initiative';
COMMENT ON COLUMN "initiative"."admitted"       IS 'TRUE, if initiative reaches the "initiative_quorum" when freezing the issue';
COMMENT ON COLUMN "initiative"."supporter_count"                    IS 'Calculated from table "direct_supporter_snapshot"';
COMMENT ON COLUMN "initiative"."informed_supporter_count"           IS 'Calculated from table "direct_supporter_snapshot"';
COMMENT ON COLUMN "initiative"."satisfied_supporter_count"          IS 'Calculated from table "direct_supporter_snapshot"';
COMMENT ON COLUMN "initiative"."satisfied_informed_supporter_count" IS 'Calculated from table "direct_supporter_snapshot"';
COMMENT ON COLUMN "initiative"."positive_votes" IS 'Calculated from table "direct_voter"';
COMMENT ON COLUMN "initiative"."negative_votes" IS 'Calculated from table "direct_voter"';
COMMENT ON COLUMN "initiative"."agreed"         IS 'TRUE, if "positive_votes"/("positive_votes"+"negative_votes") is strictly greater or greater-equal than "majority_num"/"majority_den"';
COMMENT ON COLUMN "initiative"."rank"           IS 'Rank of approved initiatives (winner is 1), calculated from table "direct_voter"';


CREATE TABLE "initiative_setting" (
        PRIMARY KEY ("member_id", "key", "initiative_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "initiative_id"         INT4            REFERENCES "initiative" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "value"                 TEXT            NOT NULL );

COMMENT ON TABLE "initiative_setting" IS 'Place for frontend to store initiative specific settings of members as strings';


CREATE TABLE "draft" (
        UNIQUE ("initiative_id", "id"),  -- index needed for foreign-key on table "supporter"
        "initiative_id"         INT4            NOT NULL REFERENCES "initiative" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "id"                    SERIAL8         PRIMARY KEY,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "author_id"             INT4            NOT NULL REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
        "formatting_engine"     TEXT,
        "content"               TEXT            NOT NULL,
        "text_search_data"      TSVECTOR );
CREATE INDEX "draft_created_idx" ON "draft" ("created");
CREATE INDEX "draft_author_id_created_idx" ON "draft" ("author_id", "created");
CREATE INDEX "draft_text_search_data_idx" ON "draft" USING gin ("text_search_data");
CREATE TRIGGER "update_text_search_data"
  BEFORE INSERT OR UPDATE ON "draft"
  FOR EACH ROW EXECUTE PROCEDURE
  tsvector_update_trigger('text_search_data', 'pg_catalog.simple', "content");

COMMENT ON TABLE "draft" IS 'Drafts of initiatives to solve issues; Frontends must ensure that new drafts for initiatives of half_frozen, fully_frozen or closed issues can''t be created.';

COMMENT ON COLUMN "draft"."formatting_engine" IS 'Allows different formatting engines (i.e. wiki formats) to be used';
COMMENT ON COLUMN "draft"."content"           IS 'Text of the draft in a format depending on the field "formatting_engine"';


CREATE TABLE "suggestion" (
        UNIQUE ("initiative_id", "id"),  -- index needed for foreign-key on table "opinion"
        "initiative_id"         INT4            NOT NULL REFERENCES "initiative" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "id"                    SERIAL8         PRIMARY KEY,
        "created"               TIMESTAMPTZ     NOT NULL DEFAULT now(),
        "author_id"             INT4            NOT NULL REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
        "name"                  TEXT            NOT NULL,
        "description"           TEXT            NOT NULL DEFAULT '',
        "text_search_data"      TSVECTOR,
        "minus2_unfulfilled_count" INT4,
        "minus2_fulfilled_count"   INT4,
        "minus1_unfulfilled_count" INT4,
        "minus1_fulfilled_count"   INT4,
        "plus1_unfulfilled_count"  INT4,
        "plus1_fulfilled_count"    INT4,
        "plus2_unfulfilled_count"  INT4,
        "plus2_fulfilled_count"    INT4 );
CREATE INDEX "suggestion_created_idx" ON "suggestion" ("created");
CREATE INDEX "suggestion_author_id_created_idx" ON "suggestion" ("author_id", "created");
CREATE INDEX "suggestion_text_search_data_idx" ON "suggestion" USING gin ("text_search_data");
CREATE TRIGGER "update_text_search_data"
  BEFORE INSERT OR UPDATE ON "suggestion"
  FOR EACH ROW EXECUTE PROCEDURE
  tsvector_update_trigger('text_search_data', 'pg_catalog.simple',
    "name", "description");

COMMENT ON TABLE "suggestion" IS 'Suggestions to initiators, to change the current draft; must not be deleted explicitly, as they vanish automatically if the last opinion is deleted';

COMMENT ON COLUMN "suggestion"."minus2_unfulfilled_count" IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."minus2_fulfilled_count"   IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."minus1_unfulfilled_count" IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."minus1_fulfilled_count"   IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."plus1_unfulfilled_count"  IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."plus1_fulfilled_count"    IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."plus2_unfulfilled_count"  IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';
COMMENT ON COLUMN "suggestion"."plus2_fulfilled_count"    IS 'Calculated from table "direct_supporter_snapshot", not requiring informed supporters';


CREATE TABLE "suggestion_setting" (
        PRIMARY KEY ("member_id", "key", "suggestion_id"),
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "key"                   TEXT            NOT NULL,
        "suggestion_id"         INT8            REFERENCES "suggestion" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "value"                 TEXT            NOT NULL );

COMMENT ON TABLE "suggestion_setting" IS 'Place for frontend to store suggestion specific settings of members as strings';


CREATE TABLE "membership" (
        PRIMARY KEY ("area_id", "member_id"),
        "area_id"               INT4            REFERENCES "area" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "autoreject"            BOOLEAN         NOT NULL DEFAULT FALSE );
CREATE INDEX "membership_member_id_idx" ON "membership" ("member_id");

COMMENT ON TABLE "membership" IS 'Interest of members in topic areas';

COMMENT ON COLUMN "membership"."autoreject" IS 'TRUE = member votes against all initiatives in case of not explicitly taking part in the voting procedure; If there exists an "interest" entry, the interest entry has precedence';


CREATE TABLE "interest" (
        PRIMARY KEY ("issue_id", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "autoreject"            BOOLEAN         NOT NULL,
        "voting_requested"      BOOLEAN );
CREATE INDEX "interest_member_id_idx" ON "interest" ("member_id");

COMMENT ON TABLE "interest" IS 'Interest of members in a particular issue; Frontends must ensure that interest for fully_frozen or closed issues is not added or removed.';

COMMENT ON COLUMN "interest"."autoreject"       IS 'TRUE = member votes against all initiatives in case of not explicitly taking part in the voting procedure';
COMMENT ON COLUMN "interest"."voting_requested" IS 'TRUE = member wants to vote now, FALSE = member wants to vote later, NULL = policy rules should apply';


CREATE TABLE "initiator" (
        PRIMARY KEY ("initiative_id", "member_id"),
        "initiative_id"         INT4            REFERENCES "initiative" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "accepted"              BOOLEAN );
CREATE INDEX "initiator_member_id_idx" ON "initiator" ("member_id");

COMMENT ON TABLE "initiator" IS 'Members who are allowed to post new drafts; Frontends must ensure that initiators are not added or removed from half_frozen, fully_frozen or closed initiatives.';

COMMENT ON COLUMN "initiator"."accepted" IS 'If "accepted" is NULL, then the member was invited to be a co-initiator, but has not answered yet. If it is TRUE, the member has accepted the invitation, if it is FALSE, the member has rejected the invitation.';


CREATE TABLE "supporter" (
        "issue_id"              INT4            NOT NULL,
        PRIMARY KEY ("initiative_id", "member_id"),
        "initiative_id"         INT4,
        "member_id"             INT4,
        "draft_id"              INT8            NOT NULL,
        FOREIGN KEY ("issue_id", "member_id") REFERENCES "interest" ("issue_id", "member_id") ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY ("initiative_id", "draft_id") REFERENCES "draft" ("initiative_id", "id") ON DELETE CASCADE ON UPDATE CASCADE );
CREATE INDEX "supporter_member_id_idx" ON "supporter" ("member_id");

COMMENT ON TABLE "supporter" IS 'Members who support an initiative (conditionally); Frontends must ensure that supporters are not added or removed from fully_frozen or closed initiatives.';

COMMENT ON COLUMN "supporter"."draft_id" IS 'Latest seen draft, defaults to current draft of the initiative (implemented by trigger "default_for_draft_id")';


CREATE TABLE "opinion" (
        "initiative_id"         INT4            NOT NULL,
        PRIMARY KEY ("suggestion_id", "member_id"),
        "suggestion_id"         INT8,
        "member_id"             INT4,
        "degree"                INT2            NOT NULL CHECK ("degree" >= -2 AND "degree" <= 2 AND "degree" != 0),
        "fulfilled"             BOOLEAN         NOT NULL DEFAULT FALSE,
        FOREIGN KEY ("initiative_id", "suggestion_id") REFERENCES "suggestion" ("initiative_id", "id") ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY ("initiative_id", "member_id") REFERENCES "supporter" ("initiative_id", "member_id") ON DELETE CASCADE ON UPDATE CASCADE );
CREATE INDEX "opinion_member_id_initiative_id_idx" ON "opinion" ("member_id", "initiative_id");

COMMENT ON TABLE "opinion" IS 'Opinion on suggestions (criticism related to initiatives); Frontends must ensure that opinions are not created modified or deleted when related to fully_frozen or closed issues.';

COMMENT ON COLUMN "opinion"."degree" IS '2 = fulfillment required for support; 1 = fulfillment desired; -1 = fulfillment unwanted; -2 = fulfillment cancels support';


CREATE TYPE "delegation_scope" AS ENUM ('global', 'area', 'issue');

COMMENT ON TYPE "delegation_scope" IS 'Scope for delegations: ''global'', ''area'', or ''issue'' (order is relevant)';


CREATE TABLE "delegation" (
        "id"                    SERIAL8         PRIMARY KEY,
        "truster_id"            INT4            NOT NULL REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "trustee_id"            INT4            NOT NULL REFERENCES "member" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "scope"              "delegation_scope" NOT NULL,
        "area_id"               INT4            REFERENCES "area" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT "cant_delegate_to_yourself" CHECK ("truster_id" != "trustee_id"),
        CONSTRAINT "area_id_and_issue_id_set_according_to_scope" CHECK (
          ("scope" = 'global' AND "area_id" ISNULL  AND "issue_id" ISNULL ) OR
          ("scope" = 'area'   AND "area_id" NOTNULL AND "issue_id" ISNULL ) OR
          ("scope" = 'issue'  AND "area_id" ISNULL  AND "issue_id" NOTNULL) ),
        UNIQUE ("area_id", "truster_id", "trustee_id"),
        UNIQUE ("issue_id", "truster_id", "trustee_id") );
CREATE UNIQUE INDEX "delegation_global_truster_id_trustee_id_unique_idx"
  ON "delegation" ("truster_id", "trustee_id") WHERE "scope" = 'global';
CREATE INDEX "delegation_truster_id_idx" ON "delegation" ("truster_id");
CREATE INDEX "delegation_trustee_id_idx" ON "delegation" ("trustee_id");

COMMENT ON TABLE "delegation" IS 'Delegation of vote-weight to other members';

COMMENT ON COLUMN "delegation"."area_id"  IS 'Reference to area, if delegation is area-wide, otherwise NULL';
COMMENT ON COLUMN "delegation"."issue_id" IS 'Reference to issue, if delegation is issue-wide, otherwise NULL';


CREATE TABLE "direct_population_snapshot" (
        PRIMARY KEY ("issue_id", "event", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "event"                 "snapshot_event",
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4 );
CREATE INDEX "direct_population_snapshot_member_id_idx" ON "direct_population_snapshot" ("member_id");

COMMENT ON TABLE "direct_population_snapshot" IS 'Snapshot of active members having either a "membership" in the "area" or an "interest" in the "issue"';

COMMENT ON COLUMN "direct_population_snapshot"."event"           IS 'Reason for snapshot, see "snapshot_event" type for details';
COMMENT ON COLUMN "direct_population_snapshot"."weight"          IS 'Weight of member (1 or higher) according to "delegating_population_snapshot"';


CREATE TABLE "delegating_population_snapshot" (
        PRIMARY KEY ("issue_id", "event", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "event"                "snapshot_event",
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4,
        "scope"              "delegation_scope" NOT NULL,
        "delegate_member_ids"   INT4[]          NOT NULL );
CREATE INDEX "delegating_population_snapshot_member_id_idx" ON "delegating_population_snapshot" ("member_id");

COMMENT ON TABLE "direct_population_snapshot" IS 'Delegations increasing the weight of entries in the "direct_population_snapshot" table';

COMMENT ON COLUMN "delegating_population_snapshot"."event"               IS 'Reason for snapshot, see "snapshot_event" type for details';
COMMENT ON COLUMN "delegating_population_snapshot"."member_id"           IS 'Delegating member';
COMMENT ON COLUMN "delegating_population_snapshot"."weight"              IS 'Intermediate weight';
COMMENT ON COLUMN "delegating_population_snapshot"."delegate_member_ids" IS 'Chain of members who act as delegates; last entry referes to "member_id" column of table "direct_population_snapshot"';


CREATE TABLE "direct_interest_snapshot" (
        PRIMARY KEY ("issue_id", "event", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "event"                 "snapshot_event",
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4,
        "voting_requested"      BOOLEAN );
CREATE INDEX "direct_interest_snapshot_member_id_idx" ON "direct_interest_snapshot" ("member_id");

COMMENT ON TABLE "direct_interest_snapshot" IS 'Snapshot of active members having an "interest" in the "issue"';

COMMENT ON COLUMN "direct_interest_snapshot"."event"            IS 'Reason for snapshot, see "snapshot_event" type for details';
COMMENT ON COLUMN "direct_interest_snapshot"."weight"           IS 'Weight of member (1 or higher) according to "delegating_interest_snapshot"';
COMMENT ON COLUMN "direct_interest_snapshot"."voting_requested" IS 'Copied from column "voting_requested" of table "interest"';


CREATE TABLE "delegating_interest_snapshot" (
        PRIMARY KEY ("issue_id", "event", "member_id"),
        "issue_id"         INT4                 REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "event"                "snapshot_event",
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4,
        "scope"              "delegation_scope" NOT NULL,
        "delegate_member_ids"   INT4[]          NOT NULL );
CREATE INDEX "delegating_interest_snapshot_member_id_idx" ON "delegating_interest_snapshot" ("member_id");

COMMENT ON TABLE "delegating_interest_snapshot" IS 'Delegations increasing the weight of entries in the "direct_interest_snapshot" table';

COMMENT ON COLUMN "delegating_interest_snapshot"."event"               IS 'Reason for snapshot, see "snapshot_event" type for details';
COMMENT ON COLUMN "delegating_interest_snapshot"."member_id"           IS 'Delegating member';
COMMENT ON COLUMN "delegating_interest_snapshot"."weight"              IS 'Intermediate weight';
COMMENT ON COLUMN "delegating_interest_snapshot"."delegate_member_ids" IS 'Chain of members who act as delegates; last entry referes to "member_id" column of table "direct_interest_snapshot"';


CREATE TABLE "direct_supporter_snapshot" (
        "issue_id"              INT4            NOT NULL,
        PRIMARY KEY ("initiative_id", "event", "member_id"),
        "initiative_id"         INT4,
        "event"                 "snapshot_event",
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "informed"              BOOLEAN         NOT NULL,
        "satisfied"             BOOLEAN         NOT NULL,
        FOREIGN KEY ("issue_id", "initiative_id") REFERENCES "initiative" ("issue_id", "id") ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY ("issue_id", "event", "member_id") REFERENCES "direct_interest_snapshot" ("issue_id", "event", "member_id") ON DELETE CASCADE ON UPDATE CASCADE );
CREATE INDEX "direct_supporter_snapshot_member_id_idx" ON "direct_supporter_snapshot" ("member_id");

COMMENT ON TABLE "direct_supporter_snapshot" IS 'Snapshot of supporters of initiatives (weight is stored in "direct_interest_snapshot")';

COMMENT ON COLUMN "direct_supporter_snapshot"."event"     IS 'Reason for snapshot, see "snapshot_event" type for details';
COMMENT ON COLUMN "direct_supporter_snapshot"."informed"  IS 'Supporter has seen the latest draft of the initiative';
COMMENT ON COLUMN "direct_supporter_snapshot"."satisfied" IS 'Supporter has no "critical_opinion"s';


CREATE TABLE "direct_voter" (
        PRIMARY KEY ("issue_id", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4,
        "autoreject"            BOOLEAN         NOT NULL DEFAULT FALSE );
CREATE INDEX "direct_voter_member_id_idx" ON "direct_voter" ("member_id");

COMMENT ON TABLE "direct_voter" IS 'Members having directly voted for/against initiatives of an issue; Frontends must ensure that no voters are added or removed to/from this table when the issue has been closed.';

COMMENT ON COLUMN "direct_voter"."weight"     IS 'Weight of member (1 or higher) according to "delegating_voter" table';
COMMENT ON COLUMN "direct_voter"."autoreject" IS 'Votes were inserted due to "autoreject" feature';


CREATE TABLE "delegating_voter" (
        PRIMARY KEY ("issue_id", "member_id"),
        "issue_id"              INT4            REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "member_id"             INT4            REFERENCES "member" ("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
        "weight"                INT4,
        "scope"              "delegation_scope" NOT NULL,
        "delegate_member_ids"   INT4[]          NOT NULL );
CREATE INDEX "delegating_voter_member_id_idx" ON "delegating_voter" ("member_id");

COMMENT ON TABLE "delegating_voter" IS 'Delegations increasing the weight of entries in the "direct_voter" table';

COMMENT ON COLUMN "delegating_voter"."member_id"           IS 'Delegating member';
COMMENT ON COLUMN "delegating_voter"."weight"              IS 'Intermediate weight';
COMMENT ON COLUMN "delegating_voter"."delegate_member_ids" IS 'Chain of members who act as delegates; last entry referes to "member_id" column of table "direct_voter"';


CREATE TABLE "vote" (
        "issue_id"              INT4            NOT NULL,
        PRIMARY KEY ("initiative_id", "member_id"),
        "initiative_id"         INT4,
        "member_id"             INT4,
        "grade"                 INT4,
        FOREIGN KEY ("issue_id", "initiative_id") REFERENCES "initiative" ("issue_id", "id") ON DELETE CASCADE ON UPDATE CASCADE,
        FOREIGN KEY ("issue_id", "member_id") REFERENCES "direct_voter" ("issue_id", "member_id") ON DELETE CASCADE ON UPDATE CASCADE );
CREATE INDEX "vote_member_id_idx" ON "vote" ("member_id");

COMMENT ON TABLE "vote" IS 'Manual and delegated votes without abstentions; Frontends must ensure that no votes are added modified or removed when the issue has been closed.';

COMMENT ON COLUMN "vote"."grade" IS 'Values smaller than zero mean reject, values greater than zero mean acceptance, zero or missing row means abstention. Preferences are expressed by different positive or negative numbers.';


CREATE TABLE "contingent" (
        "time_frame"            INTERVAL        PRIMARY KEY,
        "text_entry_limit"      INT4,
        "initiative_limit"      INT4 );

COMMENT ON TABLE "contingent" IS 'Amount of text entries or initiatives a user may create within a given time frame. Only one row needs to be fulfilled for a member to be allowed to post. This table must not be empty.';

COMMENT ON COLUMN "contingent"."text_entry_limit" IS 'Number of new drafts or suggestions to be submitted by each member within the given time frame';
COMMENT ON COLUMN "contingent"."initiative_limit" IS 'Number of new initiatives to be opened by each member within a given time frame';



--------------------------------
-- Writing of history entries --
--------------------------------

CREATE FUNCTION "write_member_history_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF
        ( NEW."login" NOTNULL AND OLD."login" NOTNULL AND
          NEW."login" != OLD."login" ) OR
        ( NEW."login" NOTNULL AND OLD."login" ISNULL ) OR
        ( NEW."login" ISNULL AND OLD."login" NOTNULL ) OR
        NEW."active" != OLD."active" OR
        NEW."name"   != OLD."name"
      THEN
        INSERT INTO "member_history"
          ("member_id", "login", "active", "name")
          VALUES (NEW."id", OLD."login", OLD."active", OLD."name");
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE TRIGGER "write_member_history"
  AFTER UPDATE ON "member" FOR EACH ROW EXECUTE PROCEDURE
  "write_member_history_trigger"();

COMMENT ON FUNCTION "write_member_history_trigger"()  IS 'Implementation of trigger "write_member_history" on table "member"';
COMMENT ON TRIGGER "write_member_history" ON "member" IS 'When changing name or login of a member, create a history entry in "member_history" table';



----------------------------
-- Additional constraints --
----------------------------


CREATE FUNCTION "issue_requires_first_initiative_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT NULL FROM "initiative" WHERE "issue_id" = NEW."id"
      ) THEN
        --RAISE 'Cannot create issue without an initial initiative.' USING
        --  ERRCODE = 'integrity_constraint_violation',
        --  HINT    = 'Create issue, initiative, and draft within the same transaction.';
        RAISE EXCEPTION 'Cannot create issue without an initial initiative.';
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "issue_requires_first_initiative"
  AFTER INSERT OR UPDATE ON "issue" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "issue_requires_first_initiative_trigger"();

COMMENT ON FUNCTION "issue_requires_first_initiative_trigger"() IS 'Implementation of trigger "issue_requires_first_initiative" on table "issue"';
COMMENT ON TRIGGER "issue_requires_first_initiative" ON "issue" IS 'Ensure that new issues have at least one initiative';


CREATE FUNCTION "last_initiative_deletes_issue_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "reference_lost" BOOLEAN;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        "reference_lost" := TRUE;
      ELSE
        "reference_lost" := NEW."issue_id" != OLD."issue_id";
      END IF;
      IF
        "reference_lost" AND NOT EXISTS (
          SELECT NULL FROM "initiative" WHERE "issue_id" = OLD."issue_id"
        )
      THEN
        DELETE FROM "issue" WHERE "id" = OLD."issue_id";
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "last_initiative_deletes_issue"
  AFTER UPDATE OR DELETE ON "initiative" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "last_initiative_deletes_issue_trigger"();

COMMENT ON FUNCTION "last_initiative_deletes_issue_trigger"()      IS 'Implementation of trigger "last_initiative_deletes_issue" on table "initiative"';
COMMENT ON TRIGGER "last_initiative_deletes_issue" ON "initiative" IS 'Removing the last initiative of an issue deletes the issue';


CREATE FUNCTION "initiative_requires_first_draft_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT NULL FROM "draft" WHERE "initiative_id" = NEW."id"
      ) THEN
        --RAISE 'Cannot create initiative without an initial draft.' USING
        --  ERRCODE = 'integrity_constraint_violation',
        --  HINT    = 'Create issue, initiative and draft within the same transaction.';
        RAISE EXCEPTION 'Cannot create initiative without an initial draft.';
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "initiative_requires_first_draft"
  AFTER INSERT OR UPDATE ON "initiative" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "initiative_requires_first_draft_trigger"();

COMMENT ON FUNCTION "initiative_requires_first_draft_trigger"()      IS 'Implementation of trigger "initiative_requires_first_draft" on table "initiative"';
COMMENT ON TRIGGER "initiative_requires_first_draft" ON "initiative" IS 'Ensure that new initiatives have at least one draft';


CREATE FUNCTION "last_draft_deletes_initiative_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "reference_lost" BOOLEAN;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        "reference_lost" := TRUE;
      ELSE
        "reference_lost" := NEW."initiative_id" != OLD."initiative_id";
      END IF;
      IF
        "reference_lost" AND NOT EXISTS (
          SELECT NULL FROM "draft" WHERE "initiative_id" = OLD."initiative_id"
        )
      THEN
        DELETE FROM "initiative" WHERE "id" = OLD."initiative_id";
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "last_draft_deletes_initiative"
  AFTER UPDATE OR DELETE ON "draft" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "last_draft_deletes_initiative_trigger"();

COMMENT ON FUNCTION "last_draft_deletes_initiative_trigger"() IS 'Implementation of trigger "last_draft_deletes_initiative" on table "draft"';
COMMENT ON TRIGGER "last_draft_deletes_initiative" ON "draft" IS 'Removing the last draft of an initiative deletes the initiative';


CREATE FUNCTION "suggestion_requires_first_opinion_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT NULL FROM "opinion" WHERE "suggestion_id" = NEW."id"
      ) THEN
        RAISE EXCEPTION 'Cannot create a suggestion without an opinion.';
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "suggestion_requires_first_opinion"
  AFTER INSERT OR UPDATE ON "suggestion" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "suggestion_requires_first_opinion_trigger"();

COMMENT ON FUNCTION "suggestion_requires_first_opinion_trigger"()      IS 'Implementation of trigger "suggestion_requires_first_opinion" on table "suggestion"';
COMMENT ON TRIGGER "suggestion_requires_first_opinion" ON "suggestion" IS 'Ensure that new suggestions have at least one opinion';


CREATE FUNCTION "last_opinion_deletes_suggestion_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "reference_lost" BOOLEAN;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        "reference_lost" := TRUE;
      ELSE
        "reference_lost" := NEW."suggestion_id" != OLD."suggestion_id";
      END IF;
      IF
        "reference_lost" AND NOT EXISTS (
          SELECT NULL FROM "opinion" WHERE "suggestion_id" = OLD."suggestion_id"
        )
      THEN
        DELETE FROM "suggestion" WHERE "id" = OLD."suggestion_id";
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE CONSTRAINT TRIGGER "last_opinion_deletes_suggestion"
  AFTER UPDATE OR DELETE ON "opinion" DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE PROCEDURE
  "last_opinion_deletes_suggestion_trigger"();

COMMENT ON FUNCTION "last_opinion_deletes_suggestion_trigger"()   IS 'Implementation of trigger "last_opinion_deletes_suggestion" on table "opinion"';
COMMENT ON TRIGGER "last_opinion_deletes_suggestion" ON "opinion" IS 'Removing the last opinion of a suggestion deletes the suggestion';



---------------------------------------------------------------
-- Ensure that votes are not modified when issues are frozen --
---------------------------------------------------------------

-- NOTE: Frontends should ensure this anyway, but in case of programming
-- errors the following triggers ensure data integrity.


CREATE FUNCTION "forbid_changes_on_closed_issue_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_id_v" "issue"."id"%TYPE;
      "issue_row"  "issue"%ROWTYPE;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        "issue_id_v" := OLD."issue_id";
      ELSE
        "issue_id_v" := NEW."issue_id";
      END IF;
      SELECT INTO "issue_row" * FROM "issue"
        WHERE "id" = "issue_id_v" FOR SHARE;
      IF "issue_row"."closed" NOTNULL THEN
        RAISE EXCEPTION 'Tried to modify data belonging to a closed issue.';
      END IF;
      RETURN NULL;
    END;
  $$;

CREATE TRIGGER "forbid_changes_on_closed_issue"
  AFTER INSERT OR UPDATE OR DELETE ON "direct_voter"
  FOR EACH ROW EXECUTE PROCEDURE
  "forbid_changes_on_closed_issue_trigger"();

CREATE TRIGGER "forbid_changes_on_closed_issue"
  AFTER INSERT OR UPDATE OR DELETE ON "delegating_voter"
  FOR EACH ROW EXECUTE PROCEDURE
  "forbid_changes_on_closed_issue_trigger"();

CREATE TRIGGER "forbid_changes_on_closed_issue"
  AFTER INSERT OR UPDATE OR DELETE ON "vote"
  FOR EACH ROW EXECUTE PROCEDURE
  "forbid_changes_on_closed_issue_trigger"();

COMMENT ON FUNCTION "forbid_changes_on_closed_issue_trigger"()            IS 'Implementation of triggers "forbid_changes_on_closed_issue" on tables "direct_voter", "delegating_voter" and "vote"';
COMMENT ON TRIGGER "forbid_changes_on_closed_issue" ON "direct_voter"     IS 'Ensures that frontends can''t tamper with votings of closed issues, in case of programming errors';
COMMENT ON TRIGGER "forbid_changes_on_closed_issue" ON "delegating_voter" IS 'Ensures that frontends can''t tamper with votings of closed issues, in case of programming errors';
COMMENT ON TRIGGER "forbid_changes_on_closed_issue" ON "vote"             IS 'Ensures that frontends can''t tamper with votings of closed issues, in case of programming errors';



--------------------------------------------------------------------
-- Auto-retrieval of fields only needed for referential integrity --
--------------------------------------------------------------------


CREATE FUNCTION "autofill_issue_id_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NEW."issue_id" ISNULL THEN
        SELECT "issue_id" INTO NEW."issue_id"
          FROM "initiative" WHERE "id" = NEW."initiative_id";
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "autofill_issue_id" BEFORE INSERT ON "supporter"
  FOR EACH ROW EXECUTE PROCEDURE "autofill_issue_id_trigger"();

CREATE TRIGGER "autofill_issue_id" BEFORE INSERT ON "vote"
  FOR EACH ROW EXECUTE PROCEDURE "autofill_issue_id_trigger"();

COMMENT ON FUNCTION "autofill_issue_id_trigger"()     IS 'Implementation of triggers "autofill_issue_id" on tables "supporter" and "vote"';
COMMENT ON TRIGGER "autofill_issue_id" ON "supporter" IS 'Set "issue_id" field automatically, if NULL';
COMMENT ON TRIGGER "autofill_issue_id" ON "vote"      IS 'Set "issue_id" field automatically, if NULL';


CREATE FUNCTION "autofill_initiative_id_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NEW."initiative_id" ISNULL THEN
        SELECT "initiative_id" INTO NEW."initiative_id"
          FROM "suggestion" WHERE "id" = NEW."suggestion_id";
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "autofill_initiative_id" BEFORE INSERT ON "opinion"
  FOR EACH ROW EXECUTE PROCEDURE "autofill_initiative_id_trigger"();

COMMENT ON FUNCTION "autofill_initiative_id_trigger"()   IS 'Implementation of trigger "autofill_initiative_id" on table "opinion"';
COMMENT ON TRIGGER "autofill_initiative_id" ON "opinion" IS 'Set "initiative_id" field automatically, if NULL';



-----------------------------------------------------
-- Automatic calculation of certain default values --
-----------------------------------------------------


CREATE FUNCTION "copy_timings_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "policy_row" "policy"%ROWTYPE;
    BEGIN
      SELECT * INTO "policy_row" FROM "policy"
        WHERE "id" = NEW."policy_id";
      IF NEW."admission_time" ISNULL THEN
        NEW."admission_time" := "policy_row"."admission_time";
      END IF;
      IF NEW."discussion_time" ISNULL THEN
        NEW."discussion_time" := "policy_row"."discussion_time";
      END IF;
      IF NEW."verification_time" ISNULL THEN
        NEW."verification_time" := "policy_row"."verification_time";
      END IF;
      IF NEW."voting_time" ISNULL THEN
        NEW."voting_time" := "policy_row"."voting_time";
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "copy_timings" BEFORE INSERT OR UPDATE ON "issue"
  FOR EACH ROW EXECUTE PROCEDURE "copy_timings_trigger"();

COMMENT ON FUNCTION "copy_timings_trigger"() IS 'Implementation of trigger "copy_timings" on table "issue"';
COMMENT ON TRIGGER "copy_timings" ON "issue" IS 'If timing fields are NULL, copy values from policy.';


CREATE FUNCTION "copy_autoreject_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NEW."autoreject" ISNULL THEN
        SELECT "membership"."autoreject" INTO NEW."autoreject"
          FROM "issue" JOIN "membership"
          ON "issue"."area_id" = "membership"."area_id"
          WHERE "issue"."id" = NEW."issue_id"
          AND "membership"."member_id" = NEW."member_id";
      END IF;
      IF NEW."autoreject" ISNULL THEN 
        NEW."autoreject" := FALSE;
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "copy_autoreject" BEFORE INSERT OR UPDATE ON "interest"
  FOR EACH ROW EXECUTE PROCEDURE "copy_autoreject_trigger"();

COMMENT ON FUNCTION "copy_autoreject_trigger"()    IS 'Implementation of trigger "copy_autoreject" on table "interest"';
COMMENT ON TRIGGER "copy_autoreject" ON "interest" IS 'If "autoreject" is NULL, then copy it from the area setting, or set to FALSE, if no membership existent';


CREATE FUNCTION "supporter_default_for_draft_id_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NEW."draft_id" ISNULL THEN
        SELECT "id" INTO NEW."draft_id" FROM "current_draft"
          WHERE "initiative_id" = NEW."initiative_id";
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "default_for_draft_id" BEFORE INSERT OR UPDATE ON "supporter"
  FOR EACH ROW EXECUTE PROCEDURE "supporter_default_for_draft_id_trigger"();

COMMENT ON FUNCTION "supporter_default_for_draft_id_trigger"() IS 'Implementation of trigger "default_for_draft" on table "supporter"';
COMMENT ON TRIGGER "default_for_draft_id" ON "supporter"       IS 'If "draft_id" is NULL, then use the current draft of the initiative as default';



----------------------------------------
-- Automatic creation of dependencies --
----------------------------------------


CREATE FUNCTION "autocreate_interest_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT NULL FROM "initiative" JOIN "interest"
        ON "initiative"."issue_id" = "interest"."issue_id"
        WHERE "initiative"."id" = NEW."initiative_id"
        AND "interest"."member_id" = NEW."member_id"
      ) THEN
        BEGIN
          INSERT INTO "interest" ("issue_id", "member_id")
            SELECT "issue_id", NEW."member_id"
            FROM "initiative" WHERE "id" = NEW."initiative_id";
        EXCEPTION WHEN unique_violation THEN END;
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "autocreate_interest" BEFORE INSERT ON "supporter"
  FOR EACH ROW EXECUTE PROCEDURE "autocreate_interest_trigger"();

COMMENT ON FUNCTION "autocreate_interest_trigger"()     IS 'Implementation of trigger "autocreate_interest" on table "supporter"';
COMMENT ON TRIGGER "autocreate_interest" ON "supporter" IS 'Supporting an initiative implies interest in the issue, thus automatically creates an entry in the "interest" table';


CREATE FUNCTION "autocreate_supporter_trigger"()
  RETURNS TRIGGER
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT NULL FROM "suggestion" JOIN "supporter"
        ON "suggestion"."initiative_id" = "supporter"."initiative_id"
        WHERE "suggestion"."id" = NEW."suggestion_id"
        AND "supporter"."member_id" = NEW."member_id"
      ) THEN
        BEGIN
          INSERT INTO "supporter" ("initiative_id", "member_id")
            SELECT "initiative_id", NEW."member_id"
            FROM "suggestion" WHERE "id" = NEW."suggestion_id";
        EXCEPTION WHEN unique_violation THEN END;
      END IF;
      RETURN NEW;
    END;
  $$;

CREATE TRIGGER "autocreate_supporter" BEFORE INSERT ON "opinion"
  FOR EACH ROW EXECUTE PROCEDURE "autocreate_supporter_trigger"();

COMMENT ON FUNCTION "autocreate_supporter_trigger"()   IS 'Implementation of trigger "autocreate_supporter" on table "opinion"';
COMMENT ON TRIGGER "autocreate_supporter" ON "opinion" IS 'Opinions can only be added for supported initiatives. This trigger automatrically creates an entry in the "supporter" table, if not existent yet.';



------------------------------------------
-- Views and helper functions for views --
------------------------------------------


CREATE VIEW "global_delegation" AS
  SELECT
    "delegation"."id",
    "delegation"."truster_id",
    "delegation"."trustee_id"
  FROM "delegation" JOIN "member"
  ON "delegation"."trustee_id" = "member"."id"
  WHERE "delegation"."scope" = 'global' AND "member"."active";

COMMENT ON VIEW "global_delegation" IS 'Global delegations to active members';


CREATE VIEW "area_delegation" AS
  SELECT "subquery".* FROM (
    SELECT DISTINCT ON ("area"."id", "delegation"."truster_id")
      "area"."id" AS "area_id",
      "delegation"."id",
      "delegation"."truster_id",
      "delegation"."trustee_id",
      "delegation"."scope"
    FROM "area" JOIN "delegation"
    ON "delegation"."scope" = 'global'
    OR "delegation"."area_id" = "area"."id"
    ORDER BY
      "area"."id",
      "delegation"."truster_id",
      "delegation"."scope" DESC
  ) AS "subquery"
  JOIN "member" ON "subquery"."trustee_id" = "member"."id"
  WHERE "member"."active";

COMMENT ON VIEW "area_delegation" IS 'Active delegations for areas';


CREATE VIEW "issue_delegation" AS
  SELECT "subquery".* FROM (
    SELECT DISTINCT ON ("issue"."id", "delegation"."truster_id")
      "issue"."id"  AS "issue_id",
      "delegation"."id",
      "delegation"."truster_id",
      "delegation"."trustee_id",
      "delegation"."scope"
    FROM "issue" JOIN "delegation"
    ON "delegation"."scope" = 'global'
    OR "delegation"."area_id" = "issue"."area_id"
    OR "delegation"."issue_id" = "issue"."id"
    ORDER BY
      "issue"."id",
      "delegation"."truster_id",
      "delegation"."scope" DESC
  ) AS "subquery"
  JOIN "member" ON "subquery"."trustee_id" = "member"."id"
  WHERE "member"."active";

COMMENT ON VIEW "issue_delegation" IS 'Active delegations for issues';


CREATE FUNCTION "membership_weight_with_skipping"
  ( "area_id_p"         "area"."id"%TYPE,
    "member_id_p"       "member"."id"%TYPE,
    "skip_member_ids_p" INT4[] )  -- "member"."id"%TYPE[]
  RETURNS INT4
  LANGUAGE 'plpgsql' STABLE AS $$
    DECLARE
      "sum_v"          INT4;
      "delegation_row" "area_delegation"%ROWTYPE;
    BEGIN
      "sum_v" := 1;
      FOR "delegation_row" IN
        SELECT "area_delegation".*
        FROM "area_delegation" LEFT JOIN "membership"
        ON "membership"."area_id" = "area_id_p"
        AND "membership"."member_id" = "area_delegation"."truster_id"
        WHERE "area_delegation"."area_id" = "area_id_p"
        AND "area_delegation"."trustee_id" = "member_id_p"
        AND "membership"."member_id" ISNULL
      LOOP
        IF NOT
          "skip_member_ids_p" @> ARRAY["delegation_row"."truster_id"]
        THEN
          "sum_v" := "sum_v" + "membership_weight_with_skipping"(
            "area_id_p",
            "delegation_row"."truster_id",
            "skip_member_ids_p" || "delegation_row"."truster_id"
          );
        END IF;
      END LOOP;
      RETURN "sum_v";
    END;
  $$;

COMMENT ON FUNCTION "membership_weight_with_skipping"
  ( "area"."id"%TYPE,
    "member"."id"%TYPE,
    INT4[] )
  IS 'Helper function for "membership_weight" function';


CREATE FUNCTION "membership_weight"
  ( "area_id_p"         "area"."id"%TYPE,
    "member_id_p"       "member"."id"%TYPE )  -- "member"."id"%TYPE[]
  RETURNS INT4
  LANGUAGE 'plpgsql' STABLE AS $$
    BEGIN
      RETURN "membership_weight_with_skipping"(
        "area_id_p",
        "member_id_p",
        ARRAY["member_id_p"]
      );
    END;
  $$;

COMMENT ON FUNCTION "membership_weight"
  ( "area"."id"%TYPE,
    "member"."id"%TYPE )
  IS 'Calculates the potential voting weight of a member in a given area';


CREATE VIEW "member_count_view" AS
  SELECT count(1) AS "total_count" FROM "member" WHERE "active";

COMMENT ON VIEW "member_count_view" IS 'View used to update "member_count" table';


CREATE VIEW "area_member_count" AS
  SELECT
    "area"."id" AS "area_id",
    count("member"."id") AS "direct_member_count",
    coalesce(
      sum(
        CASE WHEN "member"."id" NOTNULL THEN
          "membership_weight"("area"."id", "member"."id")
        ELSE 0 END
      )
    ) AS "member_weight",
    coalesce(
      sum(
        CASE WHEN "member"."id" NOTNULL AND "membership"."autoreject" THEN
          "membership_weight"("area"."id", "member"."id")
        ELSE 0 END
      )
    ) AS "autoreject_weight"
  FROM "area"
  LEFT JOIN "membership"
  ON "area"."id" = "membership"."area_id"
  LEFT JOIN "member"
  ON "membership"."member_id" = "member"."id"
  AND "member"."active"
  GROUP BY "area"."id";

COMMENT ON VIEW "area_member_count" IS 'View used to update "member_count" column of table "area"';


CREATE VIEW "opening_draft" AS
  SELECT "draft".* FROM (
    SELECT
      "initiative"."id" AS "initiative_id",
      min("draft"."id") AS "draft_id"
    FROM "initiative" JOIN "draft"
    ON "initiative"."id" = "draft"."initiative_id"
    GROUP BY "initiative"."id"
  ) AS "subquery"
  JOIN "draft" ON "subquery"."draft_id" = "draft"."id";

COMMENT ON VIEW "opening_draft" IS 'First drafts of all initiatives';


CREATE VIEW "current_draft" AS
  SELECT "draft".* FROM (
    SELECT
      "initiative"."id" AS "initiative_id",
      max("draft"."id") AS "draft_id"
    FROM "initiative" JOIN "draft"
    ON "initiative"."id" = "draft"."initiative_id"
    GROUP BY "initiative"."id"
  ) AS "subquery"
  JOIN "draft" ON "subquery"."draft_id" = "draft"."id";

COMMENT ON VIEW "current_draft" IS 'All latest drafts for each initiative';


CREATE VIEW "critical_opinion" AS
  SELECT * FROM "opinion"
  WHERE ("degree" = 2 AND "fulfilled" = FALSE)
  OR ("degree" = -2 AND "fulfilled" = TRUE);

COMMENT ON VIEW "critical_opinion" IS 'Opinions currently causing dissatisfaction';


CREATE VIEW "battle" AS
  SELECT
    "issue"."id" AS "issue_id",
    "winning_initiative"."id" AS "winning_initiative_id",
    "losing_initiative"."id" AS "losing_initiative_id",
    sum(
      CASE WHEN
        coalesce("better_vote"."grade", 0) >
        coalesce("worse_vote"."grade", 0)
      THEN "direct_voter"."weight" ELSE 0 END
    ) AS "count"
  FROM "issue"
  LEFT JOIN "direct_voter"
  ON "issue"."id" = "direct_voter"."issue_id"
  JOIN "initiative" AS "winning_initiative"
    ON "issue"."id" = "winning_initiative"."issue_id"
    AND "winning_initiative"."agreed"
  JOIN "initiative" AS "losing_initiative"
    ON "issue"."id" = "losing_initiative"."issue_id"
    AND "losing_initiative"."agreed"
  LEFT JOIN "vote" AS "better_vote"
    ON "direct_voter"."member_id" = "better_vote"."member_id"
    AND "winning_initiative"."id" = "better_vote"."initiative_id"
  LEFT JOIN "vote" AS "worse_vote"
    ON "direct_voter"."member_id" = "worse_vote"."member_id"
    AND "losing_initiative"."id" = "worse_vote"."initiative_id"
  WHERE
    "winning_initiative"."id" != "losing_initiative"."id"
  GROUP BY
    "issue"."id",
    "winning_initiative"."id",
    "losing_initiative"."id";

COMMENT ON VIEW "battle" IS 'Number of members preferring one initiative over another';


CREATE VIEW "expired_session" AS
  SELECT * FROM "session" WHERE now() > "expiry";

CREATE RULE "delete" AS ON DELETE TO "expired_session" DO INSTEAD
  DELETE FROM "session" WHERE "ident" = OLD."ident";

COMMENT ON VIEW "expired_session" IS 'View containing all expired sessions where DELETE is possible';
COMMENT ON RULE "delete" ON "expired_session" IS 'Rule allowing DELETE on rows in "expired_session" view, i.e. DELETE FROM "expired_session"';


CREATE VIEW "open_issue" AS
  SELECT * FROM "issue" WHERE "closed" ISNULL;

COMMENT ON VIEW "open_issue" IS 'All open issues';


CREATE VIEW "issue_with_ranks_missing" AS
  SELECT * FROM "issue"
  WHERE "fully_frozen" NOTNULL
  AND "closed" NOTNULL
  AND "ranks_available" = FALSE;

COMMENT ON VIEW "issue_with_ranks_missing" IS 'Issues where voting was finished, but no ranks have been calculated yet';


CREATE VIEW "member_contingent" AS
  SELECT
    "member"."id" AS "member_id",
    "contingent"."time_frame",
    CASE WHEN "contingent"."text_entry_limit" NOTNULL THEN
      (
        SELECT count(1) FROM "draft"
        WHERE "draft"."author_id" = "member"."id"
        AND "draft"."created" > now() - "contingent"."time_frame"
      ) + (
        SELECT count(1) FROM "suggestion"
        WHERE "suggestion"."author_id" = "member"."id"
        AND "suggestion"."created" > now() - "contingent"."time_frame"
      )
    ELSE NULL END AS "text_entry_count",
    "contingent"."text_entry_limit",
    CASE WHEN "contingent"."initiative_limit" NOTNULL THEN (
      SELECT count(1) FROM "opening_draft"
      WHERE "opening_draft"."author_id" = "member"."id"
      AND "opening_draft"."created" > now() - "contingent"."time_frame"
    ) ELSE NULL END AS "initiative_count",
    "contingent"."initiative_limit"
  FROM "member" CROSS JOIN "contingent";

COMMENT ON VIEW "member_contingent" IS 'Actual counts of text entries and initiatives are calculated per member for each limit in the "contingent" table.';

COMMENT ON COLUMN "member_contingent"."text_entry_count" IS 'Only calculated when "text_entry_limit" is not null in the same row';
COMMENT ON COLUMN "member_contingent"."initiative_count" IS 'Only calculated when "initiative_limit" is not null in the same row';


CREATE VIEW "member_contingent_left" AS
  SELECT
    "member_id",
    max("text_entry_limit" - "text_entry_count") AS "text_entries_left",
    max("initiative_limit" - "initiative_count") AS "initiatives_left"
  FROM "member_contingent" GROUP BY "member_id";

COMMENT ON VIEW "member_contingent_left" IS 'Amount of text entries or initiatives which can be posted now instantly by a member. This view should be used by a frontend to determine, if the contingent for posting is exhausted.';


CREATE TYPE "timeline_event" AS ENUM (
  'issue_created',
  'issue_canceled',
  'issue_accepted',
  'issue_half_frozen',
  'issue_finished_without_voting',
  'issue_voting_started',
  'issue_finished_after_voting',
  'initiative_created',
  'initiative_revoked',
  'draft_created',
  'suggestion_created');

COMMENT ON TYPE "timeline_event" IS 'Types of event in timeline tables';


CREATE VIEW "timeline_issue" AS
    SELECT
      "created" AS "occurrence",
      'issue_created'::"timeline_event" AS "event",
      "id" AS "issue_id"
    FROM "issue"
  UNION ALL
    SELECT
      "closed" AS "occurrence",
      'issue_canceled'::"timeline_event" AS "event",
      "id" AS "issue_id"
    FROM "issue" WHERE "closed" NOTNULL AND "fully_frozen" ISNULL
  UNION ALL
    SELECT
      "accepted" AS "occurrence",
      'issue_accepted'::"timeline_event" AS "event",
      "id" AS "issue_id"
    FROM "issue" WHERE "accepted" NOTNULL
  UNION ALL
    SELECT
      "half_frozen" AS "occurrence",
      'issue_half_frozen'::"timeline_event" AS "event",
      "id" AS "issue_id"
    FROM "issue" WHERE "half_frozen" NOTNULL
  UNION ALL
    SELECT
      "fully_frozen" AS "occurrence",
      'issue_voting_started'::"timeline_event" AS "event",
      "id" AS "issue_id"
    FROM "issue"
    WHERE "fully_frozen" NOTNULL
    AND ("closed" ISNULL OR "closed" != "fully_frozen")
  UNION ALL
    SELECT
      "closed" AS "occurrence",
      CASE WHEN "fully_frozen" = "closed" THEN
        'issue_finished_without_voting'::"timeline_event"
      ELSE
        'issue_finished_after_voting'::"timeline_event"
      END AS "event",
      "id" AS "issue_id"
    FROM "issue" WHERE "closed" NOTNULL AND "fully_frozen" NOTNULL;

COMMENT ON VIEW "timeline_issue" IS 'Helper view for "timeline" view';


CREATE VIEW "timeline_initiative" AS
    SELECT
      "created" AS "occurrence",
      'initiative_created'::"timeline_event" AS "event",
      "id" AS "initiative_id"
    FROM "initiative"
  UNION ALL
    SELECT
      "revoked" AS "occurrence",
      'initiative_revoked'::"timeline_event" AS "event",
      "id" AS "initiative_id"
    FROM "initiative" WHERE "revoked" NOTNULL;

COMMENT ON VIEW "timeline_initiative" IS 'Helper view for "timeline" view';


CREATE VIEW "timeline_draft" AS
  SELECT
    "created" AS "occurrence",
    'draft_created'::"timeline_event" AS "event",
    "id" AS "draft_id"
  FROM "draft";

COMMENT ON VIEW "timeline_draft" IS 'Helper view for "timeline" view';


CREATE VIEW "timeline_suggestion" AS
  SELECT
    "created" AS "occurrence",
    'suggestion_created'::"timeline_event" AS "event",
    "id" AS "suggestion_id"
  FROM "suggestion";

COMMENT ON VIEW "timeline_suggestion" IS 'Helper view for "timeline" view';


CREATE VIEW "timeline" AS
    SELECT
      "occurrence",
      "event",
      "issue_id",
      NULL AS "initiative_id",
      NULL::INT8 AS "draft_id",  -- TODO: Why do we need a type-cast here? Is this due to 32 bit architecture?
      NULL::INT8 AS "suggestion_id"
    FROM "timeline_issue"
  UNION ALL
    SELECT
      "occurrence",
      "event",
      NULL AS "issue_id",
      "initiative_id",
      NULL AS "draft_id",
      NULL AS "suggestion_id"
    FROM "timeline_initiative"
  UNION ALL
    SELECT
      "occurrence",
      "event",
      NULL AS "issue_id",
      NULL AS "initiative_id",
      "draft_id",
      NULL AS "suggestion_id"
    FROM "timeline_draft"
  UNION ALL
    SELECT
      "occurrence",
      "event",
      NULL AS "issue_id",
      NULL AS "initiative_id",
      NULL AS "draft_id",
      "suggestion_id"
    FROM "timeline_suggestion";

COMMENT ON VIEW "timeline" IS 'Aggregation of different events in the system';



--------------------------------------------------
-- Set returning function for delegation chains --
--------------------------------------------------


CREATE TYPE "delegation_chain_loop_tag" AS ENUM
  ('first', 'intermediate', 'last', 'repetition');

COMMENT ON TYPE "delegation_chain_loop_tag" IS 'Type for loop tags in "delegation_chain_row" type';


CREATE TYPE "delegation_chain_row" AS (
        "index"                 INT4,
        "member_id"             INT4,
        "member_active"         BOOLEAN,
        "participation"         BOOLEAN,
        "overridden"            BOOLEAN,
        "scope_in"              "delegation_scope",
        "scope_out"             "delegation_scope",
        "loop"                  "delegation_chain_loop_tag" );

COMMENT ON TYPE "delegation_chain_row" IS 'Type of rows returned by "delegation_chain"(...) functions';

COMMENT ON COLUMN "delegation_chain_row"."index"         IS 'Index starting with 0 and counting up';
COMMENT ON COLUMN "delegation_chain_row"."participation" IS 'In case of delegation chains for issues: interest, for areas: membership, for global delegation chains: always null';
COMMENT ON COLUMN "delegation_chain_row"."overridden"    IS 'True, if an entry with lower index has "participation" set to true';
COMMENT ON COLUMN "delegation_chain_row"."scope_in"      IS 'Scope of used incoming delegation';
COMMENT ON COLUMN "delegation_chain_row"."scope_out"     IS 'Scope of used outgoing delegation';
COMMENT ON COLUMN "delegation_chain_row"."loop"          IS 'Not null, if member is part of a loop, see "delegation_chain_loop_tag" type';


CREATE FUNCTION "delegation_chain"
  ( "member_id_p"           "member"."id"%TYPE,
    "area_id_p"             "area"."id"%TYPE,
    "issue_id_p"            "issue"."id"%TYPE,
    "simulate_trustee_id_p" "member"."id"%TYPE )
  RETURNS SETOF "delegation_chain_row"
  LANGUAGE 'plpgsql' STABLE AS $$
    DECLARE
      "issue_row"          "issue"%ROWTYPE;
      "visited_member_ids" INT4[];  -- "member"."id"%TYPE[]
      "loop_member_id_v"   "member"."id"%TYPE;
      "output_row"         "delegation_chain_row";
      "output_rows"        "delegation_chain_row"[];
      "delegation_row"     "delegation"%ROWTYPE;
      "row_count"          INT4;
      "i"                  INT4;
      "loop_v"             BOOLEAN;
    BEGIN
      SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
      "visited_member_ids" := '{}';
      "loop_member_id_v"   := NULL;
      "output_rows"        := '{}';
      "output_row"."index"         := 0;
      "output_row"."member_id"     := "member_id_p";
      "output_row"."member_active" := TRUE;
      "output_row"."participation" := FALSE;
      "output_row"."overridden"    := FALSE;
      "output_row"."scope_out"     := NULL;
      LOOP
        IF "visited_member_ids" @> ARRAY["output_row"."member_id"] THEN
          "loop_member_id_v" := "output_row"."member_id";
        ELSE
          "visited_member_ids" :=
            "visited_member_ids" || "output_row"."member_id";
        END IF;
        IF "output_row"."participation" THEN
          "output_row"."overridden" := TRUE;
        END IF;
        "output_row"."scope_in" := "output_row"."scope_out";
        IF EXISTS (
          SELECT NULL FROM "member" 
          WHERE "id" = "output_row"."member_id" AND "active"
        ) THEN
          IF "area_id_p" ISNULL AND "issue_id_p" ISNULL THEN
            SELECT * INTO "delegation_row" FROM "delegation"
              WHERE "truster_id" = "output_row"."member_id"
              AND "scope" = 'global';
          ELSIF "area_id_p" NOTNULL AND "issue_id_p" ISNULL THEN
            "output_row"."participation" := EXISTS (
              SELECT NULL FROM "membership"
              WHERE "area_id" = "area_id_p"
              AND "member_id" = "output_row"."member_id"
            );
            SELECT * INTO "delegation_row" FROM "delegation"
              WHERE "truster_id" = "output_row"."member_id"
              AND ("scope" = 'global' OR "area_id" = "area_id_p")
              ORDER BY "scope" DESC;
          ELSIF "area_id_p" ISNULL AND "issue_id_p" NOTNULL THEN
            "output_row"."participation" := EXISTS (
              SELECT NULL FROM "interest"
              WHERE "issue_id" = "issue_id_p"
              AND "member_id" = "output_row"."member_id"
            );
            SELECT * INTO "delegation_row" FROM "delegation"
              WHERE "truster_id" = "output_row"."member_id"
              AND ("scope" = 'global' OR
                "area_id" = "issue_row"."area_id" OR
                "issue_id" = "issue_id_p"
              )
              ORDER BY "scope" DESC;
          ELSE
            RAISE EXCEPTION 'Either area_id or issue_id or both must be NULL.';
          END IF;
        ELSE
          "output_row"."member_active" := FALSE;
          "output_row"."participation" := FALSE;
          "output_row"."scope_out"     := NULL;
          "delegation_row" := ROW(NULL);
        END IF;
        IF
          "output_row"."member_id" = "member_id_p" AND
          "simulate_trustee_id_p" NOTNULL
        THEN
          "output_row"."scope_out" := CASE
            WHEN "area_id_p" ISNULL  AND "issue_id_p" ISNULL  THEN 'global'
            WHEN "area_id_p" NOTNULL AND "issue_id_p" ISNULL  THEN 'area'
            WHEN "area_id_p" ISNULL  AND "issue_id_p" NOTNULL THEN 'issue'
          END;
          "output_rows" := "output_rows" || "output_row";
          "output_row"."member_id" := "simulate_trustee_id_p";
        ELSIF "delegation_row"."trustee_id" NOTNULL THEN
          "output_row"."scope_out" := "delegation_row"."scope";
          "output_rows" := "output_rows" || "output_row";
          "output_row"."member_id" := "delegation_row"."trustee_id";
        ELSE
          "output_row"."scope_out" := NULL;
          "output_rows" := "output_rows" || "output_row";
          EXIT;
        END IF;
        EXIT WHEN "loop_member_id_v" NOTNULL;
        "output_row"."index" := "output_row"."index" + 1;
      END LOOP;
      "row_count" := array_upper("output_rows", 1);
      "i"      := 1;
      "loop_v" := FALSE;
      LOOP
        "output_row" := "output_rows"["i"];
        EXIT WHEN "output_row"."member_id" ISNULL;
        IF "loop_v" THEN
          IF "i" + 1 = "row_count" THEN
            "output_row"."loop" := 'last';
          ELSIF "i" = "row_count" THEN
            "output_row"."loop" := 'repetition';
          ELSE
            "output_row"."loop" := 'intermediate';
          END IF;
        ELSIF "output_row"."member_id" = "loop_member_id_v" THEN
          "output_row"."loop" := 'first';
          "loop_v" := TRUE;
        END IF;
        IF "area_id_p" ISNULL AND "issue_id_p" ISNULL THEN
          "output_row"."participation" := NULL;
        END IF;
        RETURN NEXT "output_row";
        "i" := "i" + 1;
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "delegation_chain"
  ( "member"."id"%TYPE,
    "area"."id"%TYPE,
    "issue"."id"%TYPE,
    "member"."id"%TYPE )
  IS 'Helper function for frontends to display delegation chains; Not part of internal voting logic';

CREATE FUNCTION "delegation_chain"
  ( "member_id_p" "member"."id"%TYPE,
    "area_id_p"   "area"."id"%TYPE,
    "issue_id_p"  "issue"."id"%TYPE )
  RETURNS SETOF "delegation_chain_row"
  LANGUAGE 'plpgsql' STABLE AS $$
    DECLARE
      "result_row" "delegation_chain_row";
    BEGIN
      FOR "result_row" IN
        SELECT * FROM "delegation_chain"(
          "member_id_p", "area_id_p", "issue_id_p", NULL
        )
      LOOP
        RETURN NEXT "result_row";
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "delegation_chain"
  ( "member"."id"%TYPE,
    "area"."id"%TYPE,
    "issue"."id"%TYPE )
  IS 'Shortcut for "delegation_chain"(...) function where 4th parameter is null';



------------------------------
-- Comparison by vote count --
------------------------------

CREATE FUNCTION "vote_ratio"
  ( "positive_votes_p" "initiative"."positive_votes"%TYPE,
    "negative_votes_p" "initiative"."negative_votes"%TYPE )
  RETURNS FLOAT8
  LANGUAGE 'plpgsql' STABLE AS $$
    BEGIN
      IF "positive_votes_p" > 0 AND "negative_votes_p" > 0 THEN
        RETURN
          "positive_votes_p"::FLOAT8 /
          ("positive_votes_p" + "negative_votes_p")::FLOAT8;
      ELSIF "positive_votes_p" > 0 THEN
        RETURN "positive_votes_p";
      ELSIF "negative_votes_p" > 0 THEN
        RETURN 1 - "negative_votes_p";
      ELSE
        RETURN 0.5;
      END IF;
    END;
  $$;

COMMENT ON FUNCTION "vote_ratio"
  ( "initiative"."positive_votes"%TYPE,
    "initiative"."negative_votes"%TYPE )
  IS 'Returns a number, which can be used for comparison of initiatives based on count of approvals and disapprovals. Greater numbers indicate a better result. This function is NOT injective.';



------------------------------------------------
-- Locking for snapshots and voting procedure --
------------------------------------------------

CREATE FUNCTION "global_lock"() RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      -- NOTE: PostgreSQL allows reading, while tables are locked in
      -- exclusive move. Transactions should be kept short anyway!
      LOCK TABLE "member"     IN EXCLUSIVE MODE;
      LOCK TABLE "area"       IN EXCLUSIVE MODE;
      LOCK TABLE "membership" IN EXCLUSIVE MODE;
      -- NOTE: "member", "area" and "membership" are locked first to
      -- prevent deadlocks in combination with "calculate_member_counts"()
      LOCK TABLE "policy"     IN EXCLUSIVE MODE;
      LOCK TABLE "issue"      IN EXCLUSIVE MODE;
      LOCK TABLE "initiative" IN EXCLUSIVE MODE;
      LOCK TABLE "draft"      IN EXCLUSIVE MODE;
      LOCK TABLE "suggestion" IN EXCLUSIVE MODE;
      LOCK TABLE "interest"   IN EXCLUSIVE MODE;
      LOCK TABLE "initiator"  IN EXCLUSIVE MODE;
      LOCK TABLE "supporter"  IN EXCLUSIVE MODE;
      LOCK TABLE "opinion"    IN EXCLUSIVE MODE;
      LOCK TABLE "delegation" IN EXCLUSIVE MODE;
      LOCK TABLE "direct_population_snapshot"     IN EXCLUSIVE MODE;
      LOCK TABLE "delegating_population_snapshot" IN EXCLUSIVE MODE;
      LOCK TABLE "direct_interest_snapshot"       IN EXCLUSIVE MODE;
      LOCK TABLE "delegating_interest_snapshot"   IN EXCLUSIVE MODE;
      LOCK TABLE "direct_supporter_snapshot"      IN EXCLUSIVE MODE;
      LOCK TABLE "direct_voter"     IN EXCLUSIVE MODE;
      LOCK TABLE "delegating_voter" IN EXCLUSIVE MODE;
      LOCK TABLE "vote"             IN EXCLUSIVE MODE;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "global_lock"() IS 'Locks all tables related to support/voting until end of transaction; read access is still possible though';



-------------------------------
-- Materialize member counts --
-------------------------------

CREATE FUNCTION "calculate_member_counts"()
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      LOCK TABLE "member"     IN EXCLUSIVE MODE;
      LOCK TABLE "area"       IN EXCLUSIVE MODE;
      LOCK TABLE "membership" IN EXCLUSIVE MODE;
      DELETE FROM "member_count";
      INSERT INTO "member_count" ("total_count")
        SELECT "total_count" FROM "member_count_view";
      UPDATE "area" SET
        "direct_member_count" = "view"."direct_member_count",
        "member_weight"       = "view"."member_weight",
        "autoreject_weight"   = "view"."autoreject_weight"
        FROM "area_member_count" AS "view"
        WHERE "view"."area_id" = "area"."id";
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "calculate_member_counts"() IS 'Updates "member_count" table and "member_count" column of table "area" by materializing data from views "member_count_view" and "area_member_count"';



------------------------------
-- Calculation of snapshots --
------------------------------

CREATE FUNCTION "weight_of_added_delegations_for_population_snapshot"
  ( "issue_id_p"            "issue"."id"%TYPE,
    "member_id_p"           "member"."id"%TYPE,
    "delegate_member_ids_p" "delegating_population_snapshot"."delegate_member_ids"%TYPE )
  RETURNS "direct_population_snapshot"."weight"%TYPE
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_delegation_row"  "issue_delegation"%ROWTYPE;
      "delegate_member_ids_v" "delegating_population_snapshot"."delegate_member_ids"%TYPE;
      "weight_v"              INT4;
      "sub_weight_v"          INT4;
    BEGIN
      "weight_v" := 0;
      FOR "issue_delegation_row" IN
        SELECT * FROM "issue_delegation"
        WHERE "trustee_id" = "member_id_p"
        AND "issue_id" = "issue_id_p"
      LOOP
        IF NOT EXISTS (
          SELECT NULL FROM "direct_population_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "issue_delegation_row"."truster_id"
        ) AND NOT EXISTS (
          SELECT NULL FROM "delegating_population_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "issue_delegation_row"."truster_id"
        ) THEN
          "delegate_member_ids_v" :=
            "member_id_p" || "delegate_member_ids_p";
          INSERT INTO "delegating_population_snapshot" (
              "issue_id",
              "event",
              "member_id",
              "scope",
              "delegate_member_ids"
            ) VALUES (
              "issue_id_p",
              'periodic',
              "issue_delegation_row"."truster_id",
              "issue_delegation_row"."scope",
              "delegate_member_ids_v"
            );
          "sub_weight_v" := 1 +
            "weight_of_added_delegations_for_population_snapshot"(
              "issue_id_p",
              "issue_delegation_row"."truster_id",
              "delegate_member_ids_v"
            );
          UPDATE "delegating_population_snapshot"
            SET "weight" = "sub_weight_v"
            WHERE "issue_id" = "issue_id_p"
            AND "event" = 'periodic'
            AND "member_id" = "issue_delegation_row"."truster_id";
          "weight_v" := "weight_v" + "sub_weight_v";
        END IF;
      END LOOP;
      RETURN "weight_v";
    END;
  $$;

COMMENT ON FUNCTION "weight_of_added_delegations_for_population_snapshot"
  ( "issue"."id"%TYPE,
    "member"."id"%TYPE,
    "delegating_population_snapshot"."delegate_member_ids"%TYPE )
  IS 'Helper function for "create_population_snapshot" function';


CREATE FUNCTION "create_population_snapshot"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "member_id_v" "member"."id"%TYPE;
    BEGIN
      DELETE FROM "direct_population_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic';
      DELETE FROM "delegating_population_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic';
      INSERT INTO "direct_population_snapshot"
        ("issue_id", "event", "member_id")
        SELECT
          "issue_id_p"                 AS "issue_id",
          'periodic'::"snapshot_event" AS "event",
          "member"."id"                AS "member_id"
        FROM "issue"
        JOIN "area" ON "issue"."area_id" = "area"."id"
        JOIN "membership" ON "area"."id" = "membership"."area_id"
        JOIN "member" ON "membership"."member_id" = "member"."id"
        WHERE "issue"."id" = "issue_id_p"
        AND "member"."active"
        UNION
        SELECT
          "issue_id_p"                 AS "issue_id",
          'periodic'::"snapshot_event" AS "event",
          "member"."id"                AS "member_id"
        FROM "interest" JOIN "member"
        ON "interest"."member_id" = "member"."id"
        WHERE "interest"."issue_id" = "issue_id_p"
        AND "member"."active";
      FOR "member_id_v" IN
        SELECT "member_id" FROM "direct_population_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic'
      LOOP
        UPDATE "direct_population_snapshot" SET
          "weight" = 1 +
            "weight_of_added_delegations_for_population_snapshot"(
              "issue_id_p",
              "member_id_v",
              '{}'
            )
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "member_id_v";
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "create_population_snapshot"
  ( "issue_id_p" "issue"."id"%TYPE )
  IS 'This function creates a new ''periodic'' population snapshot for the given issue. It does neither lock any tables, nor updates precalculated values in other tables.';


CREATE FUNCTION "weight_of_added_delegations_for_interest_snapshot"
  ( "issue_id_p"            "issue"."id"%TYPE,
    "member_id_p"           "member"."id"%TYPE,
    "delegate_member_ids_p" "delegating_interest_snapshot"."delegate_member_ids"%TYPE )
  RETURNS "direct_interest_snapshot"."weight"%TYPE
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_delegation_row"  "issue_delegation"%ROWTYPE;
      "delegate_member_ids_v" "delegating_interest_snapshot"."delegate_member_ids"%TYPE;
      "weight_v"              INT4;
      "sub_weight_v"          INT4;
    BEGIN
      "weight_v" := 0;
      FOR "issue_delegation_row" IN
        SELECT * FROM "issue_delegation"
        WHERE "trustee_id" = "member_id_p"
        AND "issue_id" = "issue_id_p"
      LOOP
        IF NOT EXISTS (
          SELECT NULL FROM "direct_interest_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "issue_delegation_row"."truster_id"
        ) AND NOT EXISTS (
          SELECT NULL FROM "delegating_interest_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "issue_delegation_row"."truster_id"
        ) THEN
          "delegate_member_ids_v" :=
            "member_id_p" || "delegate_member_ids_p";
          INSERT INTO "delegating_interest_snapshot" (
              "issue_id",
              "event",
              "member_id",
              "scope",
              "delegate_member_ids"
            ) VALUES (
              "issue_id_p",
              'periodic',
              "issue_delegation_row"."truster_id",
              "issue_delegation_row"."scope",
              "delegate_member_ids_v"
            );
          "sub_weight_v" := 1 +
            "weight_of_added_delegations_for_interest_snapshot"(
              "issue_id_p",
              "issue_delegation_row"."truster_id",
              "delegate_member_ids_v"
            );
          UPDATE "delegating_interest_snapshot"
            SET "weight" = "sub_weight_v"
            WHERE "issue_id" = "issue_id_p"
            AND "event" = 'periodic'
            AND "member_id" = "issue_delegation_row"."truster_id";
          "weight_v" := "weight_v" + "sub_weight_v";
        END IF;
      END LOOP;
      RETURN "weight_v";
    END;
  $$;

COMMENT ON FUNCTION "weight_of_added_delegations_for_interest_snapshot"
  ( "issue"."id"%TYPE,
    "member"."id"%TYPE,
    "delegating_interest_snapshot"."delegate_member_ids"%TYPE )
  IS 'Helper function for "create_interest_snapshot" function';


CREATE FUNCTION "create_interest_snapshot"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "member_id_v" "member"."id"%TYPE;
    BEGIN
      DELETE FROM "direct_interest_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic';
      DELETE FROM "delegating_interest_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic';
      DELETE FROM "direct_supporter_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic';
      INSERT INTO "direct_interest_snapshot"
        ("issue_id", "event", "member_id", "voting_requested")
        SELECT
          "issue_id_p"  AS "issue_id",
          'periodic'    AS "event",
          "member"."id" AS "member_id",
          "interest"."voting_requested"
        FROM "interest" JOIN "member"
        ON "interest"."member_id" = "member"."id"
        WHERE "interest"."issue_id" = "issue_id_p"
        AND "member"."active";
      FOR "member_id_v" IN
        SELECT "member_id" FROM "direct_interest_snapshot"
        WHERE "issue_id" = "issue_id_p"
        AND "event" = 'periodic'
      LOOP
        UPDATE "direct_interest_snapshot" SET
          "weight" = 1 +
            "weight_of_added_delegations_for_interest_snapshot"(
              "issue_id_p",
              "member_id_v",
              '{}'
            )
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "member_id" = "member_id_v";
      END LOOP;
      INSERT INTO "direct_supporter_snapshot"
        ( "issue_id", "initiative_id", "event", "member_id",
          "informed", "satisfied" )
        SELECT
          "issue_id_p"      AS "issue_id",
          "initiative"."id" AS "initiative_id",
          'periodic'        AS "event",
          "member"."id"     AS "member_id",
          "supporter"."draft_id" = "current_draft"."id" AS "informed",
          NOT EXISTS (
            SELECT NULL FROM "critical_opinion"
            WHERE "initiative_id" = "initiative"."id"
            AND "member_id" = "member"."id"
          ) AS "satisfied"
        FROM "supporter"
        JOIN "member"
        ON "supporter"."member_id" = "member"."id"
        JOIN "initiative"
        ON "supporter"."initiative_id" = "initiative"."id"
        JOIN "current_draft"
        ON "initiative"."id" = "current_draft"."initiative_id"
        JOIN "direct_interest_snapshot"
        ON "member"."id" = "direct_interest_snapshot"."member_id"
        AND "initiative"."issue_id" = "direct_interest_snapshot"."issue_id"
        AND "event" = 'periodic'
        WHERE "member"."active"
        AND "initiative"."issue_id" = "issue_id_p";
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "create_interest_snapshot"
  ( "issue"."id"%TYPE )
  IS 'This function creates a new ''periodic'' interest/supporter snapshot for the given issue. It does neither lock any tables, nor updates precalculated values in other tables.';


CREATE FUNCTION "create_snapshot"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "initiative_id_v"    "initiative"."id"%TYPE;
      "suggestion_id_v"    "suggestion"."id"%TYPE;
    BEGIN
      PERFORM "global_lock"();
      PERFORM "create_population_snapshot"("issue_id_p");
      PERFORM "create_interest_snapshot"("issue_id_p");
      UPDATE "issue" SET
        "snapshot" = now(),
        "latest_snapshot_event" = 'periodic',
        "population" = (
          SELECT coalesce(sum("weight"), 0)
          FROM "direct_population_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
        ),
        "vote_now" = (
          SELECT coalesce(sum("weight"), 0)
          FROM "direct_interest_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "voting_requested" = TRUE
        ),
        "vote_later" = (
          SELECT coalesce(sum("weight"), 0)
          FROM "direct_interest_snapshot"
          WHERE "issue_id" = "issue_id_p"
          AND "event" = 'periodic'
          AND "voting_requested" = FALSE
        )
        WHERE "id" = "issue_id_p";
      FOR "initiative_id_v" IN
        SELECT "id" FROM "initiative" WHERE "issue_id" = "issue_id_p"
      LOOP
        UPDATE "initiative" SET
          "supporter_count" = (
            SELECT coalesce(sum("di"."weight"), 0)
            FROM "direct_interest_snapshot" AS "di"
            JOIN "direct_supporter_snapshot" AS "ds"
            ON "di"."member_id" = "ds"."member_id"
            WHERE "di"."issue_id" = "issue_id_p"
            AND "di"."event" = 'periodic'
            AND "ds"."initiative_id" = "initiative_id_v"
            AND "ds"."event" = 'periodic'
          ),
          "informed_supporter_count" = (
            SELECT coalesce(sum("di"."weight"), 0)
            FROM "direct_interest_snapshot" AS "di"
            JOIN "direct_supporter_snapshot" AS "ds"
            ON "di"."member_id" = "ds"."member_id"
            WHERE "di"."issue_id" = "issue_id_p"
            AND "di"."event" = 'periodic'
            AND "ds"."initiative_id" = "initiative_id_v"
            AND "ds"."event" = 'periodic'
            AND "ds"."informed"
          ),
          "satisfied_supporter_count" = (
            SELECT coalesce(sum("di"."weight"), 0)
            FROM "direct_interest_snapshot" AS "di"
            JOIN "direct_supporter_snapshot" AS "ds"
            ON "di"."member_id" = "ds"."member_id"
            WHERE "di"."issue_id" = "issue_id_p"
            AND "di"."event" = 'periodic'
            AND "ds"."initiative_id" = "initiative_id_v"
            AND "ds"."event" = 'periodic'
            AND "ds"."satisfied"
          ),
          "satisfied_informed_supporter_count" = (
            SELECT coalesce(sum("di"."weight"), 0)
            FROM "direct_interest_snapshot" AS "di"
            JOIN "direct_supporter_snapshot" AS "ds"
            ON "di"."member_id" = "ds"."member_id"
            WHERE "di"."issue_id" = "issue_id_p"
            AND "di"."event" = 'periodic'
            AND "ds"."initiative_id" = "initiative_id_v"
            AND "ds"."event" = 'periodic'
            AND "ds"."informed"
            AND "ds"."satisfied"
          )
          WHERE "id" = "initiative_id_v";
        FOR "suggestion_id_v" IN
          SELECT "id" FROM "suggestion"
          WHERE "initiative_id" = "initiative_id_v"
        LOOP
          UPDATE "suggestion" SET
            "minus2_unfulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = -2
              AND "opinion"."fulfilled" = FALSE
            ),
            "minus2_fulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = -2
              AND "opinion"."fulfilled" = TRUE
            ),
            "minus1_unfulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = -1
              AND "opinion"."fulfilled" = FALSE
            ),
            "minus1_fulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = -1
              AND "opinion"."fulfilled" = TRUE
            ),
            "plus1_unfulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = 1
              AND "opinion"."fulfilled" = FALSE
            ),
            "plus1_fulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = 1
              AND "opinion"."fulfilled" = TRUE
            ),
            "plus2_unfulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = 2
              AND "opinion"."fulfilled" = FALSE
            ),
            "plus2_fulfilled_count" = (
              SELECT coalesce(sum("snapshot"."weight"), 0)
              FROM "issue" CROSS JOIN "opinion"
              JOIN "direct_interest_snapshot" AS "snapshot"
              ON "snapshot"."issue_id" = "issue"."id"
              AND "snapshot"."event" = "issue"."latest_snapshot_event"
              AND "snapshot"."member_id" = "opinion"."member_id"
              WHERE "issue"."id" = "issue_id_p"
              AND "opinion"."suggestion_id" = "suggestion_id_v"
              AND "opinion"."degree" = 2
              AND "opinion"."fulfilled" = TRUE
            )
            WHERE "suggestion"."id" = "suggestion_id_v";
        END LOOP;
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "create_snapshot"
  ( "issue"."id"%TYPE )
  IS 'This function creates a complete new ''periodic'' snapshot of population, interest and support for the given issue. All involved tables are locked, and after completion precalculated values in the source tables are updated.';


CREATE FUNCTION "set_snapshot_event"
  ( "issue_id_p" "issue"."id"%TYPE,
    "event_p" "snapshot_event" )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "event_v" "issue"."latest_snapshot_event"%TYPE;
    BEGIN
      SELECT "latest_snapshot_event" INTO "event_v" FROM "issue"
        WHERE "id" = "issue_id_p" FOR UPDATE;
      UPDATE "issue" SET "latest_snapshot_event" = "event_p"
        WHERE "id" = "issue_id_p";
      UPDATE "direct_population_snapshot" SET "event" = "event_p"
        WHERE "issue_id" = "issue_id_p" AND "event" = "event_v";
      UPDATE "delegating_population_snapshot" SET "event" = "event_p"
        WHERE "issue_id" = "issue_id_p" AND "event" = "event_v";
      UPDATE "direct_interest_snapshot" SET "event" = "event_p"
        WHERE "issue_id" = "issue_id_p" AND "event" = "event_v";
      UPDATE "delegating_interest_snapshot" SET "event" = "event_p"
        WHERE "issue_id" = "issue_id_p" AND "event" = "event_v";
      UPDATE "direct_supporter_snapshot" SET "event" = "event_p"
        WHERE "issue_id" = "issue_id_p" AND "event" = "event_v";
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "set_snapshot_event"
  ( "issue"."id"%TYPE,
    "snapshot_event" )
  IS 'Change "event" attribute of the previous ''periodic'' snapshot';



---------------------
-- Freezing issues --
---------------------

CREATE FUNCTION "freeze_after_snapshot"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_row"      "issue"%ROWTYPE;
      "policy_row"     "policy"%ROWTYPE;
      "initiative_row" "initiative"%ROWTYPE;
    BEGIN
      SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
      SELECT * INTO "policy_row"
        FROM "policy" WHERE "id" = "issue_row"."policy_id";
      PERFORM "set_snapshot_event"("issue_id_p", 'full_freeze');
      UPDATE "issue" SET
        "accepted"     = coalesce("accepted", now()),
        "half_frozen"  = coalesce("half_frozen", now()),
        "fully_frozen" = now()
        WHERE "id" = "issue_id_p";
      FOR "initiative_row" IN
        SELECT * FROM "initiative"
        WHERE "issue_id" = "issue_id_p" AND "revoked" ISNULL
      LOOP
        IF
          "initiative_row"."satisfied_supporter_count" > 0 AND
          "initiative_row"."satisfied_supporter_count" *
          "policy_row"."initiative_quorum_den" >=
          "issue_row"."population" * "policy_row"."initiative_quorum_num"
        THEN
          UPDATE "initiative" SET "admitted" = TRUE
            WHERE "id" = "initiative_row"."id";
        ELSE
          UPDATE "initiative" SET "admitted" = FALSE
            WHERE "id" = "initiative_row"."id";
        END IF;
      END LOOP;
      IF NOT EXISTS (
        SELECT NULL FROM "initiative"
        WHERE "issue_id" = "issue_id_p" AND "admitted" = TRUE
      ) THEN
        PERFORM "close_voting"("issue_id_p");
      END IF;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "freeze_after_snapshot"
  ( "issue"."id"%TYPE )
  IS 'This function freezes an issue (fully) and starts voting, but must only be called when "create_snapshot" was called in the same transaction.';


CREATE FUNCTION "manual_freeze"("issue_id_p" "issue"."id"%TYPE)
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_row" "issue"%ROWTYPE;
    BEGIN
      PERFORM "create_snapshot"("issue_id_p");
      PERFORM "freeze_after_snapshot"("issue_id_p");
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "manual_freeze"
  ( "issue"."id"%TYPE )
  IS 'Freeze an issue manually (fully) and start voting';



-----------------------
-- Counting of votes --
-----------------------


CREATE FUNCTION "weight_of_added_vote_delegations"
  ( "issue_id_p"            "issue"."id"%TYPE,
    "member_id_p"           "member"."id"%TYPE,
    "delegate_member_ids_p" "delegating_voter"."delegate_member_ids"%TYPE )
  RETURNS "direct_voter"."weight"%TYPE
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_delegation_row"  "issue_delegation"%ROWTYPE;
      "delegate_member_ids_v" "delegating_voter"."delegate_member_ids"%TYPE;
      "weight_v"              INT4;
      "sub_weight_v"          INT4;
    BEGIN
      "weight_v" := 0;
      FOR "issue_delegation_row" IN
        SELECT * FROM "issue_delegation"
        WHERE "trustee_id" = "member_id_p"
        AND "issue_id" = "issue_id_p"
      LOOP
        IF NOT EXISTS (
          SELECT NULL FROM "direct_voter"
          WHERE "member_id" = "issue_delegation_row"."truster_id"
          AND "issue_id" = "issue_id_p"
        ) AND NOT EXISTS (
          SELECT NULL FROM "delegating_voter"
          WHERE "member_id" = "issue_delegation_row"."truster_id"
          AND "issue_id" = "issue_id_p"
        ) THEN
          "delegate_member_ids_v" :=
            "member_id_p" || "delegate_member_ids_p";
          INSERT INTO "delegating_voter" (
              "issue_id",
              "member_id",
              "scope",
              "delegate_member_ids"
            ) VALUES (
              "issue_id_p",
              "issue_delegation_row"."truster_id",
              "issue_delegation_row"."scope",
              "delegate_member_ids_v"
            );
          "sub_weight_v" := 1 +
            "weight_of_added_vote_delegations"(
              "issue_id_p",
              "issue_delegation_row"."truster_id",
              "delegate_member_ids_v"
            );
          UPDATE "delegating_voter"
            SET "weight" = "sub_weight_v"
            WHERE "issue_id" = "issue_id_p"
            AND "member_id" = "issue_delegation_row"."truster_id";
          "weight_v" := "weight_v" + "sub_weight_v";
        END IF;
      END LOOP;
      RETURN "weight_v";
    END;
  $$;

COMMENT ON FUNCTION "weight_of_added_vote_delegations"
  ( "issue"."id"%TYPE,
    "member"."id"%TYPE,
    "delegating_voter"."delegate_member_ids"%TYPE )
  IS 'Helper function for "add_vote_delegations" function';


CREATE FUNCTION "add_vote_delegations"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "member_id_v" "member"."id"%TYPE;
    BEGIN
      FOR "member_id_v" IN
        SELECT "member_id" FROM "direct_voter"
        WHERE "issue_id" = "issue_id_p"
      LOOP
        UPDATE "direct_voter" SET
          "weight" = "weight" + "weight_of_added_vote_delegations"(
            "issue_id_p",
            "member_id_v",
            '{}'
          )
          WHERE "member_id" = "member_id_v"
          AND "issue_id" = "issue_id_p";
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "add_vote_delegations"
  ( "issue_id_p" "issue"."id"%TYPE )
  IS 'Helper function for "close_voting" function';


CREATE FUNCTION "close_voting"("issue_id_p" "issue"."id"%TYPE)
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_row"   "issue"%ROWTYPE;
      "member_id_v" "member"."id"%TYPE;
    BEGIN
      PERFORM "global_lock"();
      SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
      DELETE FROM "delegating_voter"
        WHERE "issue_id" = "issue_id_p";
      DELETE FROM "direct_voter"
        WHERE "issue_id" = "issue_id_p"
        AND "autoreject" = TRUE;
      DELETE FROM "direct_voter" USING "member"
        WHERE "direct_voter"."member_id" = "member"."id"
        AND "direct_voter"."issue_id" = "issue_id_p"
        AND "member"."active" = FALSE;
      UPDATE "direct_voter" SET "weight" = 1
        WHERE "issue_id" = "issue_id_p";
      PERFORM "add_vote_delegations"("issue_id_p");
      FOR "member_id_v" IN
        SELECT "interest"."member_id"
          FROM "interest"
          LEFT JOIN "direct_voter"
            ON "interest"."member_id" = "direct_voter"."member_id"
            AND "interest"."issue_id" = "direct_voter"."issue_id"
          LEFT JOIN "delegating_voter"
            ON "interest"."member_id" = "delegating_voter"."member_id"
            AND "interest"."issue_id" = "delegating_voter"."issue_id"
          WHERE "interest"."issue_id" = "issue_id_p"
          AND "interest"."autoreject" = TRUE
          AND "direct_voter"."member_id" ISNULL
          AND "delegating_voter"."member_id" ISNULL
        UNION SELECT "membership"."member_id"
          FROM "membership"
          LEFT JOIN "interest"
            ON "membership"."member_id" = "interest"."member_id"
            AND "interest"."issue_id" = "issue_id_p"
          LEFT JOIN "direct_voter"
            ON "membership"."member_id" = "direct_voter"."member_id"
            AND "direct_voter"."issue_id" = "issue_id_p"
          LEFT JOIN "delegating_voter"
            ON "membership"."member_id" = "delegating_voter"."member_id"
            AND "delegating_voter"."issue_id" = "issue_id_p"
          WHERE "membership"."area_id" = "issue_row"."area_id"
          AND "membership"."autoreject" = TRUE
          AND "interest"."autoreject" ISNULL
          AND "direct_voter"."member_id" ISNULL
          AND "delegating_voter"."member_id" ISNULL
      LOOP
        INSERT INTO "direct_voter"
          ("member_id", "issue_id", "weight", "autoreject") VALUES
          ("member_id_v", "issue_id_p", 1, TRUE);
        INSERT INTO "vote" (
          "member_id",
          "issue_id",
          "initiative_id",
          "grade"
          ) SELECT
            "member_id_v" AS "member_id",
            "issue_id_p"  AS "issue_id",
            "id"          AS "initiative_id",
            -1            AS "grade"
          FROM "initiative" WHERE "issue_id" = "issue_id_p";
      END LOOP;
      PERFORM "add_vote_delegations"("issue_id_p");
      UPDATE "issue" SET
        "voter_count" = (
          SELECT coalesce(sum("weight"), 0)
          FROM "direct_voter" WHERE "issue_id" = "issue_id_p"
        )
        WHERE "id" = "issue_id_p";
      UPDATE "initiative" SET
        "positive_votes" = "vote_counts"."positive_votes",
        "negative_votes" = "vote_counts"."negative_votes",
        "agreed" = CASE WHEN "majority_strict" THEN
          "vote_counts"."positive_votes" * "majority_den" >
          "majority_num" *
          ("vote_counts"."positive_votes"+"vote_counts"."negative_votes")
        ELSE
          "vote_counts"."positive_votes" * "majority_den" >=
          "majority_num" *
          ("vote_counts"."positive_votes"+"vote_counts"."negative_votes")
        END
        FROM
          ( SELECT
              "initiative"."id" AS "initiative_id",
              coalesce(
                sum(
                  CASE WHEN "grade" > 0 THEN "direct_voter"."weight" ELSE 0 END
                ),
                0
              ) AS "positive_votes",
              coalesce(
                sum(
                  CASE WHEN "grade" < 0 THEN "direct_voter"."weight" ELSE 0 END
                ),
                0
              ) AS "negative_votes"
            FROM "initiative"
            JOIN "issue" ON "initiative"."issue_id" = "issue"."id"
            JOIN "policy" ON "issue"."policy_id" = "policy"."id"
            LEFT JOIN "direct_voter"
              ON "direct_voter"."issue_id" = "initiative"."issue_id"
            LEFT JOIN "vote"
              ON "vote"."initiative_id" = "initiative"."id"
              AND "vote"."member_id" = "direct_voter"."member_id"
            WHERE "initiative"."issue_id" = "issue_id_p"
            AND "initiative"."admitted"  -- NOTE: NULL case is handled too
            GROUP BY "initiative"."id"
          ) AS "vote_counts",
          "issue",
          "policy"
        WHERE "vote_counts"."initiative_id" = "initiative"."id"
        AND "issue"."id" = "initiative"."issue_id"
        AND "policy"."id" = "issue"."policy_id";
      UPDATE "issue" SET "closed" = now() WHERE "id" = "issue_id_p";
    END;
  $$;

COMMENT ON FUNCTION "close_voting"
  ( "issue"."id"%TYPE )
  IS 'Closes the voting on an issue, and calculates positive and negative votes for each initiative; The ranking is not calculated yet, to keep the (locking) transaction short.';


CREATE FUNCTION "defeat_strength"
  ( "positive_votes_p" INT4, "negative_votes_p" INT4 )
  RETURNS INT8
  LANGUAGE 'plpgsql' IMMUTABLE AS $$
    BEGIN
      IF "positive_votes_p" > "negative_votes_p" THEN
        RETURN ("positive_votes_p"::INT8 << 31) - "negative_votes_p"::INT8;
      ELSIF "positive_votes_p" = "negative_votes_p" THEN
        RETURN 0;
      ELSE
        RETURN -1;
      END IF;
    END;
  $$;

COMMENT ON FUNCTION "defeat_strength"(INT4, INT4) IS 'Calculates defeat strength (INT8!) of a pairwise defeat primarily by the absolute number of votes for the winner and secondarily by the absolute number of votes for the loser';


CREATE FUNCTION "array_init_string"("dim_p" INTEGER)
  RETURNS TEXT
  LANGUAGE 'plpgsql' IMMUTABLE AS $$
    DECLARE
      "i"          INTEGER;
      "ary_text_v" TEXT;
    BEGIN
      IF "dim_p" >= 1 THEN
        "ary_text_v" := '{NULL';
        "i" := "dim_p";
        LOOP
          "i" := "i" - 1;
          EXIT WHEN "i" = 0;
          "ary_text_v" := "ary_text_v" || ',NULL';
        END LOOP;
        "ary_text_v" := "ary_text_v" || '}';
        RETURN "ary_text_v";
      ELSE
        RAISE EXCEPTION 'Dimension needs to be at least 1.';
      END IF;
    END;
  $$;

COMMENT ON FUNCTION "array_init_string"(INTEGER) IS 'Needed for PostgreSQL < 8.4, due to missing "array_fill" function';


CREATE FUNCTION "square_matrix_init_string"("dim_p" INTEGER)
  RETURNS TEXT
  LANGUAGE 'plpgsql' IMMUTABLE AS $$
    DECLARE
      "i"          INTEGER;
      "row_text_v" TEXT;
      "ary_text_v" TEXT;
    BEGIN
      IF "dim_p" >= 1 THEN
        "row_text_v" := '{NULL';
        "i" := "dim_p";
        LOOP
          "i" := "i" - 1;
          EXIT WHEN "i" = 0;
          "row_text_v" := "row_text_v" || ',NULL';
        END LOOP;
        "row_text_v" := "row_text_v" || '}';
        "ary_text_v" := '{' || "row_text_v";
        "i" := "dim_p";
        LOOP
          "i" := "i" - 1;
          EXIT WHEN "i" = 0;
          "ary_text_v" := "ary_text_v" || ',' || "row_text_v";
        END LOOP;
        "ary_text_v" := "ary_text_v" || '}';
        RETURN "ary_text_v";
      ELSE
        RAISE EXCEPTION 'Dimension needs to be at least 1.';
      END IF;
    END;
  $$;

COMMENT ON FUNCTION "square_matrix_init_string"(INTEGER) IS 'Needed for PostgreSQL < 8.4, due to missing "array_fill" function';


CREATE FUNCTION "calculate_ranks"("issue_id_p" "issue"."id"%TYPE)
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "dimension_v"     INTEGER;
      "vote_matrix"     INT4[][];  -- absolute votes
      "matrix"          INT8[][];  -- defeat strength / best paths
      "i"               INTEGER;
      "j"               INTEGER;
      "k"               INTEGER;
      "battle_row"      "battle"%ROWTYPE;
      "rank_ary"        INT4[];
      "rank_v"          INT4;
      "done_v"          INTEGER;
      "winners_ary"     INTEGER[];
      "initiative_id_v" "initiative"."id"%TYPE;
    BEGIN
      PERFORM NULL FROM "issue" WHERE "id" = "issue_id_p" FOR UPDATE;
      SELECT count(1) INTO "dimension_v" FROM "initiative"
        WHERE "issue_id" = "issue_id_p" AND "agreed";
      IF "dimension_v" = 1 THEN
        UPDATE "initiative" SET "rank" = 1
          WHERE "issue_id" = "issue_id_p" AND "agreed";
      ELSIF "dimension_v" > 1 THEN
        -- Create "vote_matrix" with absolute number of votes in pairwise
        -- comparison:
        "vote_matrix" := "square_matrix_init_string"("dimension_v");  -- TODO: replace by "array_fill" function (PostgreSQL 8.4)
        "i" := 1;
        "j" := 2;
        FOR "battle_row" IN
          SELECT * FROM "battle" WHERE "issue_id" = "issue_id_p"
          ORDER BY "winning_initiative_id", "losing_initiative_id"
        LOOP
          "vote_matrix"["i"]["j"] := "battle_row"."count";
          IF "j" = "dimension_v" THEN
            "i" := "i" + 1;
            "j" := 1;
          ELSE
            "j" := "j" + 1;
            IF "j" = "i" THEN
              "j" := "j" + 1;
            END IF;
          END IF;
        END LOOP;
        IF "i" != "dimension_v" OR "j" != "dimension_v" + 1 THEN
          RAISE EXCEPTION 'Wrong battle count (should not happen)';
        END IF;
        -- Store defeat strengths in "matrix" using "defeat_strength"
        -- function:
        "matrix" := "square_matrix_init_string"("dimension_v");  -- TODO: replace by "array_fill" function (PostgreSQL 8.4)
        "i" := 1;
        LOOP
          "j" := 1;
          LOOP
            IF "i" != "j" THEN
              "matrix"["i"]["j"] := "defeat_strength"(
                "vote_matrix"["i"]["j"],
                "vote_matrix"["j"]["i"]
              );
            END IF;
            EXIT WHEN "j" = "dimension_v";
            "j" := "j" + 1;
          END LOOP;
          EXIT WHEN "i" = "dimension_v";
          "i" := "i" + 1;
        END LOOP;
        -- Find best paths:
        "i" := 1;
        LOOP
          "j" := 1;
          LOOP
            IF "i" != "j" THEN
              "k" := 1;
              LOOP
                IF "i" != "k" AND "j" != "k" THEN
                  IF "matrix"["j"]["i"] < "matrix"["i"]["k"] THEN
                    IF "matrix"["j"]["i"] > "matrix"["j"]["k"] THEN
                      "matrix"["j"]["k"] := "matrix"["j"]["i"];
                    END IF;
                  ELSE
                    IF "matrix"["i"]["k"] > "matrix"["j"]["k"] THEN
                      "matrix"["j"]["k"] := "matrix"["i"]["k"];
                    END IF;
                  END IF;
                END IF;
                EXIT WHEN "k" = "dimension_v";
                "k" := "k" + 1;
              END LOOP;
            END IF;
            EXIT WHEN "j" = "dimension_v";
            "j" := "j" + 1;
          END LOOP;
          EXIT WHEN "i" = "dimension_v";
          "i" := "i" + 1;
        END LOOP;
        -- Determine order of winners:
        "rank_ary" := "array_init_string"("dimension_v");  -- TODO: replace by "array_fill" function (PostgreSQL 8.4)
        "rank_v" := 1;
        "done_v" := 0;
        LOOP
          "winners_ary" := '{}';
          "i" := 1;
          LOOP
            IF "rank_ary"["i"] ISNULL THEN
              "j" := 1;
              LOOP
                IF
                  "i" != "j" AND
                  "rank_ary"["j"] ISNULL AND
                  "matrix"["j"]["i"] > "matrix"["i"]["j"]
                THEN
                  -- someone else is better
                  EXIT;
                END IF;
                IF "j" = "dimension_v" THEN
                  -- noone is better
                  "winners_ary" := "winners_ary" || "i";
                  EXIT;
                END IF;
                "j" := "j" + 1;
              END LOOP;
            END IF;
            EXIT WHEN "i" = "dimension_v";
            "i" := "i" + 1;
          END LOOP;
          "i" := 1;
          LOOP
            "rank_ary"["winners_ary"["i"]] := "rank_v";
            "done_v" := "done_v" + 1;
            EXIT WHEN "i" = array_upper("winners_ary", 1);
            "i" := "i" + 1;
          END LOOP;
          EXIT WHEN "done_v" = "dimension_v";
          "rank_v" := "rank_v" + 1;
        END LOOP;
        -- write preliminary ranks:
        "i" := 1;
        FOR "initiative_id_v" IN
          SELECT "id" FROM "initiative"
          WHERE "issue_id" = "issue_id_p" AND "agreed"
          ORDER BY "id"
        LOOP
          UPDATE "initiative" SET "rank" = "rank_ary"["i"]
            WHERE "id" = "initiative_id_v";
          "i" := "i" + 1;
        END LOOP;
        IF "i" != "dimension_v" + 1 THEN
          RAISE EXCEPTION 'Wrong winner count (should not happen)';
        END IF;
        -- straighten ranks (start counting with 1, no equal ranks):
        "rank_v" := 1;
        FOR "initiative_id_v" IN
          SELECT "id" FROM "initiative"
          WHERE "issue_id" = "issue_id_p" AND "rank" NOTNULL
          ORDER BY
            "rank",
            "vote_ratio"("positive_votes", "negative_votes") DESC,
            "id"
        LOOP
          UPDATE "initiative" SET "rank" = "rank_v"
            WHERE "id" = "initiative_id_v";
          "rank_v" := "rank_v" + 1;
        END LOOP;
      END IF;
      -- mark issue as finished
      UPDATE "issue" SET "ranks_available" = TRUE
        WHERE "id" = "issue_id_p";
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "calculate_ranks"
  ( "issue"."id"%TYPE )
  IS 'Determine ranking (Votes have to be counted first)';



-----------------------------
-- Automatic state changes --
-----------------------------


CREATE FUNCTION "check_issue"
  ( "issue_id_p" "issue"."id"%TYPE )
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_row"         "issue"%ROWTYPE;
      "policy_row"        "policy"%ROWTYPE;
      "voting_requested_v" BOOLEAN;
    BEGIN
      PERFORM "global_lock"();
      SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
      -- only process open issues:
      IF "issue_row"."closed" ISNULL THEN
        SELECT * INTO "policy_row" FROM "policy"
          WHERE "id" = "issue_row"."policy_id";
        -- create a snapshot, unless issue is already fully frozen:
        IF "issue_row"."fully_frozen" ISNULL THEN
          PERFORM "create_snapshot"("issue_id_p");
          SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
        END IF;
        -- eventually close or accept issues, which have not been accepted:
        IF "issue_row"."accepted" ISNULL THEN
          IF EXISTS (
            SELECT NULL FROM "initiative"
            WHERE "issue_id" = "issue_id_p"
            AND "supporter_count" > 0
            AND "supporter_count" * "policy_row"."issue_quorum_den"
            >= "issue_row"."population" * "policy_row"."issue_quorum_num"
          ) THEN
            -- accept issues, if supporter count is high enough
            PERFORM "set_snapshot_event"("issue_id_p", 'end_of_admission');
            "issue_row"."accepted" = now();  -- NOTE: "issue_row" used later
            UPDATE "issue" SET "accepted" = "issue_row"."accepted"
              WHERE "id" = "issue_row"."id";
          ELSIF
            now() >= "issue_row"."created" + "issue_row"."admission_time"
          THEN
            -- close issues, if admission time has expired
            PERFORM "set_snapshot_event"("issue_id_p", 'end_of_admission');
            UPDATE "issue" SET "closed" = now()
              WHERE "id" = "issue_row"."id";
          END IF;
        END IF;
        -- eventually half freeze issues:
        IF
          -- NOTE: issue can't be closed at this point, if it has been accepted
          "issue_row"."accepted" NOTNULL AND
          "issue_row"."half_frozen" ISNULL
        THEN
          SELECT
            CASE
              WHEN "vote_now" * 2 > "issue_row"."population" THEN
                TRUE
              WHEN "vote_later" * 2 > "issue_row"."population" THEN
                FALSE
              ELSE NULL
            END
            INTO "voting_requested_v"
            FROM "issue" WHERE "id" = "issue_id_p";
          IF
            "voting_requested_v" OR (
              "voting_requested_v" ISNULL AND
              now() >= "issue_row"."accepted" + "issue_row"."discussion_time"
            )
          THEN
            PERFORM "set_snapshot_event"("issue_id_p", 'half_freeze');
            "issue_row"."half_frozen" = now();  -- NOTE: "issue_row" used later
            UPDATE "issue" SET "half_frozen" = "issue_row"."half_frozen"
              WHERE "id" = "issue_row"."id";
          END IF;
        END IF;
        -- close issues after some time, if all initiatives have been revoked:
        IF
          "issue_row"."closed" ISNULL AND
          NOT EXISTS (
            -- all initiatives are revoked
            SELECT NULL FROM "initiative"
            WHERE "issue_id" = "issue_id_p" AND "revoked" ISNULL
          ) AND (
            NOT EXISTS (
              -- and no initiatives have been revoked lately
              SELECT NULL FROM "initiative"
              WHERE "issue_id" = "issue_id_p"
              AND now() < "revoked" + "issue_row"."verification_time"
            ) OR (
              -- or verification time has elapsed
              "issue_row"."half_frozen" NOTNULL AND
              "issue_row"."fully_frozen" ISNULL AND
              now() >= "issue_row"."half_frozen" + "issue_row"."verification_time"
            )
          )
        THEN
          "issue_row"."closed" = now();  -- NOTE: "issue_row" used later
          UPDATE "issue" SET "closed" = "issue_row"."closed"
            WHERE "id" = "issue_row"."id";
        END IF;
        -- fully freeze issue after verification time:
        IF
          "issue_row"."half_frozen" NOTNULL AND
          "issue_row"."fully_frozen" ISNULL AND
          "issue_row"."closed" ISNULL AND
          now() >= "issue_row"."half_frozen" + "issue_row"."verification_time"
        THEN
          PERFORM "freeze_after_snapshot"("issue_id_p");
          -- NOTE: "issue" might change, thus "issue_row" has to be updated below
        END IF;
        SELECT * INTO "issue_row" FROM "issue" WHERE "id" = "issue_id_p";
        -- close issue by calling close_voting(...) after voting time:
        IF
          "issue_row"."closed" ISNULL AND
          "issue_row"."fully_frozen" NOTNULL AND
          now() >= "issue_row"."fully_frozen" + "issue_row"."voting_time"
        THEN
          PERFORM "close_voting"("issue_id_p");
        END IF;
      END IF;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "check_issue"
  ( "issue"."id"%TYPE )
  IS 'Precalculate supporter counts etc. for a given issue, and check, if status change is required; At end of voting the ranking is not calculated by this function, but must be calculated in a seperate transaction using the "calculate_ranks" function.';


CREATE FUNCTION "check_everything"()
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "issue_id_v" "issue"."id"%TYPE;
    BEGIN
      DELETE FROM "expired_session";
      PERFORM "calculate_member_counts"();
      FOR "issue_id_v" IN SELECT "id" FROM "open_issue" LOOP
        PERFORM "check_issue"("issue_id_v");
      END LOOP;
      FOR "issue_id_v" IN SELECT "id" FROM "issue_with_ranks_missing" LOOP
        PERFORM "calculate_ranks"("issue_id_v");
      END LOOP;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "check_everything"() IS 'Perform "check_issue" for every open issue, and if possible, automatically calculate ranks. Use this function only for development and debugging purposes, as long transactions with exclusive locking may result.';



------------------------------
-- Deletion of private data --
------------------------------


CREATE FUNCTION "delete_member"("member_id_p" "member"."id"%TYPE)
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      UPDATE "member" SET
        "login"                        = NULL,
        "password"                     = NULL,
        "active"                       = FALSE,
        "notify_email"                 = NULL,
        "notify_email_unconfirmed"     = NULL,
        "notify_email_secret"          = NULL,
        "notify_email_secret_expiry"   = NULL,
        "password_reset_secret"        = NULL,
        "password_reset_secret_expiry" = NULL,
        "organizational_unit"          = NULL,
        "internal_posts"               = NULL,
        "realname"                     = NULL,
        "birthday"                     = NULL,
        "address"                      = NULL,
        "email"                        = NULL,
        "xmpp_address"                 = NULL,
        "website"                      = NULL,
        "phone"                        = NULL,
        "mobile_phone"                 = NULL,
        "profession"                   = NULL,
        "external_memberships"         = NULL,
        "external_posts"               = NULL,
        "statement"                    = NULL
        WHERE "id" = "member_id_p";
      -- "text_search_data" is updated by triggers
      UPDATE "member_history" SET "login" = NULL
        WHERE "member_id" = "member_id_p";
      DELETE FROM "setting"            WHERE "member_id" = "member_id_p";
      DELETE FROM "setting_map"        WHERE "member_id" = "member_id_p";
      DELETE FROM "member_relation_setting" WHERE "member_id" = "member_id_p";
      DELETE FROM "member_image"       WHERE "member_id" = "member_id_p";
      DELETE FROM "contact"            WHERE "member_id" = "member_id_p";
      DELETE FROM "area_setting"       WHERE "member_id" = "member_id_p";
      DELETE FROM "issue_setting"      WHERE "member_id" = "member_id_p";
      DELETE FROM "initiative_setting" WHERE "member_id" = "member_id_p";
      DELETE FROM "suggestion_setting" WHERE "member_id" = "member_id_p";
      DELETE FROM "membership"         WHERE "member_id" = "member_id_p";
      DELETE FROM "delegation"         WHERE "truster_id" = "member_id_p";
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "delete_member"("member_id_p" "member"."id"%TYPE) IS 'Clear certain settings and data of a particular member (data protection)';


CREATE FUNCTION "delete_private_data"()
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    BEGIN
      UPDATE "member" SET
        "login"                        = NULL,
        "password"                     = NULL,
        "notify_email"                 = NULL,
        "notify_email_unconfirmed"     = NULL,
        "notify_email_secret"          = NULL,
        "notify_email_secret_expiry"   = NULL,
        "password_reset_secret"        = NULL,
        "password_reset_secret_expiry" = NULL,
        "organizational_unit"          = NULL,
        "internal_posts"               = NULL,
        "realname"                     = NULL,
        "birthday"                     = NULL,
        "address"                      = NULL,
        "email"                        = NULL,
        "xmpp_address"                 = NULL,
        "website"                      = NULL,
        "phone"                        = NULL,
        "mobile_phone"                 = NULL,
        "profession"                   = NULL,
        "external_memberships"         = NULL,
        "external_posts"               = NULL,
        "statement"                    = NULL;
      -- "text_search_data" is updated by triggers
      UPDATE "member_history" SET "login" = NULL;
      DELETE FROM "invite_code";
      DELETE FROM "setting";
      DELETE FROM "setting_map";
      DELETE FROM "member_relation_setting";
      DELETE FROM "member_image";
      DELETE FROM "contact";
      DELETE FROM "session";
      DELETE FROM "area_setting";
      DELETE FROM "issue_setting";
      DELETE FROM "initiative_setting";
      DELETE FROM "suggestion_setting";
      DELETE FROM "direct_voter" USING "issue"
        WHERE "direct_voter"."issue_id" = "issue"."id"
        AND "issue"."closed" ISNULL;
      RETURN;
    END;
  $$;

COMMENT ON FUNCTION "delete_private_data"() IS 'DO NOT USE on productive database, but only on a copy! This function deletes all data which should not be publicly available, and can be used to create a database dump for publication.';



COMMIT;
