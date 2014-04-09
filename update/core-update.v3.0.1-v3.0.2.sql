BEGIN;

CREATE OR REPLACE VIEW "liquid_feedback_version" AS
  SELECT * FROM (VALUES ('3.0.2', 3, 0, 2))
  AS "subquery"("string", "major", "minor", "revision");

TODO

COMMIT;
