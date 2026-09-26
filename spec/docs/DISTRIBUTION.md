# Private Distribution

## Recommended path
Apple Developer Program membership + registered iPad + Ad Hoc distribution.

Apple documents Ad Hoc distribution for apps installed on registered devices. Registered devices can be managed in the developer account or via Xcode.

Current Apple documentation:
- Devices overview: https://developer.apple.com/help/account/devices/devices-overview
- Registered-device distribution: https://developer.apple.com/documentation/Xcode/distributing-your-app-to-registered-devices
- Create Ad Hoc profile: https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile

## Steps
1. Join/maintain Apple Developer Program membership.
2. Connect target iPad to Xcode or obtain its UDID.
3. Register the iPad.
4. Create an explicit App ID/bundle identifier.
5. Configure signing.
6. Archive the app.
7. Export using Ad Hoc/custom distribution.
8. Install IPA using Apple-supported tooling for registered devices.
9. Enable Developer Mode on the target iPad if required by the installation method/current OS.

Do not use TestFlight as the permanent deployment path because TestFlight builds expire.
