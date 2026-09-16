# Interview Questions & PLAN.md

Ask these one at a time, in plain, friendly, jargon-free language — never reveal
the question number or any technical framing (no "framework", "API",
"repository", "stack", "backend", "frontend", "container"). After each answer,
briefly confirm what you heard ("Got it — so the app should...") before asking
the next question.

For every question with listed options, make clear the project leader can
describe their own answer instead if none of the options fit.

## Q1 — Project name
"What do you want to call your project?" Any name is fine — something short
that describes what it is.

## Q2 — What it should do
"In your own words, what should this do?" Describe it like explaining to a
colleague — 1 to 5 sentences is plenty.

## Q3 — Who will use it
"Who will use it?"
- A — People on our team or at UAB only
- B — People outside UAB (students, patients, the public, partner organizations)
- C — Both internal UAB users and outside users
- D — Not sure yet

## Q4 — Visual interface
"Does it need a visual interface — a web page people visit?"
- A — Yes — people will open it in a browser and interact with it
- B — No — it works automatically in the background (runs on a schedule,
  processes data, sends notifications, etc.)
- C — Not sure

## Q5 — What people can do
"What should people be able to do with it?" List the main things, in plain
language — "submit a request", "see a report", "upload a file", "get an
answer to a question".

## Q6 — Data
"Does this app need to work with any data?" — either saving new information it
collects, or connecting to something already in use (Banner, ServiceNow,
Oracle, SharePoint, a department database/spreadsheet, another UAB
application).
- A — Yes, save new information this app collects — describe what
- B — Yes, connect to a system you already use — describe which one and what
  it needs to do with it
- C — Both A and B — describe both
- D — No — it doesn't need to save or connect to anything
- E — Not sure

A drives DATA STORAGE in `decision-matrix.md`. B/C drive EXISTING SYSTEM
INTEGRATION in the same file — these are fundamentally different (auto-
provisioned vs. IT-arranged access) and both can apply at once.

## Q7 — Data sensitivity
"Will this app handle any sensitive or protected information?" This is the one
question in the whole interview where a follow-up is worth the extra turn —
see DATA SENSITIVITY in `decision-matrix.md` for why guessing wrong in either
direction is costly.
- A — Student records (grades, financial aid, disciplinary info)
- B — Health or medical information
- C — Payment card, banking, or other financial account info
- D — Research data involving human subjects, or export-controlled data
- E — Social Security numbers or other personal ID numbers
- F — No, nothing like that
- G — Not sure → ask one plain-language follow-up before moving on: "Does it
  include things like grades, health info, Social Security numbers, or
  payment info?" Do not guess or default silently here.

## Q8 — Login
"Do users need to log in?"
- A — Yes — using their UAB email / BlazerID (recommended for internal tools)
- B — Yes — using some other kind of account (describe below)
- C — No — anyone can use it without logging in

## Q9 — AI usage
"Should it use AI?" (answering questions, summarizing documents, reading and
extracting information from files, generating content)
- A — Yes — describe what you want the AI to do
- B — No
- C — Not sure — describe what you have in mind and we'll figure it out

If the answer is "Yes" or "Not sure" AND the description sounds like chatting
with, searching, or summarizing university data/documents (rather than a
bespoke narrow task like classifying a single form field), ask one
plain-language follow-up before generating: "Should this use the university's
shared AI assistant, or does it need its own separate AI connection just for
this app?" See AI USAGE in `decision-matrix.md` for why this matters.

## Q10 — Visual examples
"Do you have any examples of what it should look like?" Mockups, screenshots,
sketches, or just a description — all optional. If yes, have them attach the
files and describe what you see back to them for confirmation. Treat these as
layout guidance for the nav and page stubs — never collect them and then
silently ignore them.

## Q11 — Contact / ownership
"Who should we contact about this project?" Name/email, and department / cost
center. This flows silently into `owner`/`costCenter` tags, the monitoring
alert recipient, and the pipeline approval-gate contact — see LIFECYCLE &
GOVERNANCE in `decision-matrix.md`. Never shown back to the project leader as
a "technical" requirement.

## Q12 — Anything else
"Anything else we should know?" Deadlines, other requirements, anything that
felt important but didn't fit above — or leave blank. Factor this into
PLAN.md and, where it describes behavior, into page stubs.

---

## After all questions are answered

1. Ask if they have mockups, screenshots, or examples (if not already covered
   by Q10 attachments). If yes, describe what you see back to them for
   confirmation.
2. Read back a short plain-English summary of their whole idea.
3. Generate PLAN.md (template below) and write it to the repo root.
4. Tell them: "I've written a plain-English plan — take a look and just say
   'looks good' when you're ready and I'll build the whole thing."
5. **Stop here.** Do not generate anything else in this turn — not the app
   scaffold, not any other file — even if you're confident they'll approve
   it. See the HARD STOP rule in `SKILL.md` — this is the single most
   important rule in this entire skill.
6. Only once they send a **new, separate reply** approving it (e.g. "looks
   good") do you move into generation.

## PLAN.md template

Write to the repo root, in plain English — no jargon, no file paths, no
technical terms.

```markdown
# [Project Name] — Project Plan

<<< ONLY if DATA SENSITIVITY (Q7) flagged this app, insert this banner here,
    before every other section: "⚠ This app will handle [the flagged
    category in plain language]. Before it goes live, [the mapped office —
    see DATA SENSITIVITY in decision-matrix.md] needs to sign off. Building
    and testing the app can continue, but treat it as not-yet-approved for
    real use until that review happens." Omit entirely if Q7 = F. >>>

## What this app will do
One or two sentences in the project leader's own words.

## Who will use it
Plain description from their answer.

## What people can do with it
Bulleted list of the user actions they described.

## What we'll build
Plain-English description of the type of app, what happens when users visit
it, and how it will be secured. Do NOT mention framework names, languages,
or cloud service names — just describe behavior.

<<< ONLY if Q6 = B or C, insert this section: >>>
## Systems this app needs access to
Plain-language bulleted list, one per system named in Q6 (e.g. "Banner — to
look up student enrollment status"). Note underneath: "Your IT team will
need to arrange access to each of these before this part of the app works."

## Who to contact about this project
The name/email and department from Q11.

## What happens next
Once they say "looks good", the app will be built and deployed
automatically. New changes always go to a development version first, then
pass a review step, before they reach the live version everyone else uses.
They'll receive a link when it's live.
```
