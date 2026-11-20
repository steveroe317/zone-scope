## Xcode Project Configuration & Schemes

This project follows modern Xcode best practices for managing multiple platforms, build configurations, and environments. 

### Schemes & Version Control
* **Shared Schemes:** All primary schemes are marked as **Shared** (`Product > Scheme > Manage Schemes`) and committed to version control. This ensures consistency across all development machines.
* **Environment-Based Schemes:** Schemes are divided by *environment* (e.g., `App-Development`, `App-Production`), not by build type. 
  * **Run/Test/Analyze** actions use the `Debug` configuration.
  * **Profile/Archive** actions use the `Release` configuration.
* **Configuration Files:** Build settings are abstracted into plain-text `.xcconfig` files rather than being hardcoded in the `.xcodeproj` file to prevent merge conflicts.

### Multiplatform Targets
* **Single Multiplatform Target:** We use a consolidated multiplatform target (with "Supported Platforms" set to `Any Platform`) rather than maintaining separate targets for iOS, iPadOS, and macOS.
* **Platform Filters:** Platform-specific files are managed using **Platform Filters** in *Build Phases > Compile Sources*, rather than wrapping entire files in `#if os()` conditional compilation blocks.

### Target Structure
* **App-Development Scheme:** Includes the main app, unit tests, UI tests, and any active extensions. "Parallelize Build" and "Find Implicit Dependencies" are enabled for fast feedback.
* **App-Production Scheme:** Streamlined strictly for archiving the final, optimized build for App Store distribution.

### ZoneScope notes
* **Platforms:** The one target is set to Supported Platforms = **iPhone + iPad** (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`) instead of `Any Platform`. This was a deliberate App Store decision (2026-08-15, see `docs/app-store-readiness.md`) so that App Review never lands on a platform with no HealthKit data. If more platforms come back, use the Platform Filters rule above. The target uses a file-system-synchronized group, so a file's filter is set in its target membership.
* **Schemes:** `ZoneScope-Development` (app + `ZoneScopeTests`, runs `ZoneScope.xctestplan`) and `ZoneScope-Production` (archive only). The two environments share the `Debug` and `Release` configurations, and no setting differs between them.
* **Configuration files** live in `Config/`, outside the synchronized `ZoneScope/` folder so they don't get bundled into the app:
  * `Project-Shared.xcconfig` → included by `Project-Debug.xcconfig` / `Project-Release.xcconfig` (project level)
  * `ZoneScope.xcconfig`, `ZoneScopeTests.xcconfig` (target level, used by both configurations)
  * Keep every `buildSettings` block in `project.pbxproj` empty. If Xcode writes a value there after you edit something in the Build Settings UI, move it into the right `.xcconfig` file.
