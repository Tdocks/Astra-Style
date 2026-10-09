-- Enforce the same strict weight-sum rule as the admin update endpoint at
-- the database boundary. Client roles remain unable to write this table.
alter table public.compatibility_weights_config
  drop constraint compatibility_weights_config_valid_weights;

alter table public.compatibility_weights_config
  add constraint compatibility_weights_config_valid_weights check (
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
    and abs(
      (weights->>'color')::numeric + (weights->>'formality')::numeric +
      (weights->>'silhouette')::numeric + (weights->>'seasonWeather')::numeric +
      (weights->>'userPreference')::numeric + (weights->>'coWear')::numeric +
      (weights->>'occasion')::numeric + (weights->>'availability')::numeric - 1
    ) <= 0.000001
  );
