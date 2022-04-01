get_run_id <- function(conn, method = "sampling") {
  # This asks the database to decide on a new `$id` number, and give it to us
  query <-
    paste0("insert into stanfit.run_ids (method) values ('", method, "') returning id")
  
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
    DBI::dbRollback(conn) # Rollback the transaction on failure

    message(cond)
  },
  interrupt = function(cond) {
    message(
      "Error occurred during insertion into table '",
      DBI::dbQuoteIdentifier(conn, name), "':"
    )

    message(cond)
    cli::cli_alert_warning("Aborting transaction")
    
    return(DBI::dbRollback(conn))
  })
}

#' Insert a sampled run into the database
#'
#' Given a sampled model and a database connection, `stanfit_insert` will
#' preprocess the run into a relational format and insert it into the database.
#' This operation is expressed as a SQL transaction and thus the transaction
#' will be rolled-back if an error occurs.
#'
#' @return The unique ID of the inserted run
#' @param sf The return value of a call to `rstan::optimizing`
#' @param conn A `DBI::DBConnection` object, the return value of a call to `DBI::dbConnect` 
#' @param schema A string, the name of the schema in your database where dbstan tables are stored
#' @param includeSamples A logical, default `false`, whether or not to include
#'   samples in the database insert. This should be a carefully considered
#'   decision because depending on model size and number of iterations, the
#'   samples can easily take up **2GB+** disk space. For large models with many
#'   iterations, expect `stanfit_insert()` to take 10-30 minutes, depending
#'   on the model size/iterations, network uplink, and other factors.
#' @seealso [optimizing_insert]
#' @importFrom cli cli_h2 cli_alert_success cli_h3 cli_alert_info
#' @export
stanfit_insert <- function(sf, conn, schema = "stanfit", includeSamples = FALSE) {

  # -- Begin transaction ------------------------------------------------------
  DBI::dbBegin(conn)
  cli_h2("Beginning transaction")

  id <- get_run_id(conn)
  cli_alert_success("Assigned run id: {.bold {id}}")

  cli_h3("Generating tables")

  tryCatch({
    tables <- get_table_entries(sf, id, progress = TRUE, includeSamples = includeSamples)
  },
  error = function(cond) {
    message(cond)
    cli::cli_alert_warning("Aborting transaction")
    
    return(DBI::dbRollback(conn))
  },
  interrupt = function(cond) {
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

  if (!is.null(tables$samples)) {
    cli::cli_alert_warning("Beginning insertion of samples. This will take a while.")
    tryInsert(conn, DBI::Id(schema = schema, table = "samples"),      tables$samples)
  }

  tryInsert(conn, DBI::Id(schema = schema, table = "log_posterior"),  tables$log_posterior)
  tryInsert(conn, DBI::Id(schema = schema, table = "sampler_params"), tables$sampler_params)

  DBI::dbCommit(conn)
  cli_h2("Transaction successful!")

  cli_alert_info(
    "Retrieve this run's data by invoking {.code get_stanfit({id}, conn)}"
  )
  # -- End transaction --------------------------------------------------------

  # id of inserted run is returned invisibly
  id
}

#' Insert an optimization run into the database
#'
#' Given an optimized model and a database connection, `optimizing_insert` will
#' preprocess the run into a relational format and insert it into the database.
#' This operation is expressed as a SQL transaction and thus the transaction
#' will be rolled-back if an error occurs.
#'
#' @return The unique ID of the inserted run
#' @param r The return value of a call to `rstan::optimizing`
#' @param conn A `DBI::DBConnection` object, the return value of a call to `DBI::dbConnect` 
#' @param schema A string, the name of the schema in your database where dbstan tables are stored
#' @seealso [stanfit_insert]
#' @export
optimizing_insert <- function(r, conn, schema = "stanfit") {

  # -- Begin transaction ------------------------------------------------------
  DBI::dbBegin(conn)
  cli_h2("Beginning transaction")

  id <- get_run_id(conn, method = "optimizing")
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

  # id of inserted run is returned
  id
}
