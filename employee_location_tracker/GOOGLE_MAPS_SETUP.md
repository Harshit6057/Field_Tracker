# Google Maps API Key Setup Guide

## ⚠️ Why Your Map is Blank

The Google Maps widget requires a valid API key. Currently, `android/app/src/main/AndroidManifest.xml` has a placeholder. Follow these steps to get a real key.

---

## **Step 1: Get Your Android SHA-1 Fingerprint**

You already have this from Firebase setup. Run:
```bash
cd android
./gradlew signingReport
```

Look for the **SHA-1** fingerprint (example: `B4:C6:E5:0A:86:3E:83:9C:75:5E:A5:19:15:F3:4D:67:3C:8B:D7:E3`)

---

## **Step 2: Create API Key in Google Cloud Console**

### 2a. Go to Google Cloud Console
- Open: https://console.cloud.google.com/
- Select your Firebase project (`pingme-sales`) from dropdown

### 2b. Enable Google Maps API
1. Click **APIs & Services** → **Library**
2. Search for **"Maps SDK for Android"**
3. Click it and press **ENABLE**

### 2c. Create API Key
1. Go to **APIs & Services** → **Credentials**
2. Click **+ Create Credentials** → **API Key**
3. Copy the new API key (example: `YOUR_GOOGLE_MAPS_API_KEY`)

### 2d. Restrict API Key (Recommended)
1. Click the API key you just created
2. Scroll to **Application restrictions**
3. Select **Android apps**
4. Click **+ Add package name and fingerprint**
5. Enter:
   - **Package name**: `com.example.sales_tracking_app`
   - **SHA-1 fingerprint**: (paste from Step 1)
6. Click **Save**

---

## **Step 3: Add API Key to Your App**

Edit: `android/app/src/main/AndroidManifest.xml`

Find this line:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY" />
```

Replace `YOUR_GOOGLE_MAPS_API_KEY` with **your actual API key** from Step 2c.

---

## **Step 4: Rebuild and Test**

```bash
flutter clean
flutter pub get
flutter run
```

Navigate to **Admin Dashboard** → **Location icon** → **Map View tab**

You should now see the map with markers! 🎉

---

## **Troubleshooting**

| Problem | Solution |
|---------|----------|
| Map still blank | Clear app cache: `adb shell pm clear com.example.sales_tracking_app` |
| "Invalid API key" error | Double-check key matches value in AndroidManifest.xml |
| Map shows "??" tiles | Wait 5-10 min for API key to activate in Google Cloud |
| Wrong package name error | Verify `android/app/src/main/AndroidManifest.xml` has `package="com.example.sales_tracking_app"` at top |

---

## **Found an Issue?**

If the map loads but shows no markers:
1. Ensure you're logged in as **Admin** (Location Tracking only shows in Admin Dashboard)
2. Check that employees have location data (latitude/longitude filled in Firestore)
3. Markers only appear if `employee.latitude != null && employee.longitude != null`

---

**Current Status**: Placeholder API key added to manifest. Replace with your real key from Google Cloud Console to activate the map.
