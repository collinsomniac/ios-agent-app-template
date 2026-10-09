# Human steps (one-time, ~15 minutes)

The agent can do everything else. Do these when the agent asks; each step says how to confirm it worked.

## 1. LocalDevVPN (App Store)
Install **LocalDevVPN** from the App Store. SideStore uses it to install apps on the phone itself.
*Done when:* the app is installed (you don't need to open it yet).

## 2. SideInstaller → SideStore
1. Open **https://sideinstaller.net/** (official) — or the repo **github.com/FrizzleM/SideInstaller**. ⚠️ `sideinstaller.com` is a **fake** site; don't use it.
2. Install SideInstaller with one of the certificates offered there.
3. Turn on LocalDevVPN, open SideInstaller, sign in with your Apple ID, tap **Install SideStore**.
*Done when:* SideStore opens and shows your Apple ID under Settings.

Your Apple ID is used only to create a free development certificate on your account. It's the same thing Xcode does on a Mac.

## 3. Add the app's source in SideStore
SideStore → **Sources** → **+** → paste the URL the agent gives you:
`https://github.com/<owner>/<repo>/releases/latest/download/sidestore-source.json`
Then **Browse** → the app → **Get**.
*Done when:* the app's icon is on your home screen and it opens.

Updates from then on: SideStore → **My Apps** → **Update**. (One tap per build.)

## 4. (Only for apps that need lots of RAM) increased memory limit
SideStore currently drops the `increased-memory-limit` entitlement. If the agent says the app needs >3 GB:
- install **GetMoreRam** (github.com/hugeBlack/GetMoreRam) via SideStore, sign in, refresh App IDs, tap the app's ID → **Add Increased Memory Limit**, then reinstall the app from SideStore.
*Done when:* the app's Device screen (or `GET /device`) lists `com.apple.developer.kernel.increased-memory-limit`.

## 5. Give the agent the control token
Open the app → **Control** tab → **Copy token** → paste it to the agent. It lets the agent call the app's local API on `127.0.0.1`; nothing is exposed to the network.

## Every 7 days
Nothing, if SideStore's background refresh works. If an app stops opening, open SideStore (with LocalDevVPN on) and tap **Refresh All**.
