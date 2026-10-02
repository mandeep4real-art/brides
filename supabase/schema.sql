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
  colors         text[] not null default '{}',   -- keys: ivory, champagne, blush, red, marigold, emerald, sage, dusk, gold, black
  trim_color     text not null default '#C6A15A', -- hex colour used for embroidery and borders in the illustration
  price_usd      integer not null check (price_usd > 0),
  lead_weeks     integer not null check (lead_weeks between 1 and 52),
  rush_available boolean not null default false,
  embellished    boolean not null default false,
  description    text,
  active         boolean not null default true,
  sort           integer not null default 0
);

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

insert into public.designers (id, name, city, specialty, sort) values
  ('ondine',  'Maison Ondine',       'Paris',     'Structured silk gowns and hand beading',     1),
  ('lumbre',  'Casa Lumbre',         'Seville',   'Chantilly lace and Spanish capes',           2),
  ('haldane', 'Haldane & Rowe',      'London',    'Minimal crepe tailoring for city weddings',  3),
  ('sora',    'Sora Atelier',        'Kyoto',     'Sculptural silk gazar and slip dresses',     4),
  ('rasika',  'Rasika Mehra Studio', 'New Delhi', 'Zardozi and gota patti lehengas',            5),
  ('kesar',   'Kesar House',         'Varanasi',  'Handwoven Banarasi silk and velvet',         6),
  ('juniper', 'Juniper Lane',        'Portland',  'Mix-and-match bridesmaid colour stories',    7)
on conflict (id) do update set name = excluded.name, city = excluded.city, specialty = excluded.specialty, sort = excluded.sort;

insert into public.products (id, name, designer_id, category, silhouette, fabric, colors, trim_color, price_usd, lead_weeks, rush_available, embellished, description, sort) values
  ('celeste',    'Céleste',    'ondine',  'Wedding gowns',      'ballgown', 'Silk mikado, hand-set pearls',  array['ivory','champagne'],        '#C6A15A', 4850, 20, false, true,  'A full mikado skirt over a boned bodice, with pearls set by hand along the neckline and waist seam.', 1),
  ('marguerite', 'Marguerite', 'lumbre',  'Wedding gowns',      'mermaid',  'Chantilly lace over silk crepe', array['ivory','blush'],            '#FFFFFF', 3600, 18, true,  true,  'Fitted through the knee and flaring into a scalloped lace hem. The lace is cut so the motifs meet at the seams.', 2),
  ('wren',       'Wren',       'haldane', 'Wedding gowns',      'sheath',   'Double-faced crepe',            array['ivory','champagne'],        '#DCCFB8', 2200, 12, true,  false, 'A clean column with a low back. No boning and no beading, so it is light enough for a long day.', 3),
  ('aiko',       'Aiko',       'sora',    'Wedding gowns',      'aline',    'Silk gazar',                    array['ivory'],                    '#E9E2D6', 3100, 16, false, false, 'Folded gazar that holds its shape without a petticoat. Pockets sit in the side seams.', 4),
  ('odette',     'Odette',     'ondine',  'Wedding gowns',      'aline',    'Tulle with 3D silk florals',    array['ivory','blush'],            '#E3A9AE', 3950, 22, false, true,  'Layered tulle scattered with silk petals that thin out toward the hem.', 5),
  ('noor',       'Noor',       'rasika',  'Lehengas',           'lehenga',  'Raw silk with zardozi',         array['red','blush'],              '#C6A15A', 6400, 24, false, true,  'A twelve-kali skirt with a zardozi border, a matching blouse and a net dupatta finished in gota.', 6),
  ('rani',       'Rani',       'kesar',   'Lehengas',           'lehenga',  'Silk velvet with dabka',        array['emerald','red'],            '#C6A15A', 4200, 20, false, true,  'Velvet for a winter wedding, embroidered in dabka and finished with a Banarasi dupatta.', 7),
  ('gulnaar',    'Gulnaar',    'rasika',  'Pre-wedding events', 'lehenga',  'Organza with gota patti',       array['marigold','blush'],         '#E8C26A', 2900, 14, true,  true,  'Light enough to dance in. Made for mehndi and sangeet, with a flared skirt and a short dupatta.', 8),
  ('saffron',    'Saffron',    'kesar',   'Pre-wedding events', 'sari',     'Handwoven Banarasi silk',       array['marigold','red'],           '#C6A15A', 1200, 10, true,  true,  'Woven in Varanasi with a zari border. Comes with an unstitched blouse piece, which we can tailor to your measurements.', 9),
  ('tamsin',     'Tamsin',     'haldane', 'Pre-wedding events', 'sheath',   'Wool-silk crepe',               array['dusk','ivory'],             '#B9C6D6',  680,  6, false, false, 'A midi sheath for the rehearsal dinner or the registry office.', 10),
  ('pilar',      'Pilar',      'lumbre',  'Reception',          'jumpsuit', 'Silk crepe, lace cape',         array['ivory','black'],            '#F3ECDF', 1850, 10, true,  false, 'Wide-leg jumpsuit with a detachable floor-length lace cape for the entrance.', 11),
  ('isadora',    'Isadora',    'ondine',  'Reception',          'sheath',   'Beaded tulle',                  array['champagne','gold'],         '#FFFFFF', 2750, 14, false, true,  'A column covered in glass bugle beads, cut to move under reception lights.', 12),
  ('hana',       'Hana',       'sora',    'Reception',          'aline',    'Silk charmeuse',                array['champagne','ivory'],        '#E6D2B0', 1450,  8, true,  false, 'A bias-cut slip dress for the after-party. The cowl back is weighted so it stays in place.', 13),
  ('fern',       'Fern',       'juniper', 'Bridesmaids',        'aline',    'Recycled chiffon',              array['sage','dusk','blush'],      '#FFFFFF',  240,  8, true,  false, 'A wrap-front chiffon A-line in 14 sizes. It mixes with Clover for a coordinated party.', 14),
  ('clover',     'Clover',     'juniper', 'Bridesmaids',        'sheath',   'Stretch satin',                 array['sage','emerald','champagne'], '#FFFFFF', 210,  8, true,  false, 'Square neck and adjustable straps. The stretch makes it forgiving to buy online.', 15),
  ('mira',       'Mira',       'juniper', 'Bridesmaids',        'lehenga',  'Georgette with mirror work',    array['blush','sage','marigold'],  '#E8E2D0',  480, 10, true,  true,  'A lightweight lehenga set for bridesmaids, with a crop blouse and a georgette dupatta.', 16)
on conflict (id) do update set
  name = excluded.name, designer_id = excluded.designer_id, category = excluded.category, silhouette = excluded.silhouette,
  fabric = excluded.fabric, colors = excluded.colors, trim_color = excluded.trim_color, price_usd = excluded.price_usd,
  lead_weeks = excluded.lead_weeks, rush_available = excluded.rush_available, embellished = excluded.embellished,
  description = excluded.description, sort = excluded.sort;
