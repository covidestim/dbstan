# dbstan

`dbstan` is glue code for connecting [`rstan::stanfit`][stanfit] objects and
relational databases.  It leverages the [DBI][dbi] package to provide a very
simple, DBMS-agnostic interface for INSERTing a representation of a `stanfit`
object into a DB, and it also provides a helper method to retrieve a particular
`stanfit` object's information from the DB. This way, you can easily get
(batches of) sampler results into a database, which usually makes it more
convenient to run analyses and share data.

The package creates a transformed representation of a `stanfit` object as
entries in eight SQL tables:

- `stanfit.run_ids`
- `stanfit.run_info`
- `stanfit.model_pars`
- `stanfit.stanmodel`
- `stanfit.summary`
- `stanfit.c_summary`
- `stanfit.log_posterior`
- `stanfit.sampler_params`

This work is done by the `stanfit_insert()` function. For example:

```r
library(rstan)
library(dbplyr)
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

# INSERT `stanfit` into db and store the UID, optionally including all
# posterior samples.
id <- stanfit_insert(fit1, conn, insertSamples = T) 

# Retrieve all relevant tables as a list of tables
tbl_dict(conn)

# Retrieve all relevant tables for a particular `id`
tables <- get_stanfit(id, conn)
```

This helps avoid situations where:

- Multiple researchers have to swap RDS archives back and forth to exchange
  results.  
  > *Now, you can just write queries against a database to get the results*

- Researchers want to do analysis across multiple (possibly many) sampled runs,
  but don't have enough RAM to do so, or don't want to keep track of various
  slimmed-down representations of the original `stanfit` object.  
  > *Now, you can have the RDBMS do the heavy lifting, and enjoy a schema that
  doesn't care if you add or subtract parameters from your model*

- Researchers are using a computing cluster and want to avoid shuffling
  around tons of RDS files, running out of space on either the cluster or their
  dev machine, etc.  
  > *Now, the cluster can just `INSERT` the `stanfit` object and move onto the
  next task, without the need to write to disk.*

Tested with Postgres 14.2, but it should work with many other SQL-based
databases.

## Get started

1. Execute `init.sql` against your database, which CREATEs a `"stanfit"` schema
   in your database and CREATEs all tables. We recommend reading `init.sql` first.  

   If you're just testing out `dbstan`, you could use a SQLite db for this.

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
- `sim` Matrix containing the individual samples.
- `inits` Initial values of all parameters on the first iteration
- `stan_args` - Arguments for the sampler
- `stanmodel` - Model code, as a `stanmodel` object
- `date` - Date of object creation

## `dbstan` table schema

The schema can be viewed in `init.sql` - here is a more descriptive mapping
between the `stanfit` object and its relational model.

### Table: `run_ids`

This table is an index of all of the `stanfit` objects represented in the
schema. The `method` column identifies the run as a sampled run or an optimized
run.

| field  | stanfit slot | notes                                                                |
|--------|--------------|----------------------------------------------------------------------|
| id     | None         | Serial, assigned by the database on insertion using `stanfit_insert` |
| method | None         | enum, `sampling`/`optimizing`                                        |

### Table: `run_info`

Basic information about the run including how long it took.

| field      | stanfit slot                                          | type        | notes                                         |
|------------|-------------------------------------------------------|-------------|-----------------------------------------------|
| id         | None                                                  | serial      | Foreign key                                   |
| model_name | `@model_name`                                         | text        | The name of the file, minus the extension     |
| date       | `@date`                                               | timestamptz | The time the Stanfit object was created       |
| duration   | `get_elapsed_time(r) %>% as_tibble(rownames='chain')` | JSON        | Retval is in SECONDS*                         |
| mode       | `@mode`                                               | numeric     |                                               |
| stan_args  | `@stan_args[[1]]`                                     | JSON        | Take the first chain and represent it as JSON |
 
### Table: `optimizing_run_info`

Optimizing runs have a lot less information associated with them - here we only
keep track of the optimizer's return code and the value of the log-posterior.

| field         | stanfit slot   | type             | notes                                                |
|---------------|----------------|------------------|------------------------------------------------------|
| id            | None           | serial           | Foreign key                                          |
| return_code   | `$return_code` | integer          | Return code from the optimizing routine              |
| log_posterior | `$value`       | double precision | The value of the log-posterior at the point-estimate |

### Table: `model_pars`

Model parameters and their dimension. Includes variables declared in:

- `parameters{}` block
- `transformed parameters{}` block
- `generated quantities{}` block

| field | stanfit slot        | type    | notes                                            |
|-------|---------------------|---------|--------------------------------------------------|
| id    | None                | serial  | Foreign key                                      |
| par   | `names(r@par_dims)` | text    | Includes all parameters/transformed ps/generated |
| dim   | `@par_dims`         | numeric | 0 represents scalars                             |

### Table: `stanmodel`

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
                                                            
Per-chain summary.

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

### Table: `samples`

All samples. Call `stanfit_insert(sft, includeSamples = T)` to insert samples
from your posterior into the database. Otherwise, the default behavior is to
save (potentially lots) of space and *not* insert any samples.

| field | stanfit slot                | type             | notes |
|-------|-----------------------------|------------------|-------|
| id    | None                        | smallint         |       |
| chain | No exact mapping            | smallint         |       |
| iter  | see `R/get_table_entries.R` | smallint         |       |
| par   |                             | text             |       |
| idx   |                             | smallint         |       |
| value |                             | double precision |       |

### Table: `optimizing_summary`

Optimizing results are sufficiently different in structure from sampler results
that they are given their own table.

| field     | list key       | type             | notes |
|-----------|----------------|------------------|-------|
| id        | None           |                  |       |
| par       | `names(r$par)` | text             |       |
| idx       | `names(r$par)` | integer          |       |
| point_est | `r$value`      | double precision |       |

### Table: `log_posterior`

The log posterior at each iteration, for each chain. **Note:** log_posterior
values for optimized runs are not located here - they're in the
`optimizing_run_info` table.

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
