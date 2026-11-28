-- Sona : deux corrections de modération.
-- 1. Une sanction décidée depuis un signalement le clôt : la personne qui a signalé doit être prévenue
--    (c'était annoncé dans l'interface, mais seule la clôture « sans sanction » prévenait).
-- 2. Ajouter une note à un signalement déjà clos ne doit pas changer sa date de clôture.

create or replace function public.admin_sanction(
  p_actor uuid, p_target uuid, p_kind text, p_reason text,
  p_duration interval default null, p_report uuid default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_role public.user_role;
  v_reason text;
  v_kind public.sanction_kind;
  v_until timestamptz;
  v_id uuid;
  v_warnings int;
  v_reporter uuid;
begin
  perform private.only_service();
  v_reason := private.require_reason(p_reason);
  v_kind := p_kind::public.sanction_kind;
  v_role := private.require_actor(p_actor, (case when v_kind = 'ban' then 'admin' else 'moderator' end)::public.user_role);
  perform private.require_above(p_actor, v_role, p_target);

  if v_kind = 'suspension' then
    if p_duration is null or p_duration <= interval '0' then raise exception 'duration_required' using errcode = '22023'; end if;
    if v_role = 'moderator' and p_duration > interval '7 days' then raise exception 'duration_too_long_for_moderator' using errcode = '42501'; end if;
    v_until := now() + p_duration;
  end if;

  insert into public.sanctions (user_id, kind, reason, created_by, expires_at, report_id)
  values (p_target, v_kind, v_reason, p_actor, v_until, p_report)
  returning id into v_id;

  if v_kind = 'warning' then
    perform private.notify(p_target, 'warning', jsonb_build_object('sanction_id', v_id, 'reason', v_reason));
  else
    update public.profiles
       set status = case v_kind when 'ban' then 'banned' when 'suspension' then 'suspended' else 'quarantined' end::public.account_status,
           status_reason = v_reason, status_until = v_until
     where id = p_target;
    perform private.notify(p_target, 'moderation', jsonb_build_object('sanction_id', v_id, 'kind', v_kind, 'reason', v_reason, 'until', v_until));
  end if;

  if v_kind in ('suspension', 'ban') then
    perform private.revoke_sessions(p_target);
  end if;

  -- Ban : on retient l'e-mail et les identités OAuth (hachés) pour empêcher
  -- de recréer un compte.
  if v_kind = 'ban' then
    insert into private.banned_identifiers (kind, value_hash, reason, created_by)
      select 'email', private.sha(private.norm_email(u.email)), v_reason, p_actor
      from auth.users u where u.id = p_target and u.email is not null;
    insert into private.banned_identifiers (kind, value_hash, reason, created_by)
      select 'oauth', private.sha(i.provider || ':' || i.provider_id), v_reason, p_actor
      from auth.identities i where i.user_id = p_target and i.provider <> 'email';
  end if;

  if p_report is not null then
    update public.reports set status = 'resolved', resolved_at = now(), updated_at = now(),
           resolution = coalesce(resolution, 'sanction:' || v_kind::text)
     where id = p_report and status in ('open', 'in_progress')
     returning reporter_id into v_reporter;
    if v_reporter is not null then
      perform private.notify(v_reporter, 'report_update', jsonb_build_object('report_id', p_report, 'status', 'resolved'));
    end if;
  end if;

  perform private.audit(p_actor, 'sanction.' || v_kind::text, p_target, 'user', p_target::text, v_reason,
    jsonb_build_object('sanction_id', v_id, 'until', v_until, 'report_id', p_report));
  select count(*) into v_warnings from public.sanctions where user_id = p_target and kind = 'warning';
  return jsonb_build_object('sanction_id', v_id, 'kind', v_kind, 'until', v_until, 'warnings', v_warnings);
end $$;

create or replace function public.staff_update_report(p_actor uuid, p_report uuid, p_status text, p_assigned uuid, p_resolution text, p_note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_reporter uuid;
  v_old text;
begin
  perform private.only_service();
  perform private.require_actor(p_actor, 'moderator');
  if p_status not in ('open', 'in_progress', 'resolved', 'dismissed') then raise exception 'bad_status' using errcode = '22023'; end if;
  select reporter_id, status into v_reporter, v_old from public.reports where id = p_report;
  if not found then raise exception 'report_not_found' using errcode = 'P0002'; end if;
  update public.reports
     set status = p_status, assigned_to = coalesce(p_assigned, assigned_to), resolution = coalesce(p_resolution, resolution),
         updated_at = now(),
         resolved_at = case when p_status not in ('resolved', 'dismissed') then null
                            when status = p_status then resolved_at
                            else now() end
   where id = p_report;
  if p_note is not null and btrim(p_note) <> '' then
    insert into public.report_notes (report_id, author_id, note) values (p_report, p_actor, btrim(p_note));
  end if;
  -- Le signalant est prévenu, sans détail sur la sanction éventuelle.
  if v_reporter is not null and p_status in ('resolved', 'dismissed') and v_old not in ('resolved', 'dismissed') then
    perform private.notify(v_reporter, 'report_update', jsonb_build_object('report_id', p_report, 'status', p_status));
  end if;
  perform private.audit(p_actor, 'report.' || p_status, null, 'report', p_report::text, coalesce(p_resolution, 'traitement du signalement'));
end $$;
