BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('2.2.6', 2, 2, 6))
  AS "subquery"("string", "major", "minor", "revision");

CREATE TABLE "issue_order" (
        "id"                    INT8            PRIMARY KEY, --REFERENCES "issue" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
        "order_in_admission_state" INT4,
        "order_in_open_states"  INT4 );

COMMENT ON TABLE "issue_order" IS 'Ordering information for issues that are not stored in the "issue" table to avoid locking of multiple issues at once';

COMMENT ON COLUMN "issue_order"."id"                       IS 'References "issue" ("id") but has no referential integrity trigger associated, due to performance/locking issues';
COMMENT ON COLUMN "issue_order"."order_in_admission_state" IS 'To be used for sorting issues within an area, when showing only issues in admission state; NULL values sort last; updated by "lf_update_issue_order"';
COMMENT ON COLUMN "issue_order"."order_in_open_states"     IS 'To be used for sorting issues within an area, when showing all open issues; NULL values sort last; updated by "lf_update_issue_order"';

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

CREATE VIEW "open_issues_ordered_with_minimum_position" AS
  SELECT
    "area_id",
    "id" AS "issue_id",
    "order_in_admission_state" * 2 - 1 AS "minimum_position"
  FROM "issue" NATURAL LEFT JOIN "issue_order"
  WHERE "closed" ISNULL
  ORDER BY
    coalesce(
      "fully_frozen" + "voting_time",
      "half_frozen" + "verification_time",
      "accepted" + "discussion_time",
      "created" + "admission_time"
    ) - now();

COMMENT ON VIEW "open_issues_ordered_with_minimum_position" IS 'Helper view for "lf_update_issue_order" to allow a (mixed) ordering of issues within an area';

COMMIT;
