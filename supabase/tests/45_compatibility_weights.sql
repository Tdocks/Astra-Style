-- Exercises the real database contract for server-owned compatibility weights.
begin;
set local role service_role;
do $$
declare
  original jsonb;
  version_before integer;
  version_after integer;
  invalid jsonb;
begin
  select weights, version into original, version_before
    from public.compatibility_weights_config where singleton;
  if version_before <> 1 then raise exception 'fixture should start at version 1'; end if;

  foreach invalid in array array[
    '{"color":0.25}'::jsonb,
    '{"color":0.25,"formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0.1,"occasion":0.05,"availability":0.05,"other":0}'::jsonb,
    '{"color":1.01,"formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0.1,"occasion":0.05,"availability":0.05}'::jsonb,
    '{"color":-0.01,"formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0.1,"occasion":0.05,"availability":0.05}'::jsonb,
    '{"color":"0.25","formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0.1,"occasion":0.05,"availability":0.05}'::jsonb,
    '{"color":0,"formality":0,"silhouette":0,"seasonWeather":0,"userPreference":0,"coWear":0,"occasion":0,"availability":0}'::jsonb
  ] loop
    begin
      update public.compatibility_weights_config set weights = invalid where singleton;
      raise exception 'invalid compatibility vector was accepted: %', invalid;
    exception when check_violation or invalid_text_representation then
      null;
    end;
  end loop;

  update public.compatibility_weights_config
    set weights = '{"color":0.35,"formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0,"occasion":0.05,"availability":0.05}'::jsonb
    where singleton;
  select version into version_after from public.compatibility_weights_config where singleton;
  if version_after <> version_before + 1 then
    raise exception 'valid update did not increment version: % -> %', version_before, version_after;
  end if;

  update public.compatibility_weights_config set weights = weights where singleton;
  select version into version_before from public.compatibility_weights_config where singleton;
  if version_before <> version_after then raise exception 'no-op update unexpectedly incremented version'; end if;

end;
$$;
reset role;

set local role authenticated;
do $$
declare denied boolean := false;
begin
  begin
    perform weights from public.compatibility_weights_config;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'authenticated role can read server-only weights'; end if;
  denied := false;
  begin
    update public.compatibility_weights_config
      set weights = '{"color":0.25,"formality":0.2,"silhouette":0.15,"seasonWeather":0.1,"userPreference":0.1,"coWear":0.1,"occasion":0.05,"availability":0.05}'::jsonb
      where singleton;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'authenticated role can update server-only weights'; end if;
end;
$$;
reset role;
rollback;
