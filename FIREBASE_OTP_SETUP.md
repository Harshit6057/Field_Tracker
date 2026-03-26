# Firebase OTP Phone Authentication - Complete Setup Guide

## Error You're Getting
```
E/zzb: Failed to initialize reCAPTCHA config: An internal error has occurred. 
[ API key not valid. Please pass a valid API key. ]
```

**Root Cause**: Your app's SHA-1 fingerprint was not registered in Firebase Console, so the API key is being rejected.

---

## Complete Fix - Follow These Steps

### ⚠️ CRITICAL STEP 1: Register SHA-1 in Firebase Console

**Your Debug SHA-1 is:**
```
B4:C6:E5:0A:86:3E:83:9C:75:5E:A5:19:15:F3:4D:67:3C:8B:D7:E3
```

**Steps:**
1. Open: https://console.firebase.google.com/
2. Select project: **pingme-sales**
3. Click ⚙️ **Settings** (top-left) → **Project Settings**
4. Go to **"Your apps"** tab
5. Click **Android app** (com.example.sales_tracking_app)
6. Scroll to **"SHA certificate fingerprints"**
7. Click **"Add Fingerprint"** button
8. Paste the SHA-1 above
9. Click **"Save"** button
10. **Wait 30 seconds for Firebase to update**

---

### ✅ STEP 2: Changes Already Completed

The following have been added to your project:

**New Files:**
- ✓ `lib/screens/otp_verification_screen.dart` - OTP input screen with 6 digit fields
- ✓ Updated `lib/screens/login_screen.dart` - Phone OTP integration
- ✓ Updated `AndroidManifest.xml` - Added SMS permissions

**Permissions Added:**
```xml
<uses-permission android:name="android.permission.READ_SMS" />
<uses-permission android:name="android.permission.RECEIVE_SMS" />
<uses-permission android:name="com.google.android.gms.permission.AD_ID" />
```

---

### 🔧 STEP 3: Testing OTP Login

**Option A: With Real Phone Number (Recommended)**
1. Add a real phone number (+91XXXXXXXXXX)
2. Real SMS will be sent to that phone
3. Enter the OTP received

**Option B: Test Phone Numbers (For Development)**
1. Go to Firebase Console → **Authentication**
2. Click **Phone** tab
3. Scroll to **"Phone numbers for testing"**
4. Add test numbers with fixed OTPs:
   - Phone: +919876543210
   - OTP: 123456
5. Use these in your app for testing

---

### 📋 STEP 4: Firebase Configuration Checklist

- [ ] SHA-1 registered in Firebase Console
- [ ] Phone authentication enabled (Firebase → Authentication → Phone)
- [ ] Blaze plan active (needed for SMS sending)
- [ ] Google Play Services updated on test device
- [ ] Internet permission enabled ✓ (already done)

---

### ⚡ STEP 5: Clean Build (Do This After Firebase Update)

Run in terminal:

```bash
cd employee_location_tracker

# Clean and rebuild
flutter clean
flutter pub get

# Rebuild Android
cd android
./gradlew clean  # or gradlew.bat clean (Windows)
cd ..

# Run app
flutter run
```

---

## How Phone OTP Login Works Now

1. **Employee** enters name + phone number
2. Clicks **"Continue as Employee"**
3. Firebase sends **6-digit OTP** via SMS
4. Screen shows **OTP entry form** with 6 digit fields
5. Auto-focuses to next field after each digit
6. Employee enters all 6 digits
7. Firebase verifies OTP
8. Employee is logged in → **Employee Dashboard**

---

## Troubleshooting

### Still getting "API key not valid" error?
- ✓ Did you wait 30 seconds after adding SHA-1?
- ✓ Reload Firebase Console page (Ctrl+F5)
- ✓ Close Flutter app from running apps
- ✓ Run: `flutter clean && flutter run`

### OTP not arriving?
- ✓ Check internet connection
- ✓ Verify phone number has +91 prefix
- ✓ Check Device spam/SMS folder
- ✓ Wait up to 60 seconds
- ✓ Use **Resend OTP** button if available

### Google Play Services Error?
- This is normal on emulator/debug builds
- On physical device with Google Play Services:
  - Update Google Play Services on device
  - Go to Settings → Apps → Google Play Services → Update

---

## Production Notes (When Ready)

For production release:

1. **Generate Release Key**
   ```bash
   keytool -genkey -v -keystore my-release-key.keystore \
   -keyalg RSA -keysize 2048 -validity 10000 -alias my-key-alias
   ```

2. **Get Release SHA-1**
   ```bash
   keytool -list -v -keystore my-release-key.keystore \
   -alias my-key-alias
   ```

3. **Add to Firebase** (same process as debug SHA-1)

4. **SMS Costs** (Blaze Plan):
   - First 50,000 SMS per month: **FREE**
   - After 50,000: **$0.04 per verification**

---

## Contact Support

If issues persist after these steps:

1. Check Firebase Console → Logs
2. Verify `google-services.json` hasn't changed
3. Ensure Blaze billing is enabled
4. Restart phone and clear app cache

---

**Last Updated**: March 24, 2026
**Project**: Employee Location Tracker
