count = 0;
function incCount() {
   count += 1;
   return 0;
}

dbpath="./testdata/Chinook_Sqlite.sqlite";
DoSQL ( SQL_OPEN, dbpath, DBID );
DoSQL ( DBID, "SELECT * FROM Album", "return incCount()");

assert(count==347, "Number of Rows failed");
assert(Columns(SQL_COLUMN_NAMES)==3, "Number of Column Names failed");

DoSQL ( SQL_CLOSE, "", DBID );

fprintf (stdout, "TEST PASSED");