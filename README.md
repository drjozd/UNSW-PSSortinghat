# Sortinghat

Sort a class into Microsoft Teams **private channels** by dragging names between
columns.

**Who this is for.** Sortinghat was developed for UNSW lecturers who need better
control over the channels in their Teams sites. Teaching a large course means
splitting a cohort into tutorial or assignment groups, each with its own private
channel, and Teams offers no way to do that in bulk — a lecturer or tutor-in-charge
ends up clicking through the same six-step dialog several hundred times, once per
student, and again every time someone swaps groups. This does the whole cohort in
one pass, from a spreadsheet you already have.

It assumes UNSW conventions where it helps (a bare zID becomes
`z1234567@ad.unsw.edu.au`, and that domain is editable on screen), but nothing in
it is UNSW-specific: it works against any Microsoft 365 tenant where you own the
team.

---

## Before you start

You need three things:

1. **Windows** with PowerShell 5.1 (every Windows 10 and 11 machine has it) or PowerShell 7.
2. To be an **owner** of the team you want to change. Sortinghat can only do what
   you could already do by hand in Teams.
3. An internet connection. The first run installs Microsoft's own Teams PowerShell
   module under your user account — no administrator rights, no IT ticket.

You do **not** need an app registration, an API key, or anything from IT.

---

## Running it

Double-click **`Launch Sortinghat.cmd`**.

A black console window opens and stays open — that window *is* the program, so
leave it alone while you work. Your browser opens on the Sortinghat page.

To stop: press **Finish** in the browser, or just close the console window.

> **First time only:** Windows may say the files came from the internet. Right-click
> the zip *before* extracting it, choose **Properties**, tick **Unblock**, then
> extract. If you have already extracted it, see *When something goes wrong* below.

---

## The five steps

**1. Sign in.** The normal Microsoft sign-in window appears, MFA and all. It
sometimes opens *behind* the browser — check your taskbar. Your password never
passes through Sortinghat.

**2. Choose the team.** Every team your account belongs to is listed. Pick one.
If you are not an owner of it, Sortinghat says so rather than letting you waste
ten minutes on changes Teams will refuse.

**3. Class list.** Everyone already in the team is loaded automatically. Paste or
drop a class list on top of that if some students have not joined the team yet.
These all work:

```
z5100101                          a bare zID
z5100101@ad.unsw.edu.au           an email address
```

```csv
zID,Name,Group                    a spreadsheet export — headers are detected
z5100101,Amara Okafor,Group 1
z5100102,Ben Lindqvist,Group 1
```

Column names it recognises: *zID / student ID / ID*, *email / UPN*, *name* (or
*given* + *surname*), and *group / channel / tutorial / class / stream*. If there
is a group column, a **Use the group column** button appears on the next step and
fills every channel in one click.

**4. Sort into channels.** Drag names between columns. Also available:

- **Click, Shift-click, Ctrl-click** to select several people, then drag them all
  at once or use the **Move to** box (handy if dragging is awkward).
- **Someone in more than one channel** — hold <kbd>Ctrl</kbd> while dragging to add
  them to a second channel instead of moving them, or open their channel list with
  the **…** on the card (a right-click does the same) and tick every channel they
  belong to. A card shows an *in 2* badge when a person is in more than one. The
  **only** button beside a channel in that list puts them in that one alone.
- **+ New private channel** — created when you apply, not before.
- **Spread evenly** — asks how many channels and what to call them, then deals the
  unsorted people out round-robin. Existing channels with those names are reused.
- **Find a person** — filters every column at once.
- **Undo all my changes** — puts the board back to how Teams looks right now.

Owners of a channel show a padlock-ish **owner** tag and cannot be dragged, because
Teams will not let the last owner of a private channel be removed.

The **Theme** button in the top right switches between following your system,
always light, and always dark. It remembers your choice.

**5. Review and apply.** Every single change is listed in plain English before
anything happens, along with warnings worth reading — especially removals, which
also remove access to everything already posted in that channel.

Press **Apply to Teams** and each step runs one at a time with a live log. A CSV
report is saved to the `reports` folder next to the program.

---

## Practice mode

Double-click **`Practice mode (no real changes).cmd`** to run against a fake class
in a fake team. Nothing can reach Microsoft 365 — the real Teams commands are not
even loaded. Use it to learn the tool, to show a colleague, or to check a change
before doing it for real.

---

## What Sortinghat does and does not do

**It does:**

- create private channels, with you as owner
- add people to the team when they are missing (Teams requires this before anyone
  can go into a private channel)
- add and remove private-channel members
- treat "already done" as success, so running it twice is harmless

**It does not:**

- touch standard channels — everyone in a team can see those, so there is nothing
  to sort
- delete channels, delete teams, or remove anyone from the team itself
- remove the last owner of a channel
- send anything anywhere except to Microsoft. The web page is served from your own
  machine on `127.0.0.1`, which is not reachable from the network, and each run
  uses a one-time key in the address so nothing else on your computer can drive it.

---

## When something goes wrong

**"Running scripts is disabled on this system."**
You started the `.ps1` directly. Use `Launch Sortinghat.cmd` instead — it sets the
policy for that one window only.

**The window flashes and closes, or a file "cannot be loaded".**
Windows has marked the files as coming from the internet. Open PowerShell in the
Sortinghat folder and run:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

**The module install fails.**
Usually PSGallery is unreachable through a proxy. Try it by hand:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-Module MicrosoftTeams -Scope CurrentUser -Force -AllowClobber
```

If that still fails, your network is blocking `www.powershellgallery.com` and IT
will need to allow it, or install the module for you.

**No sign-in window appears.**
It is probably behind the browser — check the taskbar. If you signed in to Teams
PowerShell earlier in the same session it may not ask again at all.

**"You are not an owner of this team."**
Ask an existing owner to make you one in Teams (team → ⋯ → Manage team → Members).
Nothing else will work until then.

**A step failed with "user must first be a member of the team".**
Someone was added to the team and to a channel in the same run, and Microsoft had
not finished provisioning them. Press **Retry the failed steps** — a minute later
it almost always works.

**The changes are not showing in Teams.**
Teams caches channel membership. Leave the channel and come back, or press Ctrl+R
in the Teams desktop app. The report tells you what actually succeeded.

**A student's name has a typo and the step failed.**
Fix the class list, go back to step 3, and run again. Everything already applied is
skipped rather than repeated.

---

## What is in the folder

```
Launch Sortinghat.cmd              double-click this
Practice mode (no real changes).cmd rehearsal with a fake class
Start-Sortinghat.ps1               checks the module, starts the local server
src/Server.ps1                     a small web server bound to 127.0.0.1 only
src/Api.ps1                        the JSON endpoints the page calls
src/TeamsApi.ps1                   every call into the MicrosoftTeams module
src/MockTeams.ps1                  the fake tenant used by practice mode
src/ui/                            the page itself (HTML, CSS, one JavaScript file)
reports/                           a CSV per run, created the first time you apply
```

No files are installed anywhere else. Delete the folder and Sortinghat is gone.

---

## A note on student data

Class lists never leave your computer except in the calls to Microsoft that add
people to channels. Nothing is uploaded, logged remotely, or sent to any third
party. The `reports` folder does contain student names and addresses, so treat it
like any other class list — it lives wherever you put the Sortinghat folder.
