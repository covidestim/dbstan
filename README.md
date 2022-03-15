# dbstan

`dbstan` is glue code for connecting [`rstan::stanfit`][stanfit] objects and
relational databases.  It leverages the [DBI][dbi] package to provide a
DBMS-agnostic interface to INSERT a representation of a `stanfit` object into a
DB, and it also provides a helper method to retrieve a particular `stanfit`
object's information from the DB. This way, you can easily get (batches of)
sampler results into a database, whereupon it usually becomes much easier
to run analyses and share data. For example:

```r
library(rstan)
library(dbstan)

# Establish a DB connection using DBI
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  user = 'postgres',
  password='password',
  host='mydb.vkuzdd798xs.us-east-2.rds.amazonaws.com',
)

# Get samples from any sampled Stan model. Currently only NUTS is supported.
fit1 <- stan(
  file = "schools.stan",  # Stan program
  data = schools_data,    # named list of data
)

id <- stanfit_insert(fit1, conn) # INSERT `stanfit` into db and store the UID

# Retrieve summary as a dbplyr table, backed by our database.
tbl(conn, in_schema('stanfit', 'summary')) %>% filter(id == I(id))
```

This makes it significantly easier to share `stanfit` objects, as well as run
analyses across multiple `stanfit` objects. That's traditionally difficult
to do when working with large objects representing the results from models
that are complex or require large numbers of iterations to effectively sample
from, because it's tricky to store them in RAM or otherwise keep track of
slimmed-down representations of the `stanfit` object across many different
`.RDS` archives.

Tested with Postgres 14.2, but it should work with many other SQL-based
databases.

## Get up and running

1. Execute `init.sql`, which CREATEs a `"stanfit"` schema in your database and
   CREATEs all tables.

2. Make sure you can connect to the database using [`DBI::dbConnect()`][dbconnect].

## Structure of the `stanfit` object

Results from calls to `rstan::sampling()` or `rstan::stan()` are stored in
`stanfit` objects.  The contents of the object are described in detail
[here][stanfit]. Each object is an [S4][s4] class with a bunch of slots that
represent various parts of the sampling process, like the model code, the
samples drawn from the posterior, and diagnostic messages from the NUTS sampler.

`dbstan` organizes these slots into a relational model. The slots are summarized
below:

- `model_name` Name of the model
- `model_pars` Parameters in the model, including the `generated quantities{}`
  block and `transformed parameters{}` block
- `par_dims` Dimensions of said paramaeters
- `mode` Status code indicating success or failure of the sampler
- `sim` Matrix containing the individual samples. **`dbstan` does not currently
  attempt to load this info into the db due to its large size**
- `inits` Initial values of all parameters on the first iteration
- `stan_args` - Arguments for the sampler
- `stanmodel` - Model code, as a `stanmodel` object
- `date` - Date of object creation

## Table schema

The schema can be viewed in `init.sql` - here is a more descriptive mapping
between the `stanfit` object and its relational model.

### Table `run_ids`

This table is an index of all of the `stanfit` objects represented in the
schema.

| field | stanfit slot | notes                                                                |
|-------|--------------|----------------------------------------------------------------------|
| id    | None         | Serial, assigned by the database on insertion using `stanfit_insert` |

### Table `run_info`

Basic information about the run including how long it took.

| field      | stanfit slot                                          | type        | notes                                         |
|------------|-------------------------------------------------------|-------------|-----------------------------------------------|
| model_name | `@model_name`                                         | text        | The name of the file, minus the extension     |
| date       | `@date`                                               | timestamptz | The time the Stanfit object was created       |
| duration   | `get_elapsed_time(r) %>% as_tibble(rownames='chain')` | JSON        | Retval is in SECONDS*                         |
| mode       | `@mode`                                               | numeric     |                                               |
| stan_args  | `@stan_args[[1]]`                                     | JSON        | Take the first chain and represent it as JSON |

### Table `model_pars`

Model parameters and their dimension. Includes variables declared in:

- `parameters{}` block
- `transformed parameters{}` block
- `generated quantities{}` block

| field | stanfit slot        | type    | notes                                            |
|-------|---------------------|---------|--------------------------------------------------|
| id    | None                | serial  | Foreign key?                                     |
| par   | `names(r@par_dims)` | text    | Includes all parameters/transformed ps/generated |
| dim   | `@par_dims`         | numeric | 0 represents scalars                             |

### Table `stanmodel`

Model code.

| field | stanfit slot      | type   | notes |
|-------|-------------------|--------|-------|
| id    |                   | serial |       |
| code  | `get_stancode(r)` | text   |       |

### Table: `summary`

The output of calling `rstan::summary()` on a `stanfit` object and indexing
into the combined-chain summary (`rstan::summary(obj)$summary`).

| field   | stanfit slot                    | type             | notes |
|---------|---------------------------------|------------------|-------|
| id      | None                            |                  |       |
| par     | `summary(r)$summary$par`        | text             |       |
| idx     | Slightly complicated            | int              |       |
| mean    | `summary(r)$summary$mean`       | double precision |       |
| se_mean | `summary(r)$summary$se_mean`    | double precision |       |
| sd      | `summary(r)$summary$sd`         | double precision |       |
| P2.5    | `summary(r)$summary[["2.5%"]]`  | double precision |       |
| P25     | `summary(r)$summary[["25%"]]`   | double precision |       |
| P50     | `summary(r)$summary[["50%"]]`   | double precision |       |
| P75     | `summary(r)$summary[["75%"]]`   | double precision |       |
| P97.5   | `summary(r)$summary[["97.5%"]]` | double precision |       |
| n_eff   | `summary(r)$summary$n_eff`      | double precision |       |
| Rhat    | `summary(r)$summary$Rhat`       | double precision |       |

### Table: `c_summary`
                                                            
Per-chain summary. This one is a little tricky.

- There's no `n_eff` or `Rhat`
- The column names in the object returned by `summary(r)` are confusing, as all
  vars except `par` are named `[metric].chain:[n]`. 

We pivot the data a bit to get it into nearly the same structure as the `summary` table.

| field   | stanfit slot                    | type             | notes |
|---------|---------------------------------|------------------|-------|
| id      | None                            |                  |       |
| chain   | No exact mapping                |                  |       |
| par     | `summary(r)$summary$par`        | text             |       |
| idx     | Slightly complicated            | double precision |       |
| mean    | `summary(r)$summary$mean`       | double precision |       |
| se_mean | `summary(r)$summary$se_mean`    | double precision |       |
| sd      | `summary(r)$summary$sd`         | double precision |       |
| P2.5    | `summary(r)$summary[["2.5%"]]`  | double precision |       |
| P25     | `summary(r)$summary[["25%"]]`   | double precision |       |
| P50     | `summary(r)$summary[["50%"]]`   | double precision |       |
| P75     | `summary(r)$summary[["75%"]]`   | double precision |       |
| P97.5   | `summary(r)$summary[["97.5%"]]` | double precision |       |

### Table: 'log_posterior'

The log posterior at each iteration, for each chain.

| field | stanfit slot                     | type             | notes |
|-------|----------------------------------|------------------|-------|
| id    | None                             | integer          |       |
| chain | `get_logposterior(r)[[1,2,...]]` | numeric          |       |
| iter  | Row number of vector             | numeric          |       |
| value | The vector from each chain       | double precision |       |

### Table: `sampler_params`

Diagnostic parameters, by chain.

| field       | stanfit slot                                   | type             | notes                        |
|-------------|------------------------------------------------|------------------|------------------------------|
| id          | None                                           | integer          |                              |
| chain       | No exact mapping                               | numeric          |                              |
| iter        | Row number of vector                           | numeric          |                              |
| accept_stat | `get_sampler_params(r)[[chain]]$accept_stat__` | double precision |                              |
| stepsize    | `get_sampler_params(r)[[chain]]$stepsize__`    | double precision |                              |
| treedepth   | `get_sampler_params(r)[[chain]]$treedepth__`   | double precision |                              |
| n_leapfrog  | `get_sampler_params(r)[[chain]]$n_leapfrog__`  | double precision |                              |
| divergent   | `get_sampler_params(r)[[chain]]$divergent__`   | double precision | 1=divergent, 0=not divergent |
| energy      | `get_sampler_params(r)[[chain]]$energy__`      | double precision |                              |

[stanfit]: https://mc-stan.org/rstan/reference/stanfit-class.html
[s4]: http://adv-r.had.co.nz/S4.html
[dbi]: https://dbi.r-dbi.org/
[dbconnect]: https://dbi.r-dbi.org/reference/dbconnect
