# Changelog

All notable changes to the **Server Journal** mod will be documented in this file.

## [1.1.1] - 2026-06-28

### Fixed
- **Header Icon Customization:**
  - Pointed the page title header icon (`headerIcon`) to the custom `icon_JournalTab.png` instead of the base game contracts image slice.

## [1.1.0] - 2026-06-28

### Added
- **Menu Tab Custom Icon:**
  - Created a custom tab icon `icon_JournalTab.png` showing a minimalist white journal silhouette with transparent background.
  - Registered the custom icon for the in-game menu tab, disabling the base game contracts icon override.

## [1.0.9] - 2026-06-27

### Added
- **New Translations:**
  - Added full support for **French** (`translations/lang_fr.xml`) translation, including UI labels, settings, and tooltips.
  - Added full support for **Spanish** (`translations/lang_es.xml`) translation, including UI labels, settings, and tooltips.
- **Mod Description Translations:**
  - Added French and Spanish localized description blocks in `modDesc.xml`.

## [1.0.8] - 2026-06-23

### Added
- **Security & Validation:**
  - Implemented client-to-server request validation and security checks.
- **Server Settings:**
  - Added server-configurable settings menu allowing customization of maximum posts per player, auto-cleanup duration in days, and chat announcements.
- **Automated Cleanup:**
  - Implemented automated background cleanup of expired/old journal posts.
- **Chat Announcements:**
  - Added optional chat notifications when new events are logged to the journal.
- **UI Improvements:**
  - Enhanced UI formatting and layout responsiveness.

## [1.0.7] - 2026-06-22

### Added
- Initial in-game settings page hook and layout registration structure.
