# dot.

Suite name: **dot.** Always lowercase, with the full stop. Repository and package identifiers use `dot` without punctuation.

Product names: **read.**, **listen.**, **Immersed**. Do not rename bundle identifiers, URL schemes, repositories, or existing user data directories as part of branding updates.

Suite signature: “Part of dot.” Tagline: “A quieter way to read, listen, and learn.”

Use the suite signature in About, onboarding completion, and the website footer. Companion links belong in About or Settings, with each app's purpose stated. Keep primary reading, listening, and learning screens focused on their content.

The SVG assets are initial vector identity assets. The shared circle connects the family; each app uses a distinct accent. Preserve existing application icons until a platform-specific icon is deliberately designed and reviewed. These are not production macOS or iOS icon packages.

## Layout and type

Use the system font for controls and settings. Reading surfaces may retain user-selected fonts. Use semantic spacing and radius tokens. Native platform navigation, focus, selection, and accessibility conventions take priority over cosmetic uniformity.

Use light and dark semantic colors. Accent colors are decorative or emphasis colors; do not assume they meet text contrast requirements in every context. Validate contrast in the actual component, support keyboard navigation and text scaling, and honor reduced motion.

## Icon rules

Prefer SF Symbols in native Apple surfaces and the existing icon library elsewhere. Use one consistent outline weight within each app; match meaning across apps (Settings, Search, Library, Share). Standard artwork grid: 24 × 24, 2-unit stroke, round caps, 2-unit clear space. Pair unfamiliar icons with text. Never use color as the only state indicator.

## Adoption

The exported CSS and TypeScript map to the JSON source. Swift consumers can load the JSON as a bundled resource and map semantic roles to native Color/font/spacing APIs. Adopt tokens component by component; importing this kit alone does not restyle an app.
