# 💊 Pharmacy Expiry Scanner — Setup Guide

A Flutter Web PWA that runs in iPhone Safari (no App Store needed).  
Scan barcodes → track medicine batches → get expiry alerts.

---

## 📁 Project File Structure

```
pharmacy_expiry_scanner/
├── lib/
│   ├── main.dart                          ← App entry point + bottom nav
│   ├── firebase_options.dart              ← 🔴 PASTE YOUR FIREBASE CONFIG HERE
│   ├── models/
│   │   └── pharmacy_item.dart             ← PharmacyItem + Batch data models
│   ├── services/
│   │   └── firestore_service.dart         ← All Firestore CRUD operations
│   ├── screens/
│   │   ├── dashboard_screen.dart          ← Home: stats + expiry alerts
│   │   ├── scanner_screen.dart            ← Camera barcode scanner
│   │   ├── add_medicine_screen.dart       ← Add new medicine + first batch
│   │   ├── update_medicine_screen.dart    ← View/edit medicine + manage batches
│   │   ├── inventory_screen.dart          ← Full inventory list + filters
│   │   └── reports_screen.dart            ← Reports + print/AirPrint
│   ├── widgets/
│   │   ├── batch_card.dart                ← Batch detail card widget
│   │   └── form_field_label.dart          ← Form label widget
│   └── utils/
│       └── app_theme.dart                 ← Colors, theme, categories
├── web/
│   ├── index.html                         ← PWA HTML with iOS meta tags
│   └── manifest.json                      ← PWA manifest
├── firestore.rules                        ← Firestore security rules
├── firestore.indexes.json                 ← Firestore indexes
└── pubspec.yaml                           ← Dependencies
```

---

## 🚀 Step 1 — Firebase Setup

### 1a. Create Firebase Project
1. Go to **https://console.firebase.google.com**
2. Click **"Add project"** → name it (e.g. `pharmacy-scanner`)
3. Disable Google Analytics (optional) → **Create project**

### 1b. Enable Firestore
1. In Firebase Console → **Build → Firestore Database**
2. Click **"Create database"**
3. Select **"Start in test mode"** (you'll update rules later)
4. Choose your region (pick closest to you) → **Enable**

### 1c. Register Web App
1. Firebase Console → **Project Overview** → Click the **`</>`** (Web) icon
2. App nickname: `Pharmacy Scanner Web` → **Register app**
3. You'll see a config like this — **COPY IT**:

```javascript
const firebaseConfig = {
  apiKey: "AIzaSy...",
  authDomain: "pharmacy-scanner.firebaseapp.com",
  projectId: "pharmacy-scanner",
  storageBucket: "pharmacy-scanner.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123456789:web:abc123",
  measurementId: "G-XXXXXX"
};
```

### 1d. Paste Config into Flutter
Open `lib/firebase_options.dart` and replace the placeholder values:

```dart
static const FirebaseOptions web = FirebaseOptions(
  apiKey: 'AIzaSy...',          // ← your apiKey
  appId: '1:123:web:abc',       // ← your appId
  messagingSenderId: '123456',   // ← your messagingSenderId
  projectId: 'pharmacy-scanner', // ← your projectId
  authDomain: 'pharmacy-scanner.firebaseapp.com',
  storageBucket: 'pharmacy-scanner.appspot.com',
  measurementId: 'G-XXXXXX',    // ← your measurementId
);
```

---

## 🔧 Step 2 — Flutter Setup

### 2a. Install Flutter
```bash
# macOS
brew install flutter

# Or download from https://flutter.dev/docs/get-started/install
```

### 2b. Enable Web Support
```bash
flutter config --enable-web
flutter doctor  # check everything is OK
```

### 2c. Install Dependencies
```bash
cd pharmacy_expiry_scanner
flutter pub get
```

### 2d. Install FlutterFire CLI & Configure
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure (auto-generates firebase_options.dart)
flutterfire configure --project=YOUR_PROJECT_ID
```

> **Alternative:** If you prefer, just manually paste your Firebase config into
> `lib/firebase_options.dart` as shown in Step 1d — no CLI needed.

---

## 🏗️ Step 3 — Run & Build

### Run locally (development)
```bash
flutter run -d chrome
# Or for Safari-like testing:
flutter run -d web-server --web-port=8080
# Then open http://localhost:8080 in Safari on your Mac
```

### Build for production
```bash
flutter build web --release --web-renderer canvaskit
# Output goes to: build/web/
```

---

## ☁️ Step 4 — Deploy (iPhone-accessible URL)

### Option A: Firebase Hosting (Recommended — Free)
```bash
# Install Firebase CLI
npm install -g firebase-tools
firebase login

# Initialize hosting in project root
firebase init hosting
# ✅ Use existing project
# ✅ Public directory: build/web
# ✅ Single-page app: YES
# ✅ Don't overwrite index.html: NO

# Build and deploy
flutter build web --release
firebase deploy --only hosting
```
Your app will be at: `https://YOUR_PROJECT_ID.web.app`

### Option B: Netlify (Drag & drop)
1. Run `flutter build web --release`
2. Go to **https://netlify.com**
3. Drag the `build/web` folder onto the Netlify dashboard
4. Done! You get a URL like `https://abc123.netlify.app`

### Option C: Vercel
```bash
npm install -g vercel
flutter build web --release
cd build/web
vercel
```

---

## 📱 Step 5 — Install as PWA on iPhone Safari

1. Open Safari on iPhone and navigate to your deployed URL
2. Tap the **Share** button (box with arrow)
3. Scroll down → tap **"Add to Home Screen"**
4. Name it "Rx Scanner" → tap **Add**
5. The app icon appears on your home screen — works like a native app!

### iOS Safari Camera Permission
- Camera access is requested automatically when you open the scanner
- On first use, Safari will ask "Allow pharmacy-scanner.web.app to access your camera?" → tap **Allow**
- If you accidentally denied it: **Settings → Safari → Camera → Allow**

---

## 🗄️ Firestore Data Model

```
pharmacy_items/                          (collection)
  {barcode}/                             (document — barcode is the ID)
    medicineName: "Amoxicillin 500mg"
    barcode:      "1234567890123"
    category:     "Antibiotics"
    createdAt:    Timestamp
    updatedAt:    Timestamp

    batches/                             (subcollection)
      {batchId}/                         (document — UUID)
        batchNo:       "BT-2024-001"
        expiryDate:    Timestamp
        quantity:      100
        purchasePrice: 45.00
        salePrice:     65.00
        supplier:      "MedSupply Co."
        createdAt:     Timestamp
        updatedAt:     Timestamp
```

---

## 🔐 Step 6 — Deploy Firestore Rules

After testing, deploy your security rules:

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

---

## 📋 Features Summary

| Feature | Details |
|---|---|
| **Barcode Scanner** | Uses device camera via `mobile_scanner` package |
| **Smart Routing** | New barcode → Add screen; Existing → Update screen |
| **Multi-batch Support** | Each medicine can have unlimited batches |
| **Dashboard** | Total items, expired count, expiring in 30d, low stock |
| **Inventory** | Search, filter by category/status, tap to manage |
| **Reports** | Inventory / Expired / Expiring Soon tabs with print |
| **Print/AirPrint** | Uses `printing` package — works with iOS AirPrint |
| **PWA** | Installable on iPhone Safari, works offline for UI |

---

## 🐛 Troubleshooting

### Camera doesn't work on iPhone
- Must be served over **HTTPS** — local HTTP won't work for camera
- Use Firebase Hosting or Netlify (both are HTTPS by default)
- Check Safari camera permission: **Settings → Safari → Camera**

### Barcode not detected
- Ensure good lighting
- Hold steady — the scanner needs a clear view of the barcode
- Use the "Enter Manually" keyboard button as fallback

### Firebase connection errors
- Double-check your `firebase_options.dart` values match your console
- Ensure Firestore is created (not just the Firebase project)
- Check browser console for specific error messages

### Build errors
```bash
flutter clean
flutter pub get
flutter build web --release
```

---

## 📦 Key Packages Used

| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | ^2.24.2 | Firebase initialization |
| `cloud_firestore` | ^4.14.0 | Firestore database |
| `mobile_scanner` | ^3.5.6 | Camera barcode scanning |
| `pdf` | ^3.10.7 | PDF generation for reports |
| `printing` | ^5.12.0 | iOS AirPrint / browser print |
| `intl` | ^0.18.1 | Date formatting |
| `uuid` | ^4.2.2 | Unique batch IDs |

---

## 🎨 Design System

| Color | Hex | Usage |
|---|---|---|
| Primary | `#0D7377` | App bar, buttons, accents |
| Primary Light | `#14BDBC` | Scanner overlay, gradients |
| Expired | `#D32F2F` | Expired batch indicators |
| Expiring Soon | `#F57C00` | 30-day warning indicators |
| Healthy | `#2E7D32` | Valid stock indicators |
| Low Stock | `#7B1FA2` | Low quantity warnings |
