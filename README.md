# dbstan

`dbstan` is glue code for mapping [`rstan::stanfit`][stanfit] objects to
relational database schemas.  It leverages the [DBI][dbi] package to provide a
simple, DBMS-agnostic interface for:

- `INSERT`ing a representation of a `stanfit` object into a DB
- Retrieving a particular `stanfit` object's information from the DB.
- Materializing a `dbplyr`-based list of tables which contain all `stanfit`
  information.

This makes it easy to move (batches of) sampler results into a database, which
makes it more convenient to run analyses and share data.

The package maps a `stanfit` object into records stored in nine SQL tables:

- `stanfit.run_ids`
- `stanfit.run_info`
- `stanfit.model_pars`
- `stanfit.stanmodel`
- `stanfit.summary`
- `stanfit.c_summary`
- `stanfit.samples`
- `stanfit.log_posterior`
- `stanfit.sampler_params`

### Example:

```r
library(rstan)
library(dbstan)

# Establish a DB connection using DBI
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  user     = 'postgres',
  password = 'password',
  host     = 'mydb.abcdefg1234567.us-east-2.rds.amazonaws.com'
)

# Get samples from any sampled Stan model. Currently only NUTS is supported.
fit1 <- stan(
  file = "schools.stan",  # Stan program
  data = schools_data,    # named list of data
)

# INSERT `stanfit` into db and store the generated primary key, optionally
# including all posterior samples.
id <- stanfit_insert(fit1, conn, insert_samples = T) 

# Retrieve all relevant tables as a list of dbplyr-backed tables
tbl_dict(conn)

# Or, retrieve all relevant tables for a particular `id`
tables <- get_stanfit(id, conn)
```

## Use cases

This helps avoid situations where:

- Multiple researchers swap `.RDS` archives back and forth to exchange
  results.  
  > *Now, just write queries against a database to get the results*

- Researchers want to do analysis across multiple (possibly many) sampled runs,
  but don't have enough RAM to do so, or don't want to keep track of various
  slimmed-down representations of the original `stanfit` object.  
  > *Now, the RDBMS does the heavy lifting, and gracefully adapts to a model
  > that may change over time in its parameter schema*

- Researchers are using a computing cluster and want to avoid shuffling
  around tons of `.RDS` files, running out of space on either the cluster or
  their dev machine, etc.  
  > *Now, the cluster can just `INSERT` the `stanfit` object once it is created,
  > and move onto the next task - no write to disk necessary.*

Tested with Postgres 14.2, but it should work with many other SQL-based
databases.

## Get started

1. Execute `init.sql` against your database, which `CREATE`s a `"stanfit"`
   schema in your database and `CREATE`s all tables. We recommend reading
   `init.sql` first!

   If you're just testing out `dbstan`, you could use a SQLite db for this, or
   Postgres in a container.

   ```
   psql -f init.sql
   ```

2. Make sure you can connect to the database using [`DBI::dbConnect()`][dbconnect].

3. Pass a `stanfit` object to `stanfit_insert(stanfit_object, conn)`. The
   returned number is a unique identifier `id` which is a field in all the
   tables.

## Structure of the `stanfit` object

Results from calls to `rstan::sampling()` or `rstan::stan()` are stored in
`stanfit` objects.  The contents of the object are described in detail
[here][stanfit]. Each object is an [S4][s4] class with a bunch of slots that
represent various parts of the sampling process, such as the model code, the
samples drawn from the posterior, and diagnostic messages from the NUTS sampler.

`dbstan` organizes these slots into a relational model. The slots are
summarized below:

- `model_name` Name of the model
- `model_pars` Parameters in the model, including the `generated quantities{}`
  block and `transformed parameters{}` block
- `par_dims` Dimensions of said paramaeters
- `mode` Status code indicating success or failure of the sampler
- `sim` Matrix containing the individual samples.
- `inits` Initial values of all parameters on the first iteration
- `stan_args` Arguments for the sampler
- `stanmodel` Model code, as a `stanmodel` object
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
| P2_5    | `summary(r)$summary[["2.5%"]]`  | double precision |       |
| P25     | `summary(r)$summary[["25%"]]`   | double precision |       |
| P50     | `summary(r)$summary[["50%"]]`   | double precision |       |
| P75     | `summary(r)$summary[["75%"]]`   | double precision |       |
| P97_5   | `summary(r)$summary[["97.5%"]]` | double precision |       |
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
| P2_5    | `summary(r)$summary[["2.5%"]]`  | double precision |       |
| P25     | `summary(r)$summary[["25%"]]`   | double precision |       |
| P50     | `summary(r)$summary[["50%"]]`   | double precision |       |
| P75     | `summary(r)$summary[["75%"]]`   | double precision |       |
| P97_5   | `summary(r)$summary[["97.5%"]]` | double precision |       |

### Table: `samples`

All samples. Call `stanfit_insert(sft, include_samples = T)` to insert samples
from your posterior into the database. Otherwise, the default behavior is to
save (potentially lots) of space and *not* insert any samples.

| field | stanfit slot                | type             | notes                          |
|-------|-----------------------------|------------------|--------------------------------|
| id    | None                        | smallint         | using `smallint` to save space |
| chain | No exact mapping            | smallint         |                                |
| iter  | see `R/get_table_entries.R` | smallint         |                                |
| par   |                             | text             |                                |
| idx   |                             | smallint         |                                |
| value |                             | double precision |                                |

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
