# Apps

This repo holds two iPhone apps. Each is a Swift Playgrounds project: open the `.swiftpm` folder on an iPad in Swift Playgrounds (or in Xcode on a Mac) and tap Run.

| App | Folder | What it does |
|---|---|---|
| **Lock In** | `LockIn.swiftpm` | Add the things you want to do, mark the important ones as must-dos, and tap **Lock in**. It draws your list for the day or week: every must-do plus random picks for the rest. |
| **Quiet** | `Quiet.swiftpm` | Post to TikTok without seeing views, likes, comments or followers. (Setup below.) |

## Lock In

- **Tasks tab:** add things you want to do. *Must do* tasks are on every list. *Maybe* tasks get picked at random, and ones you haven't had in a while are more likely to come up.
- **One-time tasks** disappear after you check them off. Regular tasks stay in the pool.
- **Lock in:** draws the list with a quick slot-machine reveal. The list stays fixed until the day (or week) ends.
- **One reroll** per list, only before you've checked anything off. You can turn rerolls off in Settings.
- **Streak:** counts how many days (or weeks) in a row you finished the whole list.
- **Settings:** day or week mode, list size, and an optional reminder notification.

No accounts, servers or setup. Everything is stored on the device.

## Quiet

A minimal iPhone app for posting to TikTok **without seeing views, likes, comments, followers or a feed.**
You pick a video, write a caption, tap **Post**, and see one word: *Posted.*

The app talks to TikTok's official **Content Posting API**. It never asks TikTok for stats, so the numbers aren't hidden in the app: it never has them.

### What's in the app

- **Compose screen** (the only screen you use day to day): video, caption, who can see it, Post.
- **Post or Drafts**: *Post* publishes directly. *Drafts* sends the video to your TikTok inbox to finish later.
- **More options** (collapsed): comments, Duet, Stitch, commercial-content disclosure. TikTok requires these.
- **Settings**: disconnect. That's all.

### Building it on your iPad

You need **Swift Playgrounds** (free, App Store) on the iPad.

1. In Safari, open this repo on GitHub, tap **Code → Download ZIP**, then open the ZIP in the Files app to unzip it.
2. In Files, tap **`Quiet.swiftpm`**. It opens in Swift Playgrounds.
3. Tap **▶︎ Run**. The app runs on the iPad, which works for testing.

**Getting it onto your iPhone:** Swift Playgrounds can't install straight onto a different device. You have two options:
- **TestFlight (iPad only):** join the Apple Developer Program ($99/yr). Then in Swift Playgrounds, open **App Settings → Upload to App Store Connect** and install it on your iPhone through TestFlight.
- **A Mac:** open `Quiet.swiftpm` in Xcode, plug in the iPhone, and press Run. A free Apple ID works for this, but the app has to be re-installed every 7 days.

### One-time TikTok setup

TikTok only lets apps post if they're registered, so you make your own (free) developer app:

1. Go to **developers.tiktok.com**, sign in, and **create an app**.
2. Add the **Login Kit** and **Content Posting API** products. In Content Posting API, turn on **Direct Post**.
3. Make sure these scopes are enabled: `user.info.basic`, `video.publish`, `video.upload`.
4. **Host the callback page.** TikTok needs an `https` address to send you back to after you sign in.
   The page is already in this repo at `docs/callback.html`. Enable **GitHub Pages** (Settings → Pages → branch, folder `/docs`). The address will look like
   `https://<your-username>.github.io/quietapp/callback.html`.
   (GitHub Pages on a private repo needs a paid GitHub plan. Otherwise, make the repo public or host that one file anywhere that serves https.)
5. In Login Kit, add that exact address as the **Redirect URI**.
6. Open Quiet and enter the **Client key**, **Client secret** and **Redirect URI**, then tap **Connect TikTok**.

#### Important: "Only me" until TikTok approves your app

TikTok restricts new, unaudited developer apps (including Sandbox): **Direct Post only works if your TikTok account is set to Private** (TikTok app → Profile → ☰ → Settings and privacy → Privacy → Private account). Choosing "Only me" isn't enough on its own. This lasts until you submit the app for TikTok's audit and it's approved.
Until then you can:
- switch your account to Private while testing, then switch it back, or
- use **Drafts**: the video goes to your TikTok inbox, and you publish it from there.

Other TikTok limits: about 15 posts per day per account, and videos must fit the account's maximum length. Quiet checks the length before uploading.

### Privacy notes

- Your keys and sign-in tokens are stored in the iOS **Keychain** on your device.
- Because there's no server, your **client secret is stored in the app**. That's fine for an app only you use. Don't publish this build to the App Store with your secret in it.
- Requested scopes: `user.info.basic` (needed to sign in), `video.publish`, `video.upload`. Quiet does **not** request `user.info.stats` (followers, likes) or `video.list` (views).

### Project layout

```
Quiet.swiftpm/
  Package.swift        App definition (Swift Playgrounds / Xcode)
  QuietApp.swift       Entry point + root routing
  SetupView.swift      First-run: app keys + Connect
  ComposeView.swift    The posting screen, upload progress, "Posted." state
  SettingsView.swift   Disconnect
  AppModel.swift       Sign-in (ASWebAuthenticationSession), token refresh
  TikTokAPI.swift      Content Posting API: creator info, init, chunked upload, status
  Keychain.swift       Secure storage
  Models.swift
docs/callback.html     OAuth bounce page (redirects to quietpost://auth)
```
