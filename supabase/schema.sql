-- Trousseau Row: database schema, security policies and starter catalogue.
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run: tables are created only if missing. Note that re-running
-- resets the sample designers and products below to these values.

-- ─── Catalogue ───────────────────────────────────────────────────────────────

create table if not exists public.designers (
  id         text primary key,
  name       text not null,
  city       text,
  specialty  text,
  sort       integer not null default 0
);

create table if not exists public.products (
  id             text primary key,
  name           text not null,
  designer_id    text not null references public.designers(id) on update cascade,
  category       text not null check (category in ('Wedding gowns','Lehengas','Reception','Pre-wedding events','Bridesmaids')),
  silhouette     text not null check (silhouette in ('ballgown','aline','mermaid','sheath','lehenga','jumpsuit','sari')),
  fabric         text,
  colors         text[] not null default '{}',   -- keys: ivory, champagne, blush, red, maroon, coral, marigold, emerald, sage, dusk, mink, gold, black
  trim_color     text not null default '#C6A15A', -- hex colour used for embroidery and borders in the fallback sketch
  price_usd      integer not null check (price_usd > 0),
  lead_weeks     integer not null check (lead_weeks between 1 and 52),
  rush_available boolean not null default false,
  embellished    boolean not null default false,
  description    text,
  active         boolean not null default true,
  sort           integer not null default 0
);

-- Product photos: a path inside the site (images/x.jpg) or a full https URL,
-- e.g. from a Supabase Storage public bucket. Leave empty to show the sketch.
alter table public.products add column if not exists image_url text;
alter table public.products add column if not exists image_alt text;

-- ─── Customer requests (write-only from the website) ────────────────────────

create table if not exists public.appointments (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  meeting_type     text not null check (char_length(meeting_type) <= 80),
  appointment_date date not null,
  time_slot        text not null check (time_slot ~ '^\d{2}:\d{2}$'),
  venue            text check (char_length(venue) <= 80),
  budget           text check (char_length(budget) <= 40),
  silhouettes      text[] not null default '{}',
  saved_pieces     text[] not null default '{}',
  wedding_date     date,
  name             text not null check (char_length(name) between 1 and 120),
  email            text not null check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  status           text not null default 'requested' check (status in ('requested','confirmed','cancelled'))
);

-- One booking per studio/call type per slot (cancelled bookings free the slot).
create unique index if not exists appointments_slot_unique
  on public.appointments (meeting_type, appointment_date, time_slot)
  where status <> 'cancelled';

create table if not exists public.order_requests (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  name         text not null check (char_length(name) between 1 and 120),
  email        text not null check (char_length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  wedding_date date,
  items        jsonb not null check (jsonb_typeof(items) = 'array' and pg_column_size(items) < 20000),
  subtotal_usd integer not null check (subtotal_usd >= 0),
  due_now_usd  integer not null check (due_now_usd >= 0),
  status       text not null default 'new' check (status in ('new','invoiced','paid','cancelled'))
);

-- ─── Row-level security ──────────────────────────────────────────────────────
-- The website uses the public anon key, so these policies are the only thing
-- between visitors and the data. Visitors can read the active catalogue and
-- create requests; they can never read, change or delete anyone's requests.

alter table public.designers      enable row level security;
alter table public.products       enable row level security;
alter table public.appointments   enable row level security;
alter table public.order_requests enable row level security;

drop policy if exists "Anyone can read designers" on public.designers;
create policy "Anyone can read designers" on public.designers
  for select to anon, authenticated using (true);

drop policy if exists "Anyone can read active products" on public.products;
create policy "Anyone can read active products" on public.products
  for select to anon, authenticated using (active);

drop policy if exists "Anyone can request an appointment" on public.appointments;
create policy "Anyone can request an appointment" on public.appointments
  for insert to anon, authenticated
  with check (status = 'requested' and appointment_date > current_date);

drop policy if exists "Anyone can send an order request" on public.order_requests;
create policy "Anyone can send an order request" on public.order_requests
  for insert to anon, authenticated
  with check (status = 'new');

grant select on public.designers, public.products to anon, authenticated;
grant insert on public.appointments, public.order_requests to anon, authenticated;

-- Booked times for a day, without exposing who booked them.
create or replace function public.taken_slots(p_date date, p_meeting_type text)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select time_slot from public.appointments
  where appointment_date = p_date
    and meeting_type = p_meeting_type
    and status <> 'cancelled';
$$;
revoke all on function public.taken_slots(date, text) from public;
grant execute on function public.taken_slots(date, text) to anon, authenticated;

-- ─── Starter catalogue (sample data — replace with real designers) ──────────
-- Generated from the built-in catalogue in index.html.

insert into public.designers (id, name, city, specialty, sort) values
  ('ondine', 'Maison Ondine', 'Paris', 'Structured silk gowns and hand beading', 1),
  ('lumbre', 'Casa Lumbre', 'Seville', 'Chantilly lace and Spanish capes', 2),
  ('haldane', 'Haldane & Rowe', 'London', 'Minimal crepe tailoring for city weddings', 3),
  ('sora', 'Sora Atelier', 'Kyoto', 'Sculptural silk gazar and slip dresses', 4),
  ('rasika', 'Rasika Mehra Studio', 'New Delhi', 'Zardozi and gota patti lehengas', 5),
  ('kesar', 'Kesar House', 'Varanasi', 'Velvet and heirloom zardozi bridal sets', 6)
on conflict (id) do update set name = excluded.name, city = excluded.city, specialty = excluded.specialty, sort = excluded.sort;

insert into public.products (id, name, designer_id, category, silhouette, fabric, colors, trim_color, price_usd, lead_weeks, rush_available, embellished, description, image_url, image_alt, active, sort) values
  ('marguerite', 'Marguerite', 'lumbre', 'Wedding gowns', 'mermaid', 'Chantilly lace, lace capelet', array['ivory','blush'], '#FFFFFF', 3600, 18, true, true, 'Fitted through the knee and flaring into a scalloped hem, with a detachable high-neck lace capelet.', 'images/marguerite.jpg', 'Fitted lace mermaid gown with a high-neck lace capelet and flutter sleeves', true, 1),
  ('aurelia', 'Aurelia', 'ondine', 'Wedding gowns', 'aline', 'Embroidered lace on tulle', array['ivory'], '#FFFFFF', 4200, 20, false, true, 'Lace sleeves and a high illusion collar over a plunging bodice, finished with a chapel train.', 'images/aurelia.jpg', 'Long-sleeve lace A-line gown with a high illusion collar and plunging bodice', true, 2),
  ('celeste', 'Céleste', 'ondine', 'Wedding gowns', 'ballgown', 'Corded lace over tulle, boned corset', array['ivory'], '#FFFFFF', 4850, 20, false, true, 'A strapless corset with a scalloped lace edge over a full layered skirt. Pockets sit in the side seams.', 'images/celeste.jpg', 'Strapless lace ball gown with a corseted bodice and full skirt', true, 3),
  ('solene', 'Solène', 'lumbre', 'Wedding gowns', 'ballgown', 'Floral lace on organza', array['ivory'], '#FFFFFF', 3900, 18, true, true, 'Thin straps, a sweetheart neckline and a basque waist over a full lace skirt.', 'images/solene.jpg', 'Lace ball gown with thin straps and a sweetheart neckline', true, 4),
  ('odette', 'Odette', 'ondine', 'Wedding gowns', 'aline', 'Guipure lace', array['ivory'], '#FFFFFF', 5600, 24, false, true, 'Guipure lace from neck to hem, with long sleeves and a cathedral-length train.', 'images/odette.jpg', 'Long-sleeve guipure lace A-line gown with a cathedral train', true, 5),
  ('valentina', 'Valentina', 'lumbre', 'Wedding gowns', 'ballgown', 'Lace appliqué on tulle, lace-edged veil', array['ivory'], '#FFFFFF', 5200, 20, false, true, 'A strapless lace ball gown with a front slit. The matching cathedral veil is edged in the same lace.', 'images/valentina.jpg', 'Strapless lace ball gown with a front slit, worn with a long lace-edged veil', true, 6),
  ('isabela', 'Isabela', 'lumbre', 'Wedding gowns', 'mermaid', 'Crepe with lace appliqué', array['ivory'], '#FFFFFF', 4100, 18, false, true, 'A sheer lace bodice with one off-the-shoulder strap, over a crepe mermaid skirt and a wide lace train.', 'images/isabela.jpg', 'Off-the-shoulder crepe mermaid gown with a sheer lace bodice and lace train', true, 7),
  ('elodie', 'Élodie', 'ondine', 'Wedding gowns', 'aline', 'Layered tulle with lace appliqué', array['ivory','blush'], '#FFFFFF', 3300, 16, true, true, 'Soft layered tulle with lace at the bodice, an open back and a long sweeping train.', 'images/elodie.jpg', 'Tulle A-line gown with an open back and long train, seen from behind', true, 8),
  ('wren', 'Wren', 'haldane', 'Wedding gowns', 'mermaid', 'Double-faced crepe', array['ivory','champagne'], '#DCCFB8', 2200, 12, true, false, 'A draped crepe bodice and fitted mermaid skirt with a long train. No boning and no beading, so it is light enough for a long day.', 'images/wren.jpg', 'Strapless draped crepe mermaid gown with a long train', true, 9),
  ('aiko', 'Aiko', 'sora', 'Wedding gowns', 'aline', 'Duchess satin', array['ivory'], '#E9E2D6', 2800, 14, true, false, 'A pleated sweetheart bodice and a full satin skirt with a front slit and pockets.', 'images/aiko.jpg', 'Strapless satin A-line gown with a pleated bodice and front slit', true, 10),
  ('hana', 'Hana', 'sora', 'Wedding gowns', 'sheath', 'Silk satin', array['ivory','champagne'], '#E6D2B0', 2400, 12, true, false, 'A corseted satin bodice on thin straps, falling into a fluted skirt with a short train.', 'images/hana.jpg', 'Satin fit-and-flare gown with thin straps and a corseted bodice', true, 11),
  ('noor', 'Noor', 'rasika', 'Lehengas', 'lehenga', 'Net with zardozi and sequins', array['red','maroon'], '#C6A15A', 6400, 24, false, true, 'Red net worked all over in zardozi and sequins, with a long-sleeve blouse and a matching dupatta.', 'images/noor.jpg', 'Red embroidered bridal lehenga with long sleeves and a matching dupatta', true, 12),
  ('laila', 'Laila', 'kesar', 'Lehengas', 'lehenga', 'Raw silk with zardozi, net dupatta', array['red'], '#C6A15A', 7200, 26, false, true, 'Dense gold zardozi on red raw silk, with a heavily bordered net dupatta worn over the head.', 'images/laila.jpg', 'Red bridal lehenga with dense gold embroidery and a red veil dupatta', true, 13),
  ('rani', 'Rani', 'kesar', 'Lehengas', 'lehenga', 'Silk velvet with dabka and zari', array['maroon','emerald'], '#C6A15A', 4200, 20, false, true, 'Velvet for a winter wedding, embroidered in dabka with an emerald border at the hem.', 'images/rani.jpg', 'Maroon velvet lehenga with gold embroidery and an emerald border', true, 14),
  ('shirin', 'Shirin', 'kesar', 'Lehengas', 'lehenga', 'Organza with zardozi', array['coral','red'], '#D9B26A', 6800, 24, false, true, 'A long-line coral pishwas over a lehenga, worked in gold zardozi, with a trailing dupatta.', 'images/shirin.jpg', 'Coral bridal gown with dense gold embroidery and a long embroidered trail', true, 15),
  ('gulnaar', 'Gulnaar', 'rasika', 'Lehengas', 'lehenga', 'Raw silk with resham and gota', array['ivory','blush'], '#D9A6A0', 5200, 22, false, true, 'Ivory raw silk embroidered all over in pastel resham, with a gota border and a sheer dupatta.', 'images/gulnaar.jpg', 'Ivory lehenga embroidered with pastel florals, with a matching blouse and dupatta', true, 16),
  ('mira', 'Mira', 'rasika', 'Pre-wedding events', 'lehenga', 'Organza with mirror and sequin work', array['sage','blush'], '#E8E2D0', 2900, 14, true, true, 'Light enough to dance in. Made for mehndi and sangeet, with mirror work that catches the light.', 'images/mira.jpg', 'Sage green lehenga with mirror work and a sheer dupatta', true, 17),
  ('gulabo', 'Gulabo', 'kesar', 'Pre-wedding events', 'lehenga', 'Organza with resham florals', array['blush','sage'], '#E8B9B4', 3200, 16, true, true, 'Blush organza scattered with resham flowers, for the nikah, engagement or a daytime ceremony.', 'images/gulabo.jpg', 'Blush pink lehenga with floral embroidery and a sheer dupatta', true, 18),
  ('zoya', 'Zoya', 'rasika', 'Reception', 'ballgown', 'Sequinned tulle, crystal fringe', array['mink','champagne'], '#E9E4E0', 3400, 14, true, true, 'Tulle covered in geometric sequin work, with crystal fringe at the shoulders. Made for the reception entrance.', 'images/zoya.jpg', 'Mink tulle gown with geometric sequin work and crystal fringe at the shoulders', true, 19),
  ('pilar', 'Pilar', 'haldane', 'Reception', 'mermaid', 'Silk crepe, gazar peplum', array['ivory'], '#F3ECDF', 2600, 12, true, false, 'A crepe column with a sculpted gazar peplum and a separate neck scarf. Unpin the peplum for the party.', 'images/pilar.jpg', 'Strapless crepe column gown with a sculpted bubble peplum and a neck scarf', true, 20)
on conflict (id) do update set
  name = excluded.name, designer_id = excluded.designer_id, category = excluded.category, silhouette = excluded.silhouette,
  fabric = excluded.fabric, colors = excluded.colors, trim_color = excluded.trim_color, price_usd = excluded.price_usd,
  lead_weeks = excluded.lead_weeks, rush_available = excluded.rush_available, embellished = excluded.embellished,
  description = excluded.description, image_url = excluded.image_url, image_alt = excluded.image_alt,
  active = excluded.active, sort = excluded.sort;

-- Hide sample pieces from earlier versions of this file that are no longer in the catalogue.
update public.products set active = false
where id not in ('marguerite', 'aurelia', 'celeste', 'solene', 'odette', 'valentina', 'isabela', 'elodie', 'wren', 'aiko', 'hana', 'noor', 'laila', 'rani', 'shirin', 'gulnaar', 'mira', 'gulabo', 'zoya', 'pilar');
