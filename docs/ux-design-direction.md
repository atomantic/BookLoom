# BookLoom UX Direction

## Product Shape

BookLoom should feel like a quiet operating surface for a reading group: fast to scan, warm enough for books, and dense enough that the next useful action is visible without digging. The app is not a marketing site once the user has onboarded; returning screens should prioritize current reads, proposals, ratings, notes, and sharing state.

## Design Principles

- First viewport carries the workflow. On iPhone, Clubs should show the summary plus at least one club row; a club home should show the current read and the first proposal; a submission detail should show the book, rating control, and note entry with minimal scrolling.
- Headers are earned. Keep the navigation title, then use compact in-content headers only when they separate different tasks. Avoid a card header followed by a section header followed by another card title.
- Cards frame work, not decoration. Use small radius, moderate padding, and cards for rows, controls, empty states, and compact summaries. Avoid nesting cards inside cards.
- Metrics are scan aids. Use short inline metric tiles, not tall stat blocks. Counts should answer "what changed?" without pushing rows down.
- Forms start quickly. Use a compact contextual header, then fields. Save large imagery for onboarding and empty states.
- macOS needs the same density with wider breathing room. Reuse compact components, but let lists and forms cap their width so the app does not become a stretched iPhone layout.

## Current Pass

- Tightened shared card/list primitives in `BookLoomDesign.swift`.
- Reworked club list and club home dashboards into compact summary bands.
- Reduced proposal/current row height by shrinking covers, card padding, spacing, and metric tiles.
- Collapsed Submission Detail from separate Book, Description, Your Rating, Group Ratings, Add Note, and Notes blocks into Details, Ratings, and Notes.
- Consolidated Settings into Preferences, Sync, and About instead of five separate sections.
- Converted New Club and Add Book sheets from large vertical hero stacks to compact contextual headers.

## Screen Direction

### Clubs

The default state should be a compact dashboard and a dense list of clubs. Each club row needs name, current read or proposal count, and small badges for read/member/note counts. The create action belongs in the toolbar once the user has clubs; the empty state can remain more expressive.

### Club Home

This is the main work surface. The current book is the anchor, followed immediately by proposals. Completed books are secondary history and can stay below active work. Next improvements should add a small sync/sharing indicator in the toolbar and make meeting date/reminder state visible on the current row.

### Submission Detail

Treat this as a decision and discussion panel. The top should answer: what book, what status, what is my rating, what is the group rating, and where do I add a note. Long metadata and description should not outrank rating and note actions.

### Add Book

The form should accept a title first, then progressively enrich with metadata. Cover art is helpful feedback after lookup, not the primary content before the user can type.

### Settings

Settings should remain utilitarian. Keep profile, appearance, welcome replay, sync status, and version info grouped tightly. Avoid turning setup/status explanations into separate full-height sections unless they require action.

## Follow-Up Plan

- Add lightweight SwiftUI previews or snapshot-friendly fixtures for Clubs, Club Home, Submission Detail, and Add Book in populated and empty states.
- Add meeting date and reminder UI as compact metadata on the current read, not a new top-level screen.
- Add member list and sharing health as a small club-home surface, with full invite management behind the existing Invite action.
- Review macOS navigation after the content model stabilizes. A sidebar may make sense once clubs, members, and meetings become deeper than the current two-tab app.
- Capture App Store screenshots only after the density pass and meeting/reminder surfaces are stable.
