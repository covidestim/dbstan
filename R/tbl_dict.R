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
