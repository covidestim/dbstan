get_run_info <- function(sf, id) {

  # Returns per-chain warmup and sampling times
  elapsed_matrix <- rstan::get_elapsed_time(sf)
  elapsed_tibble <- tibble::as_tibble(elapsed_matrix, rownames = 'chain')

  # Get numeric values (`get_elapsed_time` returns character vectors)
  elapsed_tibble$chain = as.numeric(stringr::str_remove_all(
    elapsed_tibble$chain, 'chain:'
  ))

  tibble::tibble(
    id,

    # This seems to be the name of the stan file, minus the extension
    model_name = sf@model_name,

    # Parse their weird date format
    date       = as.Date(sf@date, format = "%a %b %d %H:%M:%S %Y"),
    duration   = jsonlite::toJSON(elapsed_tibble),
    mode       = sf@mode,

    # There are `nchains` elements in `sf@stan_args` but I think they are 
    # always identical so we will just use the first one and convert it to
    # JSON.
    stan_args  = jsonlite::toJSON(sf@stan_args[[1]], auto_unbox=T),

    # Number of chains
    chains     = length(sf@stan_args)
  ) -> d

  d
}

get_optimizing_run_info <- function(r, id) {
  tibble::tibble(
    id,
    return_code = r$return_code,
    log_posterior = r$value
  )
}

get_model_pars <- function(sf, id) {
  tibble::tibble(
    id,
    par = names(sf@par_dims),

    # Scalar parameters are assigned a length of zero, in order to 
    # differentiate them from arrays.
    dim = purrr::map_dbl(sf@par_dims, ~ifelse(identical(., numeric(0)), 0, c(.)))
  )
}

get_stanmodel <- function(sf, id) {
  # Just a string
  code <- rstan::get_stancode(sf)

  tibble::tibble(id, code)
}

summary_var_mapping <- c(
  # RStan's default quantile naming scheme is incompatible with SQL, here we
  # rename
  "2.5%"  = "p2_5",
  "25%"   = "p25",
  "50%"   = "p50",
  "75%"   = "p75",
  "97.5%" = "p97_5",
  "Rhat"  = "rhat"
)

# Matches the Stan syntax for indexing into an `array_name123[1]` and captures
# the variable name and index.
array_bracket_regex <- '^([A-Za-z_][A-Za-z_0-9]*)(?:\\[([0-9]+)\\])?$'

get_summary <- function(sf, id) {
  d <- tibble::as_tibble(rstan::summary(sf)$summary, rownames = 'par')

  matched <- stringr::str_match(d$par, array_bracket_regex)

  # `idx` for scalars is 0, 1-based indexing for all vectors/arrays.
  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)
  d <- dplyr::rename_with(d, ~ifelse(is.na(summary_var_mapping[.]), ., summary_var_mapping[.]))

  d
}

# Per-chain summaries
get_c_summary <- function(sf, id) {
  d <- tibble::as_tibble(rstan::summary(sf)$c_summary, rownames = 'par')

  matched <- stringr::str_match(d$par, array_bracket_regex)

  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)

  # Deal with odd schema - marshal data into a 1row=1observation format
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

get_optimizing_summary <- function(r, id) {
  d <- tibble::tibble(
    par = names(r$par),
    point_est = r$par
  )                  

  matched <- stringr::str_match(d$par, array_bracket_regex)

  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)

  d
}

get_samples <- function(sf, id) {

  rstan::extract(sf, permuted = F) -> sf_mat

  niter   <- dim(sf_mat)[1]
  nchains <- dim(sf_mat)[2]

  # Extract samples of all parameters for a given iteration
  rows_for_iteration <- function(iter_num)
    purrr::map_dfr(1:nchains, ~dplyr::mutate(
      tibble::as_tibble(sf_mat[iter_num, ., ], rownames = 'par'),
      chain = .,
      iter = iter_num
    ))

  d <- purrr::map_dfr(1:niter, rows_for_iteration)

  array_bracket_regex <- '^([A-Za-z_][A-Za-z_0-9]*)(?:\\[([0-9]+)\\])?$'

  matched <- stringr::str_match(d$par, array_bracket_regex)

  idx <- ifelse(
    is.na(matched[,3]),
    0,
    as.numeric(matched[,3])
  )

  d <- dplyr::mutate(d, id, par = matched[,2], idx)

  d
}

get_log_posterior <- function(sf, id) {
  lp <- rstan::get_logposterior(sf)

  purrr::imap_dfr(
    lp,
    ~tibble::tibble(id, chain = .y, iter = 1:length(.x), value = .x)
  )
}

#' @importFrom magrittr %>%
get_sampler_params_ <- function(sf, id) {

  # Convert from matrix to tibble
  params <- rstan::get_sampler_params(sf) %>% purrr::map(tibble::as_tibble)

  # Note the changing variable names
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

get_table_entries <- function(sf, id, progress = T, includeSamples = F) {

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

  # Don't build the sample tibble unless neccessary
  if (identical(includeSamples, T)) {
    samples <- get_samples(sf, id)
    info(paste0("Generated entries for: {.val samples} ", dims("samples")))
  }

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
    samples        = NULL, # By default `lst$samples` is NULL
    log_posterior  = log_posterior,
    sampler_params = sampler_params
  ) -> lst

  if (identical(includeSamples, T))
    lst$samples <- samples

  lst
}

get_table_entries_optimizing <- function(r, id, progress = T) {

  if (progress)
    info <- cli_alert_success
  else
    info <- function(...) NULL

  dims <- function(df) paste0("({.val {nrow(",df,")}} × {.val {ncol(",df,")}})")

  optimizing_run_info <- get_optimizing_run_info(r, id)
  info(paste0("Generated entries for: {.val optimizing_run_info} ", dims("optimizing_run_info")))

  optimizing_summary <- get_optimizing_summary(r, id)
  info(paste0("Generated entries for: {.val optimizing_summary} ", dims("optimizing_summary")))

  list(
    optimizing_run_info = optimizing_run_info,
    optimizing_summary  = optimizing_summary
  )
}

