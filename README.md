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

1. **PowerShell.**
   - *Windows:* nothing to do. Windows 10 and 11 both ship with PowerShell 5.1.
   - *macOS:* PowerShell 7 is not included, so install it once —
     `brew install --cask powershell`, or the `.pkg` from
     [the PowerShell releases page](https://github.com/PowerShell/PowerShell/releases)
     (`osx-arm64` on Apple Silicon, `osx-x64` on Intel). Microsoft supports the
     Teams module on PowerShell 7.2 and later on every platform.
2. To be an **owner** of the team you want to change. Sortinghat can only do what
   you could already do by hand in Teams.
3. An internet connection. The first run installs Microsoft's own Teams PowerShell
   module under your user account — no administrator rights, no IT ticket.

You do **not** need an app registration, an API key, or anything from IT.

---

## Running it

- **Windows:** double-click **`Windows - Start Sortinghat.cmd`**.
- **macOS:** double-click **`Mac - Start Sortinghat.command`**.

Never run it before? Open the **Practice run** file for your computer first —
a fake class in a fake team, where nothing real can change.

A console window (Terminal on a Mac) opens and stays open — that window *is* the
program, so leave it alone while you work. Your browser opens on the Sortinghat
page.

To stop: press **Finish** in the browser, or just close the console window.

> **First time only.** Both operating systems treat files downloaded from the
> internet with suspicion.
>
> *Windows:* right-click the zip *before* extracting it, choose **Properties**,
> tick **Unblock**, then extract.
>
> *macOS:* the first launch is blocked as coming from an unidentified developer.
> Right-click `Mac - Start Sortinghat.command`, choose **Open**, then **Open**
> again in the dialog. You only do this once. (If macOS will not offer *Open* at all, run
> `xattr -dr com.apple.quarantine .` in the Sortinghat folder.)

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

Double-click the **Practice run** file for your computer to work against a fake
class in a fake team. Nothing can reach Microsoft 365 — the real Teams commands are not
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
On Windows it is probably behind the browser — check the taskbar. On a Mac there
is no Web Account Manager, so if the sign-in page does not come up Sortinghat
falls back to a **device code**: switch to the Terminal window, which prints a
short code and a link to enter it at. You can force that flow from the start with
`./app/Start-Sortinghat.ps1 -DeviceCode`.

**macOS: "command not found: pwsh".**
PowerShell 7 is not installed yet — see *Before you start* above. The launcher
prints the same instructions.

**"You are not an owner of this team."**
Ask an existing owner to make you one in Teams (team → ⋯ → Manage team → Members).
Nothing else will work until then.

**Creating a channel failed, but the channel is there in Teams.**
Teams sometimes returns an error for a channel it has in fact just created.
Sortinghat now checks whether the channel exists before calling it a failure, so
this should report as *already in place* rather than red. If you are on an older
copy and saw it fail: look in Teams first — if the channel is there, the run
worked and pressing **Retry** will only produce a second, confusing error.

**Creating a channel failed with a "BadRequest" from the templates backend.**
Almost always the name. Teams reserves the name of a **deleted** channel
permanently — by design, for information-protection reasons — so a channel called
*Group 3* that was deleted last term can never be recreated under that name. Use a
variant (*Group 3b*, *Group 3 T3*) instead.

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

Only the things you might double-click sit at the top level:

```
START HERE.txt                        read this first
Windows - Start Sortinghat.cmd        double-click this on Windows
Windows - Practice run (changes nothing).cmd
Mac - Start Sortinghat.command        double-click this on a Mac
Mac - Practice run (changes nothing).command
README.md                             this file
reports/                              a CSV per run, created the first time you apply
app/                                  the program itself - nothing here to run
```

Inside `app/`:

```
Start-Sortinghat.ps1               checks the module, starts the local server
Server.ps1                         a small web server bound to 127.0.0.1 only
Api.ps1                            the JSON endpoints the page calls
TeamsApi.ps1                       every call into the MicrosoftTeams module
MockTeams.ps1                      the fake tenant used by the practice run
ui/                                the page itself (HTML, CSS, one JavaScript file)
```

No files are installed anywhere else. Delete the folder and Sortinghat is gone.

---

## A note on student data

Class lists never leave your computer except in the calls to Microsoft that add
people to channels. Nothing is uploaded, logged remotely, or sent to any third
party. The `reports` folder does contain student names and addresses, so treat it
like any other class list — it lives wherever you put the Sortinghat folder.

---

© 2026 · Developed by **Giuseppe Daniele Ibello**, UNSW Business School — PhD
Candidate in Information Systems & Technology Management
· [g.ibello@unsw.edu.au](mailto:g.ibello@unsw.edu.au)
· [giuseppe.ibello06@gmail.com](mailto:giuseppe.ibello06@gmail.com)
