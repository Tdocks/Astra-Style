-- Server-side compatibility weights; client roles have no read/write access.
create table public.compatibility_weights_config (
  singleton boolean primary key default true check (singleton),
  weights jsonb not null default '{"color":0.25,"formality":0.20,"silhouette":0.15,"seasonWeather":0.10,"userPreference":0.10,"coWear":0.10,"occasion":0.05,"availability":0.05}'::jsonb,
  version integer not null default 1 check (version > 0),
  updated_at timestamptz not null default now(),
  constraint compatibility_weights_config_valid_weights check (
    jsonb_typeof(weights) = 'object'
    and weights ?& array['color','formality','silhouette','seasonWeather','userPreference','coWear','occasion','availability']
    and weights - array['color','formality','silhouette','seasonWeather','userPreference','coWear','occasion','availability'] = '{}'::jsonb
    and jsonb_typeof(weights->'color') = 'number'
    and jsonb_typeof(weights->'formality') = 'number'
    and jsonb_typeof(weights->'silhouette') = 'number'
    and jsonb_typeof(weights->'seasonWeather') = 'number'
    and jsonb_typeof(weights->'userPreference') = 'number'
    and jsonb_typeof(weights->'coWear') = 'number'
    and jsonb_typeof(weights->'occasion') = 'number'
    and jsonb_typeof(weights->'availability') = 'number'
    and (weights->>'color')::numeric between 0 and 1
    and (weights->>'formality')::numeric between 0 and 1
    and (weights->>'silhouette')::numeric between 0 and 1
    and (weights->>'seasonWeather')::numeric between 0 and 1
    and (weights->>'userPreference')::numeric between 0 and 1
    and (weights->>'coWear')::numeric between 0 and 1
    and (weights->>'occasion')::numeric between 0 and 1
    and (weights->>'availability')::numeric between 0 and 1
    and ((weights->>'color')::numeric + (weights->>'formality')::numeric +
      (weights->>'silhouette')::numeric + (weights->>'seasonWeather')::numeric +
      (weights->>'userPreference')::numeric + (weights->>'coWear')::numeric +
      (weights->>'occasion')::numeric + (weights->>'availability')::numeric) > 0
  )
);

insert into public.compatibility_weights_config(singleton) values (true);
alter table public.compatibility_weights_config enable row level security;
revoke all on public.compatibility_weights_config from public, anon, authenticated;
grant select, update on public.compatibility_weights_config to service_role;

create function public.bump_compatibility_weights_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.weights is distinct from old.weights then
    new.version := old.version + 1;
  else
    new.version := old.version;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.bump_compatibility_weights_version() from public, anon, authenticated;

create trigger compatibility_weights_config_version
before update on public.compatibility_weights_config
for each row execute function public.bump_compatibility_weights_version();
