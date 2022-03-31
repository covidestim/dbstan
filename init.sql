/* Create a schema to house all of the data */
create schema stanfit;

create type stanfit.method as enum ('sampling', 'optimizing');

create table stanfit.run_ids (
  id serial primary key,
  method stanfit.method default 'sampling'
);

create table stanfit.run_info (
  id integer primary key references stanfit.run_ids on delete cascade,
  model_name text not null,
  date timestamptz not null,
  duration json not null,
  mode integer not null,
  stan_args json not null,
  chains integer not null
);

create table stanfit.optimizing_run_info (
  id integer primary key references stanfit.run_ids on delete cascade,
  return_code integer not null,
  log_posterior double precision not null
);

create table stanfit.model_pars (
  id integer references stanfit.run_ids on delete cascade,
  par text not null,
  dim integer not null,

  primary key (id, par)
);

create table stanfit.stanmodel (
  id integer primary key references stanfit.run_ids on delete cascade,
  code text not null
);

create table stanfit.summary (
  id integer references stanfit.run_ids on delete cascade,
  par text not null,
  idx integer not null,
  mean double precision,
  se_mean double precision, /* Can be null */
  sd double precision,
  p2_5 double precision,
  p25 double precision,
  p50 double precision,
  p75 double precision,
  p97_5 double precision,
  n_eff double precision, /* Can be null */ 
  rhat double precision, /* Can be null */ 

  primary key (id, par, idx)
);

create table stanfit.c_summary (
  id integer references stanfit.run_ids on delete cascade,
  chain integer not null,
  par text not null,
  idx integer not null,
  mean double precision,
  sd double precision,
  p2_5 double precision,
  p25 double precision,
  p50 double precision,
  p75 double precision,
  p97_5 double precision,

  primary key (id, chain, par, idx)
);

create table stanfit.samples (
  id smallint references stanfit.run_ids on delete cascade,
  chain smallint not null,
  iter smallint not null,
  par text not null,
  idx smallint not null,
  value double precision
);

create index samples_for_run_and_par_idx_index
  on stanfit.samples (id, par) with (deduplicate_items = off);

create table stanfit.optimizing_summary (
  id integer references stanfit.run_ids on delete cascade,
  par text not null,
  idx integer not null,
  point_est double precision,

  primary key (id, par, idx)
);

create table stanfit.log_posterior (
  id integer references stanfit.run_ids on delete cascade,
  chain integer not null,
  iter integer not null,
  value double precision not null,

  primary key (id, chain, iter)
);

create table stanfit.sampler_params (
  id integer references stanfit.run_ids on delete cascade,
  chain integer not null,
  iter integer not null,
  accept_stat double precision not null,
  stepsize double precision not null,
  treedepth double precision not null,
  n_leapfrog double precision not null,
  divergent double precision not null,
  energy double precision not null,

  primary key (id, chain, iter)
);
