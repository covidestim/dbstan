get_run_id <- function(sf, id) {

}

get_run_info <- function(sf, id) {

  elapsed_matrix <- rstan::get_elapsed_time(sf)
  elapsed_tibble <- tibble::as_tibble(elapsed_matrix, rownames = 'chain')

  elapsed_tibble$chain = as.numeric(stringr::str_remove_all(
    elapsed_tibble$chain, 'chain:'
  ))

  tibble::tibble(
    id,
    model_name = sf@model_name,
    date       = as.Date(sf@date, format = "%a %b %d %H:%M:%S %Y"),
    duration   = jsonlite::toJSON(elapsed_tibble),
    mode       = sf@mode,
    stan_args  = jsonlite::toJSON(sf@stan_args[[1]], auto_unbox=T),
    chains     = length(sf@stan_args)
  ) -> d

  d
}

get_model_pars <- function(sf, id) {
  tibble::tibble(
    id,
    par = names(sf@par_dims),
    dim = purrr::map_dbl(sf@par_dims, ~ifelse(identical(., numeric(0)), 0, c(.)))
  )
}

get_stanmodel <- function(sf, id) {
  code <- rstan::get_stancode(sf)

  tibble::tibble(id, code)
}

summary_var_mapping <- c(
  "2.5%"  = "p2_5",
  "25%"   = "p25",
  "50%"   = "p50",
  "75%"   = "p75",
  "97.5%" = "p97_5",
  "Rhat"  = "rhat"
)

array_bracket_regex <- '^([A-Za-z_][A-Za-z_0-9]*)(?:\\[([0-9]+)\\])?$'

get_summary <- function(sf, id) {
  d <- tibble::as_tibble(rstan::summary(sf)$summary, rownames = 'par')

  matched <- stringr::str_match(d$par, array_bracket_regex)

  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)
  d <- dplyr::rename_with(d, ~ifelse(is.na(summary_var_mapping[.]), ., summary_var_mapping[.]))

  d
}

get_c_summary <- function(sf, id) {
  d <- tibble::as_tibble(rstan::summary(sf)$c_summary, rownames = 'par')

  matched <- stringr::str_match(d$par, array_bracket_regex)

  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)

  d <- tidyr::pivot_longer(d, tidyselect::matches('[A-Za-z0-9_.%]+.chain:[0-9][0-9]*')) 
  d <- tidyr::separate(d, name, into = c('metric', 'chain'), sep = '.chain:') 

  d <- dplyr::mutate(
    d,
    chain = as.numeric(chain),
    metric = ifelse(is.na(summary_var_mapping[metric]), metric, summary_var_mapping[metric])
  ) 

  d <- tidyr::pivot_wider(d, names_from = 'metric', values_from = 'value')

  d
}

#' @importFrom magrittr %>%
get_log_posterior <- function(sf, id) {
  lp <- rstan::get_logposterior(sf)

  purrr::imap_dfr(
    lp,
    ~tibble::tibble(id, chain = .y, iter = 1:length(.x), value = .x)
  )
}

get_sampler_params_ <- function(sf, id) {

  # Convert from matrix to tibble
  params <- rstan::get_sampler_params(sf) %>% purrr::map(tibble::as_tibble)

  purrr::imap_dfr(
    params,
    ~tibble::tibble(
      id,
      chain = .y,
      iter = 1:nrow(.x),
      accept_stat = .x$accept_stat__,
      stepsize    = .x$stepsize__,
      treedepth   = .x$treedepth__,
      n_leapfrog  = .x$n_leapfrog__,
      divergent   = .x$divergent__,
      energy      = .x$energy__,
    )
  )
}

get_table_entries <- function(sf, id, progress = T) {

  if (progress)
    info <- cli_alert_success
  else
    info <- function(...) NULL

  dims <- function(df) paste0("({.val {nrow(",df,")}} × {.val {ncol(",df,")}})")

  run_info <- get_run_info(sf, id)
  info(paste0("Generated entries for: {.val run_info} ", dims("run_info")))

  model_pars <- get_model_pars(sf, id)
  info(paste0("Generated entries for: {.val model_pars} ", dims("model_pars")))

  stanmodel <- get_stanmodel(sf, id)
  info(paste0("Generated entries for: {.val stanmodel} ", dims("stanmodel")))

  summary_ <- get_summary(sf, id)
  info(paste0("Generated entries for: {.val summary} ", dims("summary_")))

  c_summary <- get_c_summary(sf, id)
  info(paste0("Generated entries for: {.val c_summary} ", dims("c_summary")))

  log_posterior <- get_log_posterior(sf, id)
  info(paste0("Generated entries for: {.val log_posterior} ", dims("log_posterior")))

  sampler_params <- get_sampler_params_(sf, id)
  info(paste0("Generated entries for: {.val sampler_params} ", dims("sampler_params")))

  list(
    run_info       = run_info,
    model_pars     = model_pars,
    stanmodel      = stanmodel,
    summary        = summary_,
    c_summary      = c_summary,
    log_posterior  = log_posterior,
    sampler_params = sampler_params
  )
}

