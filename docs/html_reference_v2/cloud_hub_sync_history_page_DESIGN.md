# Design System Strategy: The Ethereal Vault

## 1. Overview & Creative North Star
**Creative North Star: "The Digital Singularity"**
This design system moves away from the utilitarian "folder-and-file" metaphor of traditional cloud storage. Instead, it treats data as a luminous, living asset. By leveraging the infinite depth of AMOLED black and the high-energy vibration of Cyan and Electric Purple, we create an interface that feels less like a tool and more like an advanced AI consciousness.

The layout rejects rigid, boxy grids in favor of **Intentional Asymmetry**. We utilize overlapping glass surfaces and "floating" typography to create a sense of vast, 3D space. This system is designed to feel premium, cinematic, and profoundly futuristic—bridging the gap between a linguistic coach and a high-security data sanctum.

---

## 2. Color & Atmospheric Depth
The palette is rooted in the "Infinite Void." To ensure the UI feels high-end, we follow strict rules regarding boundaries and transitions.

### The "No-Line" Rule
Traditional 1px borders are strictly prohibited for sectioning. Structural boundaries must be defined solely through background shifts.
*   **Base:** Always start with `surface_container_lowest` (#000000) to maximize AMOLED power savings and depth.
*   **Sectioning:** Use `surface_container_low` (#131313) or `surface_container` (#191919) to define different functional areas. The transition between these deep tones creates a "felt" boundary rather than a "seen" one.

### Surface Hierarchy & Nesting
Treat the UI as a series of nested physical layers. 
*   **Level 0 (The Void):** `surface_container_lowest` (#000000)
*   **Level 1 (The Bed):** `surface` (#0e0e0e)
*   **Level 2 (The Module):** `surface_container_high` (#1f1f1f)
*   **Level 3 (The Interaction):** Glassmorphic overlays using `surface_variant` (#262626) at 40-60% opacity with a `20px` backdrop blur.

### Signature Textures & Glows
*   **The Cyan Pulse:** Use a linear gradient from `primary` (#c1fffe) to `primary_dim` (#00e6e6) for data-centric CTAs.
*   **The Purple Aura:** Use `secondary` (#d575ff) with a soft outer glow (drop-shadow: 0 0 15px) to indicate AI-assisted linguistic functions or "active" storage sectors.

---

## 3. Typography
The typographic system creates a tension between high-tech "Space Grotesk" and the highly legible, human-centric "Manrope."

*   **Display & Headline (Space Grotesk):** These are your "Architectural" elements. Use `display-lg` for data totals (e.g., "1.2 TB") with tight letter-spacing (-0.02em) to evoke a sleek, technical feel.
*   **Titles & Body (Manrope):** These are your "Communication" elements. `title-md` should be used for file names, while `body-md` handles the linguistic coaching insights. 
*   **Hierarchy Note:** To achieve an editorial look, contrast the `display-lg` size against a `label-sm` metadata tag. The extreme scale difference is what conveys "premium design" over "standard app."

---

## 4. Elevation & Depth
In a futuristic AMOLED environment, shadows are not dark; they are **Ambient Light.**

*   **The Layering Principle:** Depth is achieved by "stacking." A `surface_container_highest` (#262626) card sitting on a `surface` (#0e0e0e) background provides all the "lift" required. 
*   **Luminous Shadows:** For floating elements (like modals), do not use black shadows. Use a 4% opacity glow of the `primary` (Cyan) color with a blur of `40px` to simulate the light of the screen reflecting off the data.
*   **The Ghost Border:** If a boundary is required for accessibility, use the `outline_variant` (#484848) at **15% opacity**. It should be felt as a subtle shimmer at the edge of a glass panel, never as a hard line.
*   **Glassmorphism:** All floating modules must use `backdrop-filter: blur(12px)`. This allows the vibrant purple and cyan accents in the background to bleed through, ensuring the UI feels integrated into a single atmosphere.

---

## 5. Components

### Buttons (The Kinetic Triggers)
*   **Primary:** A gradient of `primary_dim` to `primary_container`. High-contrast `on_primary_fixed` text. Roundedness: `full`.
*   **Secondary:** Glass-filled. Background is `surface_variant` at 30% opacity with a `ghost border`. 
*   **Active State:** Add a `2px` outer glow of `secondary` (Electric Purple) to indicate the AI is "thinking" or processing the request.

### Status Indicators (The Vital Signs)
*   Instead of standard dots, use **Glow Orbs**. A small circle using `tertiary` (#63baff) with a `5px` blur indicates a stable cloud connection. If the AI Linguistic Coach is active, the orb shifts to `secondary_dim` (#b90afc).

### Input Fields (The Data Portal)
*   **Style:** No background fill. Only a bottom "Ghost Border."
*   **Focus State:** The bottom border animates into a gradient (Cyan to Purple) and the `label-sm` text glows.

### Cards & Lists (The Knowledge Archive)
*   **Strict Rule:** No dividers. Separate items using `spacing.4` (1.4rem) of vertical white space.
*   **Interaction:** On hover, the background of a list item should shift from `surface` to `surface_container_low`.

### Featured Component: The "Linguistic Nebula"
A custom visualization for the cloud storage module. Instead of a bar chart, use a blurred, rotating gradient sphere using `primary`, `secondary`, and `tertiary` colors. The size and "turbulence" of the nebula represent storage capacity and AI activity levels.

---

## 6. Do’s and Don’ts

### Do:
*   **Embrace the Dark:** Keep 80% of the screen at `surface_container_lowest` (#000000). Let the AMOLED screen disappear into the bezel.
*   **Use Asymmetry:** Place metadata (dates, sizes) in unexpected locations, like rotated 90 degrees or tucked into the corner of a large display heading.
*   **Layer with Intent:** Ensure that every glass panel has a distinct `backdrop-filter` to create a sense of physical stacking.

### Don’t:
*   **Don't use Grey Shadows:** On an AMOLED screen, grey shadows look "muddy." Use tonal glows or simple color shifts.
*   **Don't Overcrowd:** Futuristic UI requires "breathing room." Use the `spacing.8` and `spacing.12` tokens generously to separate high-level modules.
*   **Don't use Pure White for Body:** Use `on_surface_variant` (#ababab) for long-form text to reduce eye strain against the black background, reserving `on_surface` (#ffffff) for headlines.