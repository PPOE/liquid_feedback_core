BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('2.2.6', 2, 2, 6))
  AS "subquery"("string", "major", "minor", "revision");

ALTER TABLE "issue" ADD COLUMN "order_in_admission_state" INT4;
ALTER TABLE "issue" ADD COLUMN "order_in_open_states"     INT4;

COMMENT ON COLUMN "issue"."order_in_admission_state" IS 'To be used for sorting issues within an area, when showing only issues in admission state; NULL values sort last; updated by "lf_update_issue_order"';
COMMENT ON COLUMN "issue"."order_in_open_states"     IS 'To be used for sorting issues within an area, when showing all open issues; NULL values sort last; updated by "lf_update_issue_order"';

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
