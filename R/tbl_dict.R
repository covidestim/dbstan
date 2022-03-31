#' Return a dictionary of tables containing dbstan results
#'
#' Given a database connection `conn` and a database schema name `schema`,
#' `tbl_dict()` returns a keyed list, where the key names are the tables, and
#' the values are `dbplyr`-backed tibbles.
#'
#' @return A list of tables:
#' - `run_ids`    
#' - `run_info`           
#' - `optimizing_run_info`
#' - `model_pars`         
#' - `stanmodel`          
#' - `summary`            
#' - `c_summary`          
#' - `samples`            
#' - `optimizing_summary` 
#' - `log_posterior`      
#' - `sampler_params`     
#' @param conn A `DBI::DBConnection` object, the return value of a call to `DBI::dbConnect` 
#' @param schema A string, the name of the schema in your database where dbstan tables are stored
#' @seealso [get_stanfit] Returns tables specific to a particular Stan run.
#' @importFrom dplyr tbl
#' @importFrom dbplyr in_schema
#' @export
tbl_dict <- function(conn, schema = "stanfit") {
  list(
    run_ids             = tbl(conn, in_schema(schema, "run_ids")),
    run_info            = tbl(conn, in_schema(schema, "run_info")),
    optimizing_run_info = tbl(conn, in_schema(schema, "optimizing_run_info")),
    model_pars          = tbl(conn, in_schema(schema, "model_pars")),
    stanmodel           = tbl(conn, in_schema(schema, "stanmodel")),
    summary             = tbl(conn, in_schema(schema, "summary")),
    c_summary           = tbl(conn, in_schema(schema, "c_summary")),
    samples             = tbl(conn, in_schema(schema, "samples")),
    optimizing_summary  = tbl(conn, in_schema(schema, "optimizing_summary")),
    log_posterior       = tbl(conn, in_schema(schema, "log_posterior")),
    sampler_params      = tbl(conn, in_schema(schema, "sampler_params"))
  )
}
