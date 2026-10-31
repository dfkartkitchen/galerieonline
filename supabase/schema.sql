-- =====================================================================
--  Otevřená galerie – schéma pro Supabase
--  Spusťte celé najednou v Supabase → SQL Editor → New query → Run.
--  Skript je opakovatelný: druhé spuštění nic nerozbije.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1) Správci galerie
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

alter table public.admins enable row level security;

-- Přihlášený uživatel vidí jen svůj vlastní řádek (frontend tak zjistí, zda je admin).
drop policy if exists "admins: cist vlastni radek" on public.admins;
create policy "admins: cist vlastni radek"
  on public.admins for select
  to authenticated
  using (user_id = auth.uid());

-- Pomocná funkce pro policies. security definer = obchází RLS na tabulce admins,
-- takže ji lze volat z policies jiných tabulek bez rekurze.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;


-- ---------------------------------------------------------------------
--  2) Pověšené obrazy – jeden řádek = jeden obraz na jednom místě
-- ---------------------------------------------------------------------
create table if not exists public.paintings (
  slot            int primary key check (slot between 0 and 29),
  image_path      text not null check (char_length(image_path) <= 200),
  w               int check (w between 1 and 10000),
  h               int check (h between 1 and 10000),
  author          text not null check (char_length(author) between 1 and 60),
  title           text check (char_length(title) <= 80),
  technique       text check (char_length(technique) <= 60),
  year            text check (char_length(year) <= 9),
  exhibitor_name  text check (char_length(exhibitor_name) <= 40),
  owner           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at      timestamptz not null default now()
);

create index if not exists paintings_owner_idx on public.paintings (owner);

alter table public.paintings enable row level security;

-- Číst může kdokoli, i nepřihlášený návštěvník.
drop policy if exists "paintings: cist kdokoli" on public.paintings;
create policy "paintings: cist kdokoli"
  on public.paintings for select
  to anon, authenticated
  using (true);

-- Vkládat jen přihlášený, sám za sebe, a jen s obrázkem z vlastní složky ve Storage.
drop policy if exists "paintings: vlozit vlastni" on public.paintings;
create policy "paintings: vlozit vlastni"
  on public.paintings for insert
  to authenticated
  with check (
    owner = auth.uid()
    and split_part(image_path, '/', 1) = auth.uid()::text
  );

-- Mazat vlastník nebo admin. Úpravy (update) nejsou povolené vůbec.
drop policy if exists "paintings: smazat vlastnik nebo admin" on public.paintings;
create policy "paintings: smazat vlastnik nebo admin"
  on public.paintings for delete
  to authenticated
  using (owner = auth.uid() or public.is_admin());

-- Limit: nejvýš 3 obrazy na jednoho uživatele.
-- Advisory lock zabrání tomu, aby dva souběžné inserty téhož uživatele limit obešly.
create or replace function public.paintings_limit_3()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtext('paintings-owner:' || new.owner::text));
  if (select count(*) from public.paintings where owner = new.owner) >= 3 then
    raise exception 'Limit 3 obrazů na uživatele' using errcode = 'P0001', hint = 'limit_3';
  end if;
  return new;
end;
$$;

drop trigger if exists paintings_limit_3 on public.paintings;
create trigger paintings_limit_3
  before insert on public.paintings
  for each row execute function public.paintings_limit_3();


-- ---------------------------------------------------------------------
--  3) Sundané ukázkové obrazy
-- ---------------------------------------------------------------------
create table if not exists public.hidden_samples (
  slot int primary key check (slot between 0 and 29)
);

alter table public.hidden_samples enable row level security;

drop policy if exists "hidden_samples: cist kdokoli" on public.hidden_samples;
create policy "hidden_samples: cist kdokoli"
  on public.hidden_samples for select
  to anon, authenticated
  using (true);

drop policy if exists "hidden_samples: vlozit admin" on public.hidden_samples;
create policy "hidden_samples: vlozit admin"
  on public.hidden_samples for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "hidden_samples: smazat admin" on public.hidden_samples;
create policy "hidden_samples: smazat admin"
  on public.hidden_samples for delete
  to authenticated
  using (public.is_admin());


-- ---------------------------------------------------------------------
--  4) Realtime – změny obrazů chodí všem živě
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'paintings') then
    alter publication supabase_realtime add table public.paintings;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'hidden_samples') then
    alter publication supabase_realtime add table public.hidden_samples;
  end if;
end $$;


-- ---------------------------------------------------------------------
--  5) Storage – bucket „paintings“ (veřejné čtení, max 5 MB, jen obrázky)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('paintings', 'paintings', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Veřejné URL obrázků fungují bez policy (bucket je public).
-- Policies níže řídí nahrávání a mazání přes API.

-- Nahrávat jen přihlášený a jen do své složky {auth.uid()}/...
drop policy if exists "paintings storage: nahrat do vlastni slozky" on storage.objects;
create policy "paintings storage: nahrat do vlastni slozky"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'paintings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Mazání ve Storage potřebuje i select. Obojí jen vlastní soubory, nebo admin.
drop policy if exists "paintings storage: cist vlastni nebo admin" on storage.objects;
create policy "paintings storage: cist vlastni nebo admin"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'paintings'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

drop policy if exists "paintings storage: smazat vlastni nebo admin" on storage.objects;
create policy "paintings storage: smazat vlastni nebo admin"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'paintings'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );


-- ---------------------------------------------------------------------
--  Hotovo. Přidání správce (spusťte zvlášť, až se poprvé přihlásíte na webu):
--
--    insert into public.admins (user_id)
--    select id from auth.users where email = 'vas@email.cz'
--    on conflict do nothing;
-- ---------------------------------------------------------------------
