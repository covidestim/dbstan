/* Create a schema to house all of the data */
create schema stanfit;

create table stanfit.run_ids (
  id serial primary key
);

create table stanfit.run_info (
  id integer primary key references stanfit.run_ids,
  model_name text not null,
  date timestamptz not null,
  duration json not null,
  mode integer not null,
  stan_args json not null,
  chains integer not null
);

create table stanfit.model_pars (
  id integer references stanfit.run_ids,
  par text not null,
  dim integer not null,

  primary key (id, par)
);

create table stanfit.stanmodel (
  id integer primary key references stanfit.run_ids,
  code text not null
);

create table stanfit.summary (
  id integer references stanfit.run_ids,
  par text not null,
  idx integer not null,
  mean numeric not null,
  se_mean numeric, /* Can be null */
  sd numeric not null,
  p2_5 numeric not null,
  p25 numeric not null,
  p50 numeric not null,
  p75 numeric not null,
  p97_5 numeric not null,
  n_eff numeric, /* Can be null */ 
  rhat numeric, /* Can be null */ 

  primary key (id, par, idx)
);

create table stanfit.c_summary (
  id integer references stanfit.run_ids,
  chain integer not null,
  par text not null,
  idx integer not null,
  mean numeric not null,
  sd numeric not null,
  p2_5 numeric not null,
  p25 numeric not null,
  p50 numeric not null,
  p75 numeric not null,
  p97_5 numeric not null,

  primary key (id, chain, par, idx)
);

create table stanfit.log_posterior (
  id integer references stanfit.run_ids,
  chain integer not null,
  iter integer not null,
  value numeric not null,

  primary key (id, chain, iter)
);

create table stanfit.sampler_params (
  id integer references stanfit.run_ids,
  chain integer not null,
  iter integer not null,
  accept_stat numeric not null,
  stepsize numeric not null,
  treedepth numeric not null,
  n_leapfrog numeric not null,
  divergent numeric not null,
  energy numeric not null,

  primary key (id, chain, iter)
);
