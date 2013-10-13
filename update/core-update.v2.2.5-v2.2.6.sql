BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('2.2.6', 2, 2, 6))
  AS "subquery"("string", "major", "minor", "revision");

CREATE TABLE "issue_order" (
        "id"                    INT8            PRIMARY KEY, --REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "order_in_admission_state" INT4 );

COMMENT ON TABLE "issue_order" IS 'Ordering information for issues that are not stored in the "issue" table to avoid locking of multiple issues at once';

COMMENT ON COLUMN "issue_order"."id"                       IS 'References "issue" ("id") but has no referential integrity trigger associated, due to performance/locking issues';
COMMENT ON COLUMN "issue_order"."order_in_admission_state" IS 'To be used for sorting issues within an area, when showing issues in admission state; NULL values sort last; updated by "lf_update_issue_order"';

CREATE VIEW "issue_supporter_in_admission_state" AS
  SELECT DISTINCT
    "issue"."area_id",
    "issue"."id" AS "issue_id",
    "supporter"."member_id",
    "direct_interest_snapshot"."weight"
  FROM "issue"
  JOIN "supporter" ON "supporter"."issue_id" = "issue"."id"
  JOIN "direct_interest_snapshot"
    ON  "direct_interest_snapshot"."issue_id" = "issue"."id"
    AND "direct_interest_snapshot"."event" = "issue"."latest_snapshot_event"
    AND "direct_interest_snapshot"."member_id" = "supporter"."member_id"
  WHERE "issue"."state" = 'admission'::"issue_state";

COMMENT ON VIEW "issue_supporter_in_admission_state" IS 'Helper view for "lf_update_issue_order" to allow a (proportional) ordering of issues within an area';

COMMIT;
