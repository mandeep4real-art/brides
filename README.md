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

## Run locally

Open `index.html` in a browser.

## Limitations

- All designers, products, prices, reviews and stories are sample content.
- Checkout and booking are not connected to any backend; nothing is charged or sent.
- The board and bag are stored in the visitor's browser (`localStorage`).
