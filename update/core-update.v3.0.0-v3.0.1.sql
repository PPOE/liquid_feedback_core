BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('3.0.1', 3, 0, 1))
  AS "subquery"("string", "major", "minor", "revision");

ALTER TABLE "initiative" ADD COLUMN "first_preference_votes" INT4;

ALTER TABLE "initiative" DROP CONSTRAINT "non_admitted_initiatives_cant_contain_voting_results";
ALTER TABLE "initiative" ADD CONSTRAINT "non_admitted_initiatives_cant_contain_voting_results" CHECK (
          ( "admitted" NOTNULL AND "admitted" = TRUE ) OR
          ( "first_preference_votes" ISNULL AND
            "positive_votes" ISNULL AND "negative_votes" ISNULL AND
            "direct_majority" ISNULL AND "indirect_majority" ISNULL AND
            "schulze_rank" ISNULL AND
            "better_than_status_quo" ISNULL AND "worse_than_status_quo" ISNULL AND
            "reverse_beat_path" ISNULL AND "multistage_majority" ISNULL AND
            "eligible" ISNULL AND "winner" ISNULL AND "rank" ISNULL ) );

COMMENT ON COLUMN "initiative"."first_preference_votes" IS 'Number of direct and delegating voters who ranked this initiative as their first choice';
COMMENT ON COLUMN "initiative"."positive_votes"         IS 'Number of direct and delegating voters who ranked this initiative better than the status quo';
COMMENT ON COLUMN "initiative"."negative_votes"         IS 'Number of direct and delegating voters who ranked this initiative worse than the status quo';

-- UPDATE TABLE "vote" SET "grade" = 0 WHERE "grade" ISNULL;  -- should not be necessary
ALTER TABLE "vote" ALTER COLUMN "grade" SET NOT NULL;

ALTER TABLE "vote" ADD COLUMN "first_preference" BOOLEAN;

ALTER TABLE "vote" ADD
        CONSTRAINT "first_preference_flag_only_set_on_positive_grades"
        CHECK ("grade" > 0 OR "first_preference" ISNULL);

COMMENT ON COLUMN "vote"."first_preference" IS 'Value is automatically set after voting is finished. For positive grades, this value is set to true for the highest (i.e. best) grade.';
 
INSERT INTO "temporary_transaction_data" ("key", "value")
  VALUES ('override_protection_triggers', TRUE::TEXT);

UPDATE "vote" SET "first_preference" = "subquery"."first_preference"
  FROM (
    SELECT
      "vote"."initiative_id",
      "vote"."member_id",
      CASE WHEN "vote"."grade" > 0 THEN
        CASE WHEN "vote"."grade" = max("agg"."grade") THEN TRUE ELSE FALSE END
      ELSE NULL
      END AS "first_preference"
    FROM "vote"
    JOIN "initiative"  -- NOTE: due to missing index on issue_id
    ON "vote"."issue_id" = "initiative"."issue_id"
    JOIN "vote" AS "agg"
    ON "initiative"."id" = "agg"."initiative_id"
    AND "vote"."member_id" = "agg"."member_id"
    GROUP BY "vote"."initiative_id", "vote"."member_id"
  ) AS "subquery"
  WHERE "vote"."initiative_id" = "subquery"."initiative_id"
  AND "vote"."member_id" = "subquery"."member_id";

DELETE FROM "temporary_transaction_data"
  WHERE "key" = 'override_protection_triggers';

UPDATE "initiative"
  SET "first_preference_votes" = coalesce("subquery"."sum", 0)
  FROM (
    SELECT "vote"."initiative_id", sum("direct_voter"."weight")
    FROM "vote" JOIN "direct_voter"
    ON "vote"."issue_id" = "direct_voter"."issue_id"
    AND "vote"."member_id" = "direct_voter"."member_id"
    WHERE "vote"."first_preference"
    GROUP BY "vote"."initiative_id"
  ) AS "subquery"
  WHERE "initiative"."admitted"
  AND "initiative"."id" = "subquery"."initiative_id";

-- reconstruct battle data to avoid future data loss when
-- executing "clean_issue" to delete voting data:
INSERT INTO "battle" (
    "issue_id",
    "winning_initiative_id",
    "losing_initiative_id",
    "count"
  ) SELECT
    "battle_view"."issue_id",
    "battle_view"."winning_initiative_id",
    "battle_view"."losing_initiative_id",
    "battle_view"."count"
  FROM "battle_view"
  LEFT JOIN "battle"
  ON "battle_view"."winning_initiative_id" = "battle"."winning_initiative_id"
  AND "battle_view"."losing_initiative_id" = "battle"."losing_initiative_id"
  -- NOTE: comparisons with status-quo are intentionally omitted to mark
  --       issues that were counted prior LiquidFeedback Core v2.0.0
  WHERE "battle" ISNULL;

CREATE OR REPLACE FUNCTION "close_voting"("issue_id_p" "issue"."id"%TYPE)
  RETURNS VOID
  LANGUAGE 'plpgsql' VOLATILE AS $$
    DECLARE
      "area_id_v"   "area"."id"%TYPE;
      "unit_id_v"   "unit"."id"%TYPE;
      "member_id_v" "member"."id"%TYPE;
    BEGIN
      PERFORM "require_transaction_isolation"();
      SELECT "area_id" INTO "area_id_v" FROM "issue" WHERE "id" = "issue_id_p";
      SELECT "unit_id" INTO "unit_id_v" FROM "area"  WHERE "id" = "area_id_v";
      -- override protection triggers:
      INSERT INTO "temporary_transaction_data" ("key", "value")
        VALUES ('override_protection_triggers', TRUE::TEXT);
      -- delete timestamp of voting comment:
      UPDATE "direct_voter" SET "comment_changed" = NULL
        WHERE "issue_id" = "issue_id_p";
      -- delete delegating votes (in cases of manual reset of issue state):
      DELETE FROM "delegating_voter"
        WHERE "issue_id" = "issue_id_p";
      -- delete votes from non-privileged voters:
      DELETE FROM "direct_voter"
        USING (
          SELECT
            "direct_voter"."member_id"
          FROM "direct_voter"
          JOIN "member" ON "direct_voter"."member_id" = "member"."id"
          LEFT JOIN "privilege"
          ON "privilege"."unit_id" = "unit_id_v"
          AND "privilege"."member_id" = "direct_voter"."member_id"
          WHERE "direct_voter"."issue_id" = "issue_id_p" AND (
            "member"."active" = FALSE OR
            "privilege"."voting_right" ISNULL OR
            "privilege"."voting_right" = FALSE
          )
        ) AS "subquery"
        WHERE "direct_voter"."issue_id" = "issue_id_p"
        AND "direct_voter"."member_id" = "subquery"."member_id";
      -- consider delegations:
      UPDATE "direct_voter" SET "weight" = 1
        WHERE "issue_id" = "issue_id_p";
      PERFORM "add_vote_delegations"("issue_id_p");
      -- mark first preferences:
      UPDATE "vote" SET "first_preference" = "subquery"."first_preference"
        FROM (
          SELECT
            "vote"."initiative_id",
            "vote"."member_id",
            CASE WHEN "vote"."grade" > 0 THEN
              CASE WHEN "vote"."grade" = max("agg"."grade") THEN TRUE ELSE FALSE END
            ELSE NULL
            END AS "first_preference"
          FROM "vote"
          JOIN "initiative"  -- NOTE: due to missing index on issue_id
          ON "vote"."issue_id" = "initiative"."issue_id"
          JOIN "vote" AS "agg"
          ON "initiative"."id" = "agg"."initiative_id"
          AND "vote"."member_id" = "agg"."member_id"
          GROUP BY "vote"."initiative_id", "vote"."member_id"
        ) AS "subquery"
        WHERE "vote"."issue_id" = "issue_id_p"
        AND "vote"."initiative_id" = "subquery"."initiative_id"
        AND "vote"."member_id" = "subquery"."member_id";
      -- finish overriding protection triggers (avoids garbage):
      DELETE FROM "temporary_transaction_data"
        WHERE "key" = 'override_protection_triggers';
      -- materialize battle_view:
      -- NOTE: "closed" column of issue must be set at this point
      DELETE FROM "battle" WHERE "issue_id" = "issue_id_p";
      INSERT INTO "battle" (
        "issue_id",
        "winning_initiative_id", "losing_initiative_id",
        "count"
      ) SELECT
        "issue_id",
        "winning_initiative_id", "losing_initiative_id",
        "count"
        FROM "battle_view" WHERE "issue_id" = "issue_id_p";
      -- set voter count:
      UPDATE "issue" SET
        "voter_count" = (
          SELECT coalesce(sum("weight"), 0)
          FROM "direct_voter" WHERE "issue_id" = "issue_id_p"
        )
        WHERE "id" = "issue_id_p";
      -- calculate "first_preference_votes":
      UPDATE "initiative"
        SET "first_preference_votes" = coalesce("subquery"."sum", 0)
        FROM (
          SELECT "vote"."initiative_id", sum("direct_voter"."weight")
          FROM "vote" JOIN "direct_voter"
          ON "vote"."issue_id" = "direct_voter"."issue_id"
          AND "vote"."member_id" = "direct_voter"."member_id"
          WHERE "vote"."first_preference"
          GROUP BY "vote"."initiative_id"
        ) AS "subquery"
        WHERE "initiative"."issue_id" = "issue_id_p"
        AND "initiative"."admitted"
        AND "initiative"."id" = "subquery"."initiative_id";
      -- copy "positive_votes" and "negative_votes" from "battle" table:
      UPDATE "initiative" SET
        "positive_votes" = "battle_win"."count",
        "negative_votes" = "battle_lose"."count"
        FROM "battle" AS "battle_win", "battle" AS "battle_lose"
        WHERE
          "battle_win"."issue_id" = "issue_id_p" AND
          "battle_win"."winning_initiative_id" = "initiative"."id" AND
          "battle_win"."losing_initiative_id" ISNULL AND
          "battle_lose"."issue_id" = "issue_id_p" AND
          "battle_lose"."losing_initiative_id" = "initiative"."id" AND
          "battle_lose"."winning_initiative_id" ISNULL;
    END;
  $$;

COMMIT;
