## The `stanfit` object

Results from calls to `rstan::sampling()` or `rstan::stan()` are stored in
`stanfit` objects.  The contents of the object are described in detail
[here][stanfit]. Each object is an [S4][s4] class with a bunch of slots that
represent various parts of the sampling process, like the model code, the
samples drawn from the posterior, and diagnostic messages from the NUTS sampler.

`dbstan` organizes these slots into a relational model. The slots are summarized
below:

- `model_name` Name of the model
- `model_pars` Parameters in the model, including the `generated quantities{}` block and `transformed parameters{}` block
- `par_dims` Dimensions of said paramaeters
- `mode` Status code indicating success or failure of the sampler
- `sim` Matrix containing the individual samples. **`dbstan` does not attempt to load this info into the db due to the size**
- `inits` Initial values of all parameters on the first iteration
- `stan_args` - Arguments for the sampler
- `stanmodel` - Model code, as a `stanmodel` object
- `date` - Date of object creation

### Table `run_ids`

| field | stanfit slot | notes |
|-------|--------------|-------|
| id    | None         |       |

### Table `run_info`

| field      | stanfit slot          | type        | notes                                         |
|------------|-----------------------|-------------|-----------------------------------------------|
| model_name | `@model_name`         | text        | The name of the file, minus the extension     |
| date       | `@date`               | timestamptz | The time the Stanfit object was created       |
| duration   | `get_elapsed_time(r) %>% as_tibble(rownames='chain')` | JSON    | Retval is in SECONDS* |
| mode       | `@mode`               | numeric     |                                               |
| stan_args  | `@stan_args[[1]]`     | JSON        | Take the first chain and represent it as JSON |

\* The `chain` column will be named `chain:[n]` after conversion to tibble format.
Make sure to strip the `'chain:'` part and convert to number!

### Table `model_pars`

| field | stanfit slot        | type    | notes                                            |
|-------|---------------------|---------|--------------------------------------------------|
| id    | None                | serial  | Foreign key?                                     |
| par   | `names(r@par_dims)` | text    | Includes all parameters/transformed ps/generated |
| dim   | `@par_dims`         | numeric | 0 represents scalars                             |

### Table `stanmodel`

| field | stanfit slot      | type   | notes |
|-------|-------------------|--------|-------|
| id    |                   | serial |       |
| code  | `get_stancode(r)` | text   |       |

### Table: `summary`

| field   | stanfit slot                    | type    | notes |
|---------|---------------------------------|---------|-------|
| id      | None                            |         |       |
| par     | `summary(r)$summary$par`        | text    |       |
| idx     | Slightly complicated            | numeric |       |
| mean    | `summary(r)$summary$mean`       | numeric |       |
| se_mean | `summary(r)$summary$se_mean`    | numeric |       |
| sd      | `summary(r)$summary$sd`         | numeric |       |
| P2.5    | `summary(r)$summary[["2.5%"]]`  | numeric |       |
| P25     | `summary(r)$summary[["25%"]]`   | numeric |       |
| P50     | `summary(r)$summary[["50%"]]`   | numeric |       |
| P75     | `summary(r)$summary[["75%"]]`   | numeric |       |
| P97.5   | `summary(r)$summary[["97.5%"]]` | numeric |       |
| n_eff   | `summary(r)$summary$n_eff`      | numeric |       |
| Rhat    | `summary(r)$summary$Rhat`       | numeric |       |

### Table: `c_summary`
                                                            
This one is a little tricky.

- There's no `n_eff` or `Rhat`
- The column names in the object returned by `summary(r)` are dumb, all vars
  except `par` are named `[metric].chain:[n]`. 

| field   | stanfit slot                    | type    | notes |
|---------|---------------------------------|---------|-------|
| id      | None                            |         |       |
| chain   | No exact mapping                |         |       |
| par     | `summary(r)$summary$par`        | text    |       |
| idx     | Slightly complicated            | numeric |       |
| mean    | `summary(r)$summary$mean`       | numeric |       |
| se_mean | `summary(r)$summary$se_mean`    | numeric |       |
| sd      | `summary(r)$summary$sd`         | numeric |       |
| P2.5    | `summary(r)$summary[["2.5%"]]`  | numeric |       |
| P25     | `summary(r)$summary[["25%"]]`   | numeric |       |
| P50     | `summary(r)$summary[["50%"]]`   | numeric |       |
| P75     | `summary(r)$summary[["75%"]]`   | numeric |       |
| P97.5   | `summary(r)$summary[["97.5%"]]` | numeric |       |

### Table: 'log_posterior'

| field | stanfit slot                     | type    | notes |
|-------|----------------------------------|---------|-------|
| id    | None                             | integer |       |
| chain | `get_logposterior(r)[[1,2,...]]` | numeric |       |
| iter  | Row number of vector             | numeric |       |
| value | The vector from each chain       | numeric |       |

### Table: `sampler_params`
                                                            
| field       | stanfit slot                                   | type    | notes |
|-------------|------------------------------------------------|---------|-------|
| id          | None                                           | integer |       |
| chain       | No exact mapping                               | numeric |       |
| iter        | Row number of vector                           | numeric |       |
| accept_stat | `get_sampler_params(r)[[chain]]$accept_stat__` | numeric |       |
| stepsize    | `get_sampler_params(r)[[chain]]$stepsize__`    | numeric |       |
| treedepth   | `get_sampler_params(r)[[chain]]$treedepth__`   | numeric |       |
| n_leapfrog  | `get_sampler_params(r)[[chain]]$n_leapfrog__`  | numeric |       |
| divergent   | `get_sampler_params(r)[[chain]]$divergent__`   | numeric |       |
| energy      | `get_sampler_params(r)[[chain]]$energy__`      | numeric |       |

[stanfit]: FILLME
[s4]: FILLME
