# Tap-Zee-App

---

## **Prerequisites**

Before you begin, make sure you have the following installed:

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [VS Code](https://code.visualstudio.com/) or Android Studio
- [Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code) and [Flutter extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter) for VS Code
- Android Emulator or a physical device connected for testing
- (Optional) [Xcode](https://developer.apple.com/xcode/) for iOS development (Mac only)

---

## **Installation**

### 1. Clone the repository

```bash
git clone https://github.com/tapzeeflutter-glitch/Tap-Zee-App.git
cd Tap-Zee-App
```

### 2. Install Dependencies

Fetch all required packages:

```bash
flutter pub get
```

### 3. Run the App

#### Option 1: Using VS Code

1. Open the project in VS Code.
2. Select your target device or emulator from the bottom-right corner.
3. Press F5 or go to **Run → Start Debugging**.

#### Option 2: Using Terminal

```bash
flutter run
```

This will build and launch the app on the connected device.

---

## **Troubleshooting**

- Run `flutter doctor` to verify environment setup.
- Make sure the device/emulator is running before `flutter run`.
- If dependencies fail:
  ```bash
  flutter clean
  flutter pub get
  ```
