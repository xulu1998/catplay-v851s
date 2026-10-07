# Pull request: https://github.com/catplay-labs/catplay/pull/35 (submitted 2026-10-07, fixes #18)

Branch: `keep-paging-last-iphone` (two commits on dbb3ebb). Same changes as
yocto/meta-u5a/recipes-apps/catplay/files/0006 and 0008.

---

**Title:** catplay_carplay_rx_gadget: keep paging the iPhone after the first minute and after a session ends (#18)

**Body:**

Fixes #18, and the related case where the phone does not come back after a session ends.

Found while testing a V851S + RTL8733BS port in a 2024 Kia Sportage (wired-only head unit, Hyundai
Mobis D-Audio), two iPhones on iOS 27.

**1. Phone arrives late.** The last-connect task gives up after 60 s
(`Failed to reconnect to iPhone peer … before invite deadline: br-connection-page-timeout`). A phone
that reaches the car later (it was still in the house) never reconnects; it has to be connected from
the phone's Bluetooth settings. Commit 1 keeps the fast retries for the first minute, then keeps paging
every 10 s until the reconnect succeeds. The task is already dropped once a session is received, which
stops the paging.

**2. Session ends.** The iPhone drops its Bluetooth link once the wireless session is up
(DisableBluetooth). If the session then ends (here: Wi-Fi turned off and on again from Control
Center; the session ended on KeepAliveTimeout and the car went back to the connection screen), nothing
reconnects the phone: it rejoins the adapter's Wi-Fi but CarPlay only comes back after reconnecting
Bluetooth by hand. Commit 2 starts the last-connect task again when a received session ends.

**Testing.** In the car, with both commits: after Wi-Fi off/on the phone reconnects and CarPlay comes
back by itself, without touching the phone. For the late-arrival case I have verified on the adapter
that paging continues after the first minute (log: "… retrying every 10s"), but I have not yet repeated
the walk-to-the-car scenario in the car. Built for armv7 in the catplay-firmware Yocto BSP.

Notes: after the first minute it is one attempt (one page timeout) every 10 s, to leave the radio free
most of the time. I don't know whether other cars or adapters prefer a different interval; happy to
adjust.

---

## Not submitted yet

`rearm-legacy-self-invite` (downstream patch 0007): the case it fixes (CatPlay ending the car session with
"iPhone disconnected while command proxies were inflight", after which a legacy head unit is never
invited again) happened once and has not happened again, so the fix is not confirmed in the car yet.
Submit, or open an issue with the logs, once it has been seen working.
