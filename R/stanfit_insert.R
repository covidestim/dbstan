get_run_id <- function(conn) {
  query <- 'insert into stanfit.run_ids default values returning id'
  
  result <- DBI::dbGetQuery(conn, query)

  result$id
}

tryInsert <- function(conn, name, value, progress = TRUE) {
  tryCatch({
    result <- DBI::dbAppendTable(conn, name, value)
    
    printableTableName <- DBI::dbQuoteIdentifier(conn, name)

    if (progress)
      cli_alert_success("Completed insertions into: {.val {printableTableName}}")

    return(result)
  },
  error = function(cond) {
    message(
      "Error occurred during insertion into table '",
      DBI::dbQuoteIdentifier(conn, name), "':"
    )

    cli::cli_alert_warning("Aborting transaction")
    DBI::dbRollback(conn)

    message(cond)
  })
}

#' @importFrom cli cli_h2 cli_alert_success cli_h3 cli_alert_info
#' @export
stanfit_insert <- function(sf, conn, schema = "stanfit") {

  # -- Begin transaction ------------------------------------------------------
  DBI::dbBegin(conn)
  cli_h2("Beginning transaction")

  id <- get_run_id(conn)
  cli_alert_success("Assigned run id: {.bold {id}}")

  cli_h3("Generating tables")

  tryCatch({
    tables <- get_table_entries(sf, id, progress = TRUE)
  },
  error = function(cond) {
    message(cond)
    cli::cli_alert_warning("Aborting transaction")
    
    return(DBI::dbRollback(conn))
  })

  cli_h3("Performing insertions")

  tryInsert(conn, DBI::Id(schema = schema, table = "run_info"),       tables$run_info)
  tryInsert(conn, DBI::Id(schema = schema, table = "model_pars"),     tables$model_pars)
  tryInsert(conn, DBI::Id(schema = schema, table = "stanmodel"),      tables$stanmodel)
  tryInsert(conn, DBI::Id(schema = schema, table = "summary"),        tables$summary)
  tryInsert(conn, DBI::Id(schema = schema, table = "c_summary"),      tables$c_summary)
  tryInsert(conn, DBI::Id(schema = schema, table = "log_posterior"),  tables$log_posterior)
  tryInsert(conn, DBI::Id(schema = schema, table = "sampler_params"), tables$sampler_params)

  DBI::dbCommit(conn)
  cli_h2("Transaction successful!")

  cli_alert_info(
    "Retrieve this run's data by invoking {.code get_stanfit({id}, conn)}"
  )
  # -- End transaction --------------------------------------------------------

  # id of inserted run is returned invisibly
  invisible(id)
}

#' @importFrom cli cli_h2 cli_alert_success cli_h3 cli_alert_info
#' @export
optimizing_insert <- function(r, conn, schema = "stanfit") {

  # -- Begin transaction ------------------------------------------------------
  DBI::dbBegin(conn)
  cli_h2("Beginning transaction")

  id <- get_run_id(conn)
  cli_alert_success("Assigned run id: {.bold {id}}")

  cli_h3("Generating tables")

  tryCatch({
    tables <- get_table_entries_optimizing(r, id, progress = TRUE)
  },
  error = function(cond) {
    message(cond)
    cli::cli_alert_warning("Aborting transaction")
    
    return(DBI::dbRollback(conn))
  })

  cli_h3("Performing insertions")

  tryInsert(conn, DBI::Id(schema = schema, table = "optimizing_run_info"), tables$optimizing_run_info)
  tryInsert(conn, DBI::Id(schema = schema, table = "optimizing_summary"),  tables$optimizing_summary)

  DBI::dbCommit(conn)
  cli_h2("Transaction successful!")

  cli_alert_info(
    "Retrieve this run's data by invoking {.code get_optimizing({id}, conn)}"
  )
  # -- End transaction --------------------------------------------------------

  # id of inserted run is returned invisibly
  invisible(id)
}
