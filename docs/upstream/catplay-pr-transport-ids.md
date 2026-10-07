# Pull request: https://github.com/catplay-labs/catplay/pull/34 (submitted 2026-10-07)

Branch: `fix-iap2-transport-identifiers` (two commits on dbb3ebb). Same changes as
yocto/meta-u5a/recipes-apps/catplay/files/0002 and 0003.

---

**Title:** catplay_carplay_tx_gadget: send transport IDs and language when the head unit asks (Kia/Hyundai D-Audio)

**Body:**

Hi, I'm porting CatPlay to a V851S + RTL8733BS adapter (LY2734 "smartBox", same LY family as the
ly5190 V821B boxes) and testing it in a **2024 Kia Sportage** (Canada). Head unit: Hyundai Mobis
D-Audio (telechips `wp_daudioplus`), iAP2 identity name "Sportage", model "NQ5", manufacturer
"HYUNDAI MOBIS". Wired CarPlay only.

**Symptom.** iAP2 identification and authentication succeed, the car shows "Reading USB" for about two
seconds, and then nothing: it never invites the device over `_carplay-ctrl`, and the tx gadget stays in
WaitingForInvite.

**Cause.** This head unit lists DeviceTransportIdentifierNotification (0x4E0E) and DeviceLanguageUpdate
(0x4E0A) in `IdentificationInformation.messages_received_from_device` and waits for them. Sending both
right after AuthenticationSucceeded makes it invite the device; wireless CarPlay then works (screen,
audio, touch). I did not isolate which of the two it actually needs.

**Commits**

1. `catplay_csm: fix IdentificationInformation::unpack_ids and has_id`: `unpack_ids` loops on the
   length of its own (empty) output, so it always returns an empty list (the "Modern CarPlay" check in
   carplay_client_session.rs is never true). `has_id` never advances its index and compares a byte
   index with `len / 2`, so it spins forever once the list has two or more IDs and the first does not
   match (no callers yet). Both now use `chunks_exact(2)`; tests in `tests/ident_test.rs` (with the old
   code the round-trip test fails and the `has_id` test hangs).
2. `catplay_carplay_tx_gadget: send transport IDs and language when the accessory asks`: only when the
   accessory lists them. The Bluetooth transport ID is the Bonjour ID of the CarPlay-control
   advertisement and the USB one is the g_iphone serial (read from sysfs), so they match what the car
   already sees; language is "en". `CarPlayClientSession::new(bonjour_id, iphone_instance)` replaces
   `default()` in client.rs. DeviceTimeUpdate is still not sent.

**Testing**

- This exact version has been running in the car since 2026-10-07 over several drives, with two iPhones
  (iPhone 14 Pro Max and 17 Pro Max, iOS 27): every time the adapter is plugged in, the head unit
  invites it and CarPlay starts as soon as a phone is connected (screen, audio, touch). An earlier
  version with the same message contents had been in the car since 2026-10-06.
- Built for armv7 in the catplay-firmware Yocto BSP; `cargo test -p catplay_csm --test ident_test`
  passes (with the old code the round-trip test fails and the `has_id` test hangs).
- Logs of the car session (identification, the invite, the CarPlay setup) are available if useful.

Happy to change the approach if you'd prefer this handled elsewhere. Once it's in, I can send a README
line for the car compatibility table.

---

## Notes for the maintainer's style (from earlier PRs)

The maintainer (ninja-) merges small, root-caused changes and rejects heuristics (PR #20). Keep the PR to
these two commits, answer review questions with logs, and don't add unrelated changes.
