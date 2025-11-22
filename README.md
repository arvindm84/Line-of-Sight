# Visual Guide - Flutter App

Real-time visual guide application for blind users built with Flutter.

## Features

✅ **Camera Preview** - Full-screen rear camera  
✅ **GPS Tracking** - Continuous location updates  
✅ **Nearby POIs** - Restaurants, shops, attractions via OpenStreetMap  
✅ **Auto-Scan** - Updates every 5 seconds  
✅ **Cross-Platform** - Android & iOS from single codebase

---

## Setup & Run

### 1. Install Flutter

Download from: https://docs.flutter.dev/get-started/install/windows

Add to PATH: `C:\flutter\bin`

Verify: `flutter doctor`

### 2. Get Dependencies

```bash
cd C:\Users\Arvind Marella\Projects\MadHacks
flutter pub get
```

### 3. Run App

```bash
flutter run
```

**On physical device:**
- Enable USB Debugging
- Connect via USB
- Run command above

**On emulator:**
- Start Android emulator
- Run command above

---

## Quick Commands

```bash
flutter pub get          # Get dependencies
flutter run              # Run app
flutter run --release    # Release mode
flutter build apk        # Build APK
flutter devices          # List devices
flutter doctor           # Check setup
```

---

## Project Structure

```
lib/
├── main.dart                # Entry point
├── services/
│   ├── location_service.dart
│   └── osm_service.dart
├── models/
│   └── poi.dart
├── screens/
│   └── main_screen.dart
└── widgets/
    └── poi_list.dart
```

---

**Ready to run:** `flutter pub get` then `flutter run` 🚀
