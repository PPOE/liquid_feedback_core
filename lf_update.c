#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <libpq-fe.h>

int main(int argc, char **argv) {
  int i, count;
  char *conninfo;
  PGconn *db;
  PGresult *list;
  PGresult *status;
  if (argc == 0) return 1;
  if (argc == 1 || !strcmp(argv[1], "-h") || !strcmp(argv[1], "--help")) {
    FILE *out;
    out = argc == 1 ? stderr : stdout;
    fprintf(stdout, "\n");
    fprintf(stdout, "Usage: %s <conninfo>\n", argv[0]);
    fprintf(stdout, "\n");
    fprintf(stdout, "<conninfo> is specified by PostgreSQL's libpq,\n");
    fprintf(stdout, "see http://www.postgresql.org/docs/8.4/static/libpq-connect.html\n");
    fprintf(stdout, "\n");
    fprintf(stdout, "Example: %s dbname=liquid_feedback\n", argv[0]);
    fprintf(stdout, "\n");
    return argc == 1 ? 1 : 0;
  }
  {
    size_t len = 0;
    for (i=1; i<argc; i++) len += strlen(argv[i]) + 1;
    conninfo = malloc(len * sizeof(char));
    if (!conninfo) {
      fprintf(stderr, "Error: Could not allocate memory for conninfo string\n");
      return 1;
    }
    conninfo[0] = 0;
    for (i=1; i<argc; i++) {
      if (i>1) strcat(conninfo, " ");
      strcat(conninfo, argv[i]);
    }
  }
  db = PQconnectdb(conninfo);
  if (!db) {
    fprintf(stderr, "Error: Could not create database handle\n");
    return 1;
  }
  if (PQstatus(db) != CONNECTION_OK) {
    fprintf(stderr, "Could not open connection:\n%s", PQerrorMessage(db));
    return 1;
  }
  list = PQexec(db, "SELECT \"id\" FROM \"open_issue\"");
  if (!list) {
    fprintf(stderr, "Error in pqlib while sending SQL command selecting open issues\n");
    return 1;
  }
  if (PQresultStatus(list) != PGRES_TUPLES_OK) {
    fprintf(stderr, "Error while executing SQL command selecting open issues:\n%s", PQresultErrorMessage(list));
    return 1;
  }
  count = PQntuples(list);
  for (i=0; i<count; i++) {
    const char *params[1];
    params[0] = PQgetvalue(list, i, 0);
    status = PQexecParams(
      db, "SELECT \"check_issue\"($1)", 1, NULL, params, NULL, NULL, 0
    );
    if (
      PQresultStatus(status) != PGRES_COMMAND_OK &&
      PQresultStatus(status) != PGRES_TUPLES_OK
    ) {
      fprintf(stderr, "Error while calling SQL function \"check_issue\"(...):\n%s", PQresultErrorMessage(status));
      return 1;
    }
    PQclear(status);
  }
  PQclear(list);
  list = PQexec(db, "SELECT \"id\" FROM \"issue_with_ranks_missing\"");
  if (!list) {
    fprintf(stderr, "Error in pqlib while sending SQL command selecting issues where ranks are missing\n");
    return 1;
  }
  if (PQresultStatus(list) != PGRES_TUPLES_OK) {
    fprintf(stderr, "Error while executing SQL command selecting issues where ranks are missing:\n%s", PQresultErrorMessage(list));
    return 1;
  }
  count = PQntuples(list);
  for (i=0; i<count; i++) {
    const char *params[1];
    params[0] = PQgetvalue(list, i, 0);
    status = PQexecParams(
      db, "SELECT \"calculate_ranks\"($1)", 1, NULL, params, NULL, NULL, 0
    );
    if (
      PQresultStatus(status) != PGRES_COMMAND_OK &&
      PQresultStatus(status) != PGRES_TUPLES_OK
    ) {
      fprintf(stderr, "Error while calling SQL function \"calculate_ranks\"(...):\n%s", PQresultErrorMessage(status));
      return 1;
    }
    PQclear(status);
  }
  PQclear(list);
  PQfinish(db);
  return 0;
}
