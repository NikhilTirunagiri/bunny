# Spec E — Bunny v3 redesign

Date: 2026-11-13 · Status: agreed with Rahul in a design interview; Nikhil is fine with Rahul driving.
Builds on Specs A–D (v2.0.0, tag `v2.0.0`, commit `ac5b2ac`). Where this spec disagrees with A–D, this spec wins.
Visual reference (private prototype): https://claude.ai/artifact/UMjGiHLGaBeLbUEPjXhHB9

## 1. Intent

Bunny is a quick-notes list in the menu bar that can hand a note to a coding agent. It is a notes
app first; the agent is one quiet action. v2 made the agent the centre, left v1.0's features behind
(delete, shortcuts), and shipped with a set of window and interaction bugs. v3 fixes the bugs,
restores what v1.0 had, and reorganises the UI so a row shows a note and its state and nothing else.

Constraints:
- Lightweight. No third-party dependencies. Nothing agent-related runs until an agent is enabled and used.
- macOS 26+. Native look (Liquid Glass via system APIs), following Apple's layout conventions: one
  primary action per surface, destructive actions last and apart, rare actions in menus, secondary
  detail folded.
- Local only. No account, no sync.
- Bundle identifier stays `nikhiltirunagiri.bunny` so existing data carries over.

Vocabulary used in the UI: "note" (the model stays `BunnyTask`), "details" (the note's text,
`taskDescription`), "Attachments" (was "Shelf"; the model stays `ShelfItem`), "Hand off".

## 2. Delivery

One branch, `redesign`, off `main`. One commit (or a few) per phase; Rahul tests a build after each
phase. One PR for v3.0.0 at the end, on Rahul's go. Nothing is pushed before that.

| Phase | Content |
|---|---|
| 1 | Repo hygiene, the single window, click/select/keyboard model, context menu, delete to Trash with Archive/Trash tabs, the v2 bug list (§11) |
| 2 | Row and note-side redesign: badges, Completed group, new notes on top, long-text split, search, attachments (paste, stored copies), quick capture, undo, links, copy as prompt, keyboard reorder, shared button style |
| 3 | Settings window redesign, glass toggle, retention rules, Data page, export, backup before upgrade, check for updates, global shortcut, ⌘Q |
| 4 | Agents: enable toggles, lazy start, ask-first default, folder rule and options card, real model names, state UI, messaging thread, note/agent fold, menu bar dot, two-page welcome |
| 5 | README, release script, v3.0.0 |

Parked for v3.1: background image behind the notes (blurred once and cached, strength slider);
folder memory for new notes; optional long-delay hover preview.

Not doing: sync, accounts, tags, folders/projects for notes, rich text or Markdown rendering,
a built-in screenshot tool.

## 3. The window

One window replaces the `NSPopover` plus child `NSPanel` of v2.

- A borderless, non-activating `NSPanel` that can become key, positioned under the status item,
  right-aligned to it and clamped to the screen's visible frame. No popover arrow.
- Two columns in one surface, split by a thin divider: the **note side** (left, ~328 pt) and the
  **list** (right, 340 pt). With no note open the window is the list alone. Opening a note grows
  the window to the left; the list never moves. If there is no room on the left, it grows right.
- Closing: the window closes when it resigns key (click in another app, on the desktop, on another
  Bunny window), on Esc (Esc first closes the note side, or leaves search, or ends a text edit; then
  closes the window), on a status item click, and when Settings or Welcome opens. It does not close
  while one of its own alerts, menus or the timer picker is showing.
- Closing never deletes anything. Edits are saved as typed.
- Reopening always shows the notes list (never Archive), no note open, focus in the New note field.
  Exceptions: the note side is pinned (§5), or Bunny was opened from an agent notification (opens on
  that note).
- Appearance follows the Bunny theme setting and live system changes.
- Surface: system glass by default; a solid material when the user picks Solid or the Mac has
  Reduce Transparency on (§8).
- Dragging a file onto the status item still opens the window (Spec A §5.3).

## 4. The list

Top to bottom: New note field, notes, Completed group, bottom bar.

**New note field.** Leading plus, placeholder "New note", trailing round search button. Return adds
the note at the **top** of the list. If the text has more than one line, or is longer than ~120
characters with a sentence break, the first line/sentence becomes the title and the rest goes into
the details. ⌘N focuses the field.

**Search.** The search button or ⌘F turns the field into a search field (the button grows leftward
into the field, ~0.2 s, instant under Reduce Motion). It matches titles and details. Matches from
the Archive are listed under an "In Archive" heading. Esc returns to New note.

**Row.** Checkbox, title (one line), then at most: small badges (details present, attachment count,
subtask progress `1/2`, running timer countdown), and one hover action (Hand off; only when an
agent is enabled and the note is top-level). No other buttons on the row. Subtasks are indented one
level, with a disclosure chevron on parents that have them. Row highlight insets match the field.

Row state:
- Open: empty circle.
- Completed by the user: blue tick. Completed by an agent: green tick.
- Agent working: accent title with shimmer, small accent dot.
- Agent waiting on the user: yellow "?" in the circle, yellow title.
- Agent failed: red "!" in the circle.

**Click model.**
- Click: select the note and open the note side at once. Click the selected note again: close the
  note side (unless pinned).
- Double-click the title: rename in place.
- Shift-click / ⌘-click: extend / toggle the selection. With more than one note selected the note
  side closes and the bottom bar becomes "N selected · Complete · Archive · Delete".
- Hover only highlights. Nothing opens on hover.
- Right-click: Edit Title, Add Subtask, Show in Menu Bar (was "Pin"), Set Timer…, Hand Off to
  <agent> (when enabled), Copy as Prompt, Archive, Delete. Delete is last, after a separator.
  With a multi-selection the menu offers Complete, Archive, Delete.
- Drag: reorder, or drop on a note to nest (Spec D rules, unchanged). Dropping files on a row
  attaches them.

**Keyboard.** ↑/↓ move the selection (the note side follows when open). Return opens the note side.
Space toggles complete. ⌫ moves to Trash. ⌥↑/⌥↓ reorder. ⌘N new note. ⌘F search. ⌘C copy as
prompt. ⌘Z undo. ⌘, Settings. ⌘Q quit. Esc as in §3.

**Completed group.** Completed notes leave the active list and sit under a folded "N completed"
header at the bottom (Google Keep style). Click the header to unfold. Unticking sends a note back
up. Completed notes move to the Archive on the schedule in Settings (§8).

**Bottom bar.** Left: Archive and Trash. Right: Settings. During a multi-selection it shows the
selection actions instead. After delete/archive/complete it shows an Undo strip for a few seconds
("Moved 2 notes to Trash · Undo"); ⌘Z does the same.

**Quick capture.** While typing a new note, if the clipboard holds an image or file, a strip under
the field offers "Attach the copied screenshot"; Tab accepts, Return alone ignores it. Only the
pasteboard's types are inspected until the user accepts.

## 5. The note side

Header: pin and close buttons, top right.
- **Pin** keeps the note side open: it follows the selection and is restored when the window
  reopens. Unpinned (default) it closes on a second click of the note, Esc, or the close button.
- **Close** closes the note side.

Body, one scroll area:
1. Title, editable in place.
2. Details: plain text, grows with content. Empty: a grey "Add details…" hint; the empty space is
   the writing area. URLs are clickable.
3. Attachments: a strip of thumbnails/icons with names, and a plus. Empty: one line, "Drop or paste
   a file to attach it". Dropping anywhere on the note side attaches; ⌘V attaches an image or file
   from the clipboard. Dropped files and folders are **linked** (bookmark, Spec A). Pasted images
   are **stored** as files under `Application Support/Bunny/Attachments/<note id>/` and removed when
   the note is deleted for good. Context menu and drag-out as in Spec A.
4. Footer: created/edited line; Hand off button with a small arrow for options, and a caption
   showing the agent and folder a hand-off would use. Hidden when no agent is enabled or the note
   is a subtask.

No save button and no edit mode: every change is saved as typed.

## 6. Archive and Trash

The Archive button swaps the list for a view with a back arrow and two tabs.

**Archive.** Grouped by day. Hover: Restore and a trash button. Selection as in the list, with
Restore / Move to Trash. Bottom bar: count and **Move All to Trash**.

**Trash.** Each note shows its days left. Nothing selected: "Deleted after N days" and **Empty
Trash**. With a selection: Restore / Delete Forever. Delete Forever and Empty Trash confirm once,
with a "do not ask again" checkbox (and a setting to re-enable).

**Model.** `BunnyTask.deletedAt: Date?`. Delete sets it (subtasks follow their parent); the note
leaves the list and the Archive. Restore clears it (the note returns to where it was: active or
archived). Purge deletes the row, its subtasks, its `ShelfItem`s and its stored attachment files,
and stops any agent. Deleting or archiving a note with a live agent stops the agent first.
Pure rules (days left, expiry, what to purge, what to auto-archive) live in Core with tests.

## 7. Agents

Bunny hands a note to Claude Code or Codex with its title, details, subtasks, attachments and timer
(Spec B), and shows state on the note. Changes from v2:

**Enable.** Each agent has an on/off toggle. With both off, every agent control disappears and no
agent code runs (no shell probe, no model fetch, no server). Detection and the Codex model list are
fetched when an agent is turned on or first used, not at launch.

**Permissions.** Default is "Ask before running commands". "Autonomous" is an opt-in under Advanced.

**Bunny tools (MCP server).** Off by default, under Advanced. The listener starts only while it is on.

**Folder.** Order: the folder picked for this run; else a folder attached to the note; else the
default in Settings. The default is "Bunny folder" (an empty per-agent folder under
`Application Support/Bunny/Workspaces/`) or a folder the user chooses. The home folder is never used.

**Hand off.** Clicking Hand off starts at once with the resolved settings. Its arrow opens an
options card: Folder (recent folders, Bunny folder, Choose Folder… via the open panel), Agent,
Model, Effort, and a Hand off button. Choices apply to that note. Model and Effort show real names:
Codex reports its defaults; for Claude Code, the name reported by the last run, or "Default" before
any run. A note's explicit choice is stored separately from "what the last run used", so a note that
once ran on Codex does not keep using Codex against the user's default (v2 bug).

**State in the note side.** One status line, then what fits the state:
- Working: live one-line activity; a small line with model, effort and folder; Open session, Stop.
- Needs input: the question at the top with its options; Send is the only primary button.
- Failed: one plain sentence; raw error folded under Details (no nested scroll); Try again, Copy details.
- Finished: short summary; Open session. The note is ticked green and drops into Completed.

**Messaging.** Whenever a note has a session, a message field sits at the bottom of the agent part.
Sending continues the same session in the same folder (live runner, or resume). If the agent is
mid-step the message is delivered when the step ends. A short thread shows the user's messages and
the agent's replies (turn-final text only; no tool noise), last exchange visible, earlier ones
behind "Show N earlier messages". The thread is stored with the note, capped in length. Open
session remains for the full log.

**Note/agent fold.** The note side shows either the note or the agent in full. While an agent is
active the note folds to two lines plus an attachment count; clicking it opens the note and folds
the agent to one status line; clicking that line swaps back. A question from the agent opens the
agent part by itself.

**Attention.** Needs input: notification, yellow row, and a yellow dot on the menu bar icon until
answered. Clicking the notification opens Bunny on that note.

**Copy as prompt.** ⌘C / menu: title, details, subtasks and attachment paths as plain text.

## 8. Settings

A normal-level, reusable window; Bunny shows in the Dock only while it (or Welcome) is open.
Opening it closes the main window. It goes behind other apps when they are clicked.

Layout: sidebar with a search field and six pages; the detail pane is a column of cards; each row
is icon tile, title, one-line caption, control. One list of pages and their rows feeds both the
sidebar and search (search matches row titles and jumps to the row).

- **General**: Launch at login · Global shortcut (unset until chosen; opens Bunny focused on New
  note) · Show the pinned note in the menu bar · Welcome guide (Open) · Quit Bunny (⌘Q; stops
  running agents first).
- **Appearance**: Theme (System/Light/Dark) · Surface (Glass/Solid; forced Solid under Reduce
  Transparency) · Background image (disabled, "v3.1").
- **Notes**: Move completed notes to Archive (At midnight / After 24 hours / Never) · Delete
  archived notes (Never / After 30 / 90 days → Trash) · Empty Trash (After 7 / 30 / 90 days /
  Never) · Ask before deleting forever.
- **Agents**: Claude Code toggle with status · Codex toggle with status · Default agent · Open
  sessions in · Default folder · Advanced (folded): CLI paths, model and effort per agent,
  permissions, Bunny tools.
- **Data**: Stored on this Mac (sizes; Show in Finder) · Export all notes (Markdown files plus
  attachments, to a chosen folder) · Clear Archive (→ Trash) · Empty Trash · Erase all data
  (confirm; last, alone).
- **About**: icon, version, authors, repository link, Check for updates (queries the GitHub
  releases API for the latest release and links to it; manual, nothing installs itself).

## 9. Welcome

Two pages, both skippable. Page 1: what Bunny is, in three rows. Page 2: agents (optional): the two
toggles with detection status. Closing or skipping counts as done.

## 10. Data and upgrade

- Store: `~/Library/Application Support/Bunny/Bunny.store` (SwiftData), as in v2. Additive fields
  only (lightweight migration): `deletedAt`, the agent message thread, per-note folder and explicit
  agent choice.
- First launch of v3 copies the store files to `Application Support/Bunny/Backups/pre-v3/` before
  the container opens it, once.
- Version `3.0.0`.

## 11. v2 bugs to fix (root causes traced)

1. Window would not close; Settings did not close it; locked panel stuck: `performClose` fails while
   a child window is attached. Resolved by §3 (single window, close on resign key).
2. No way to close the panel; "lock" was invisible. Resolved by §4/§5 (selection, pin, close).
3. ~1.5 s click delay: single tap waits on the title's double-tap gesture. Selection must fire on
   mouse-down / without waiting; detect double-click by click count.
4. Archiving a note whose panel is open leaves a blank stuck panel: clear selection/open note on
   archive and delete. Retest "details dead after restore" after this.
5. Caret drawn over the "Add a description…" placeholder (inset mismatch).
6. Stray `Divider()` row in Settings "Model & effort".
7. "Default agent" segmented picker shows four segments (HStack label split in two).
8. Settings window lands in another app's full-screen Space and stays on top: set the activation
   policy and activate before ordering front; explicit collection behavior.
9. Row highlight wider than the field (6 pt vs 10 pt insets); Archive rows have no inset.
10. Archive view sticks across reopen. Resolved by §3.
11. A note that once ran on Codex always uses Codex (§7 Hand off).
12. A failed run keeps showing "Starting…".
13. "Chat about this" on a failed run with no session starts a new run.
14. Esc does nothing while a non-empty text view has focus.
15. In System theme the window does not follow a live light/dark switch.
16. No hover feedback on any button: one shared button style (hover wash, slight scale, press
    state, no motion under Reduce Motion).

## 12. Code organisation and testing

- Pure rules stay in `bunny/Core/` (Foundation only, `swift test`): selection model (click, shift,
  ⌘, keyboard), trash/retention rules, new-note title/details split, search matching, folder
  resolution, run-settings resolution, window placement. Each gets unit tests.
- App-side code is verified by `xcodebuild` and by Rahul testing each phase build; nobody but the
  user can judge look and feel.
- `HoverIntent` and the hover/lock coordinator are removed with the popover/panel pair.
- No new dependencies.

## 13. Amendments after Phase 1–2 testing (these win over the sections above)

- **No Archive.** The Archive feature is removed everywhere (§4, §6, §8). The app has the notes
  list with its Completed group, the Trash, and Settings. Notes archived by older versions are
  moved to Trash once at launch (`deletedAt = now`, `archivedAt` cleared; the property stays for
  schema stability and nothing else reads it).
- **Completed retention.** Completed top-level notes move to Trash after `notes.completedRetention`:
  24 hours (default), 7 days, or never. Done subtasks stay under an open parent. Restoring a
  completed note from Trash resets `completedAt`. Settings → Notes has this instead of the two
  archive rows.
- **Bottom bar is permanent**: Trash (soft red) at the left, Settings at the right, in every view.
  In the Trash view the Trash button is active and returns to notes; a slim header with a back
  chevron and title sits at the top; Esc goes back.
- **Action strip.** Selection actions, Undo (3 s), the Copied notice and the Trash view's standing
  line ("Deleted after N days" + Empty Trash) live in one strip above the bottom bar, never in it.
- **Trash keyboard**: ⌘A, ↑/↓, ⌫ (Delete Forever via the confirmation), Esc.
- **Window**: the list hangs to the right of the status item; the note side opens to its left. The
  window frame is constant and the card is drawn in SwiftUI; only the card animates. The surface is
  solid for now (glass left a ghost on close and, applied to content, blocks drops); a Glass option
  returns only if both are solved.
- **Search**: an empty-space click leaves search.
- **Timer**: starting a timer shows the note in the menu bar by default (checkbox in the picker);
  the end-of-timer notification fires for every timer.
- **Agents (pulled forward from Phase 4)**: never the home folder (Bunny's own empty folder is the
  default workspace); "Ask before running commands" is the default; the row's agent button never
  opens an external app.
- **Tooling**: `bunny --snapshot <dir>` (Debug) renders fixed UI states to PNGs; implementers use
  it to check layout. Nothing may script the desktop or need a privacy permission.
