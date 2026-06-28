# Changelog

All notable changes to the **Server Auction House** mod will be documented in this file.

## [1.3.3.0] - 2026-06-28

### Added
- **BRAIN Bot Profile:**
  - Added the **BRAIN** bot bidding profile (assigned to bot "Anderson").
  - Implemented a stable 5% chance of the bot playing "pranks" on specific auctions (bidding up to 150% of store value, high bid frequency, large bid increments).
  - Implemented smart behavior for other 95% of auctions (limiting bids to 70%-85% of store value to buy cheap, bidding minimum increments).

## [1.3.2.0] - 2026-06-28

### Fixed
- **Header Icon Customization:**
  - Pointed the page title header icon (`headerIcon`) to the custom `icon_AuctionTab.png` instead of the base game finances image slice.
  - Also synchronized this change to **Server Journal**'s page title header, pointing it to custom `icon_JournalTab.png`.

## [1.3.1.0] - 2026-06-28

### Added
- **Menu Tab Custom Icon:**
  - Created a custom tab icon `icon_AuctionTab.png` showing a minimalist white gavel silhouette with transparent background.
  - Registered the custom icon for the in-game menu tab, disabling the base game finances icon override.
  - Done the same for **Server Journal** using a custom `icon_JournalTab.png` diário tab icon.

## [1.3.0.0] - 2026-06-28

### Added
- **History Tab:**
  - Added the **History Tab** to the Auction House UI.
  - Implemented persistent saving and loading of ended auctions in `server_auctions.xml`.
  - Implemented a rolling limit of **30 ended auctions** in history to prevent savegame XML bloat.
  - Configured History cells to show "Sold" or "No Bids" in place of remaining time.
  - Configured History detail view to display "Status: Ended" and hide the bidding input panel.
  - Added Spanish and French translations for the new history tab labels.

## [1.2.3.0] - 2026-06-24

### Added
- **New Translations:**
  - Added full support for **French** (`translations/lang_fr.xml`) translation, including UI labels, error messages, global announcements, and French bot names (e.g., Pierre, Jean, Camille, Chloé).
  - Added full support for **Spanish** (`translations/lang_es.xml`) translation, including UI labels, error messages, global announcements, and Spanish bot names (e.g., Alejandro, Carlos, Sofía, Elena).
- **Mod Description Translations:**
  - Added French and Spanish localized description blocks in [modDesc.xml](file:///g:/Users/Administrador/Documents/My%20Games/FarmingSimulator2025/mods/FS25_ServerAuctionHouse/modDesc.xml).
  - Registered `fr` and `es` under the `supportedLanguages` attribute in `modDesc.xml`.
