# Aria Pro Release Checklist

Complete these external steps before submitting Aria 3.9 (build 2).

## App Store Connect

- Create a **Non-Consumable** in-app purchase with product ID `com.hdi200.ariascore.unlimitedscores`.
- Use the reference and display name **Aria Pro**.
- Set the U.S. price to **$9.99** and review Apple's localized storefront prices.
- Enable **Family Sharing** before release.
- Add the localized description: “Unlock every feature Aria offers today.”
- Add the required App Review screenshot and review notes explaining the two-score free allowance.
- Confirm Aria is available on Apple-silicon Macs before advertising Mac access in the paywall. Otherwise, remove the Mac claim before submission.
- Submit the in-app purchase with Aria 3.9 (build 2).

## Grandfathering

- Confirm the last public unlimited release is Aria 3.8 (build 1).
- Do not change `LibraryAccessPolicy.grandfatheredThroughBuild` from `1` unless that public cutoff changes.
- Verify an Apple ID that first acquired build 1 receives **Early Supporter** access after reinstall.
- Verify an Apple ID that first acquires build 2 starts with two free score slots.

## StoreKit and Device Testing

- Use `Products.storekit` for local purchase, cancellation, Ask to Buy, restore, refund, and Family Sharing scenarios.
- Repeat purchase and restore testing against an App Store sandbox account before submission.
- Verify the paywall and allowance UI on iPhone and iPad in portrait and landscape.
- Verify a refunded account keeps all existing scores readable/editable while new additions are gated.

## Open-Source Release

- Complete `OPEN_SOURCE_COMPLIANCE.md` for build 2.
- Confirm GPLv3/App Store distribution compliance with qualified counsel or the applicable MuseScore commercial license.
- Publish and tag the complete corresponding source for the shipped build.
