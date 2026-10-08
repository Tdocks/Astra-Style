-- Activate the configurable 24-hour abandoned-reference policy after the
-- fenced cleanup worker is deployed and explicit erasure is verified.
update public.studio_retention_config set reference_cleanup_enabled=true where singleton;
