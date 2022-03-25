#' @importFrom dplyr tbl
#' @importFrom dbplyr in_schema
#' @importFrom cli cli_ol cli_ul cli_li cli_end cli_h2 cli_h1 cli_vec
#' @importFrom magrittr %>%
#' @export
get_stanfit <- function(id, conn, schema = "stanfit") {

  id_ <- id

  filter_id <- function(df) dplyr::filter(df, id == id_)

  dims <- function(dbtbl) list(
    nrow = dplyr::pull(dplyr::tally(dbtbl), n),
    ncol = ncol(dbtbl)
  )


  list(
    run_info       = tbl(conn, in_schema(schema, "run_info"))       %>% filter_id,
    model_pars     = tbl(conn, in_schema(schema, "model_pars"))     %>% filter_id,
    stanmodel      = tbl(conn, in_schema(schema, "stanmodel"))      %>% filter_id,
    summary        = tbl(conn, in_schema(schema, "summary"))        %>% filter_id,
    c_summary      = tbl(conn, in_schema(schema, "c_summary"))      %>% filter_id,
    samples        = tbl(conn, in_schema(schema, "samples"))        %>% filter_id,
    log_posterior  = tbl(conn, in_schema(schema, "log_posterior"))  %>% filter_id,
    sampler_params = tbl(conn, in_schema(schema, "sampler_params")) %>% filter_id
  ) -> tbls

  stan_args <- dplyr::pull(tbls$run_info, stan_args) %>% jsonlite::fromJSON(.)
  chains <- dplyr::pull(tbls$run_info, chains)
  completed_date <- dplyr::pull(tbls$run_info, date)

  cli_h1("ID[{id_}] ({.val {completed_date}}), {.val {chains}} chains, {.val {stan_args$warmup}} + {.val {stan_args$iter - stan_args$warmup}} iterations")

  cli_h2("Model: {.val {dplyr::pull(tbls$run_info, model_name)}}, {.val {stringr::str_count(dplyr::pull(tbls$stanmodel, code), '\n')}} loc")

  if (dims(tbls$samples)$nrow == 0)
    cli::cli_alert_warning("No samples available for this run")

  cli_h2("Chain summary")
  cli_ol()
  purrr::pwalk(
    jsonlite::fromJSON(dplyr::pull(tbls$run_info, duration)),
    function (warmup, sample, ...) cli_li("ran for {.val {prettyunits::pretty_sec(warmup + sample)}}, ({.val {scales::label_percent()(warmup/(warmup+sample))}} was warmup)")
  )
  cli_end()

  cli_h2("Tables")
  cli_ul()
  purrr::iwalk(tbls, ~cli_li("{.field ${.y}}:\t {.val {dims(.x)$nrow}} × {.val {dims(.x)$ncol}} - {cli_vec(cli::bg_white(cli::col_black((colnames(.x)))), list(vec_sep=', ', vec_last=', '))}"))
  cli_end()

  invisible(tbls)
}

#' @importFrom dplyr tbl
#' @importFrom dbplyr in_schema
#' @importFrom cli cli_ul cli_li cli_end cli_h2 cli_h1 cli_vec
#' @importFrom magrittr %>%
#' @export
get_optimizing <- function(id, conn, schema = "stanfit") {

  id_ <- id

  filter_id <- function(df) dplyr::filter(df, id == id_)

  list(
    optimizing_run_info = tbl(conn, in_schema(schema, "optimizing_run_info"))       %>% filter_id,
    optimizing_summary  = tbl(conn, in_schema(schema, "optimizing_summary"))        %>% filter_id
  ) -> tbls

  log_posterior <- dplyr::pull(tbls$optimizing_run_info, log_posterior)

  cli_h1("ID[{id_}] (log_posterior {.val {log_posterior}})")

  dims <- function(dbtbl) list(
    nrow = dplyr::pull(dplyr::tally(dbtbl), n),
    ncol = ncol(dbtbl)
  )

  cli_h2("Tables")
  cli_ul()
  purrr::iwalk(tbls, ~cli_li("{.field ${.y}}:\t {.val {dims(.x)$nrow}} × {.val {dims(.x)$ncol}} - {cli_vec(cli::bg_white(cli::col_black(colnames(.x))), list(vec_sep=', ', vec_last=', '))}"))
  cli_end()

  invisible(tbls)
}
