# Contrast rule: colour formats beyond hex and rgb()

The OpenComposer fork's contrast rule (`text_color_on`, #164) picks black or white text for the navbar, dropdowns, footer, category headings and description banners from the background colour the config sets. It reads only `#RGB` and `#RRGGBB` (either with alpha) and `rgb()` with plain numbers. Any other colour, whether named (`yellow`, `gold`), `hsl()` or `rgb()` with percentages, gets white text, which is how every colour was handled before the rule existed. The fork's README and `docs/install.html` state the limit.

## Why this is out of scope

IRIS's config, and the fork's own defaults, write colours in hex. A hex value is the one form a theme colour is normally given in, and the documented limit tells anyone using another form what to write instead. Each way of widening the rule costs more than it saves:

- **Reading named colours and `hsl()` on the server** means carrying CSS's 148-entry named-colour table and an HSL conversion in the fork. That's code to maintain, and to defend upstream, for a config that can just as easily say `#ffd700` instead of `gold`.
- **Computing the colour in the browser** (`getComputedStyle`) reads every CSS form, but it moves the rule out of the ERB into JavaScript, and the text colour only settles after the page loads.

If an upstream reviewer asks about it when the rule is offered (#169), the answer is the documented limit: write the colour in hex or `rgb()`.

## Prior requests

- #178: "Contrast rule reads only hex and rgb() colours"
