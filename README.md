# Trousseau Row

A prototype storefront for a multi-designer bridal marketplace. It is a single static page (`index.html`) with no build step and no dependencies apart from Google Fonts.

## Features

- **Wedding-date timeline.** Enter a date and every piece shows its last order-by date. The date allows for production lead time plus 4 weeks of fittings. Pieces can also be filtered to those that arrive in time.
- **Catalogue.** 16 sample pieces from 7 sample ateliers, filterable by category, designer, silhouette and budget.
- **Product configurator.** Choose colour, options with transparent price changes, a standard size or made-to-measure, and rush production. The 50% deposit is shown up front.
- **Wedding board.** A saved shortlist that can be copied as text to share.
- **Bag and swatch box.** Swatches cost $15 for a box of up to 5.
- **Size finder.** Recommends a US size from bust, waist and hip.
- **Real brides.** Stories filtered by venue and height.
- **Stylist booking.** Appointment request with a short style intake.

## Backend (Supabase)

The page talks to Supabase directly over its REST API; there is no server of our own.

- **Catalogue.** `designers` and `products` are read from Supabase. Edit them in the Table Editor and the site updates on the next page load. If Supabase can't be reached, the page falls back to the catalogue built into `index.html`.
- **Stylist bookings.** Saved to `appointments`. Booked times are hidden from other visitors through the `taken_slots` function, and a unique index stops double-booking.
- **Order requests.** The bag sends its contents to `order_requests`. No payment is taken.

Set up a new project by running [`supabase/schema.sql`](supabase/schema.sql) in the Supabase SQL Editor. The anon key in `index.html` is public by design: row-level security only lets visitors read the active catalogue and create requests. They can't read, change or delete anyone's requests.

## Run locally

Serve the folder with any static file server, for example `npx serve .`, and open the printed address.

## Limitations

- All designers, products, prices, reviews and stories are sample content.
- No payments are taken. Order and booking requests are stored, but nothing emails the customer yet.
- Reviews and real-bride stories are still built into `index.html`.
- The board and bag are stored in the visitor's browser (`localStorage`).
