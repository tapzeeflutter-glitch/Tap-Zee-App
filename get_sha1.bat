@echo off
echo === Google Sign-in Android Setup Helper ===
echo.

echo 1. Getting SHA-1 fingerprint for DEBUG build:
echo    (This is what you need to add to Firebase Console)
echo.

cd android

if exist "gradlew.bat" (
    echo Running: gradlew.bat signingReport
    echo.
    gradlew.bat signingReport | findstr "SHA1:"
) else (
    echo gradlew.bat not found. Trying alternative method...
    echo.
    echo Debug keystore location: %USERPROFILE%\.android\debug.keystore
    echo Run this command manually:
    echo keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr SHA1
)

echo.
echo 2. Next steps:
echo    a) Copy the SHA1 fingerprint from above
echo    b) Go to Firebase Console ^> Project Settings ^> Your Android App
echo    c) Click 'Add fingerprint' and paste the SHA1
echo    d) Download the google-services.json file
echo    e) Replace android/app/google-services.json.template with the downloaded file
echo.
echo 3. Test the setup:
echo    flutter run
echo.

pause
