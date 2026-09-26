# Starter Project Setup

The source skeleton is intentionally not wrapped in a generated `.xcodeproj`; the developer should create a clean Xcode iPadOS application project so signing, deployment target, entitlements, and current Xcode project metadata are generated correctly.

1. Create a new Xcode iOS App project named `ClassicMail`.
2. Interface: UIKit / Storyboard off if offered; lifecycle may use scenes.
3. Language: Swift.
4. Deployment target: iPadOS 15+ initially.
5. Device family: iPad only for v1.
6. Delete generated view-controller UI and copy files from `starter/ClassicMail/` into matching groups.
7. Add SwiftMail through Swift Package Manager:
   `https://github.com/Cocoanetics/SwiftMail`
8. Confirm the actual SwiftMail package manifest's iOS minimum before finalizing deployment target.
9. Run mock mode first.
10. Do not begin network integration until the UI prototype is approved.
