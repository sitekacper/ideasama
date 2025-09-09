# Instrukcje generacji i konfiguracji keystore Android

## 1. Generacja keystore lokalnie

```bash
# Generowanie nowego keystore (Windows PowerShell)
keytool -genkey -v -keystore .\app-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ideasama-key

# Lub z pełną ścieżką (w katalogu android/)
keytool -genkey -v -keystore D:\PROJEKTY_VIBE_CODING\ideasamaapp\idea_app\android\app-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ideasama-key
```

## 2. Tworzenie pliku key.properties

W katalogu `android/` utwórz plik `key.properties`:

```
storePassword=TwojeHasloKeystore
keyPassword=TwojeHasloKlucza
keyAlias=ideasama-key
storeFile=app-keystore.jks
```

## 3. Aktualizacja .gitignore

Upewnij się, że `android/.gitignore` zawiera:
```
key.properties
*.jks
*.keystore
```

## 4. GitHub Actions (zmienne środowiskowe)

W GitHub repo → Settings → Secrets and variables → Actions dodaj:
- `ANDROID_KEYSTORE_BASE64` - keystore zakodowany w base64
- `ANDROID_KEYSTORE_PASSWORD` - hasło keystore
- `ANDROID_KEY_ALIAS` - alias klucza
- `ANDROID_KEY_PASSWORD` - hasło klucza

```bash
# Kodowanie keystore do base64 (Windows PowerShell)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("app-keystore.jks"))
```

## 5. Weryfikacja konfiguracji

```bash
# Test buildu z podpisem (lokalnie)
cd android
.\gradlew assembleRelease

# Weryfikacja podpisu
jarsigner -verify -verbose -certs .\app\build\outputs\apk\release\app-release.apk
```

## Uwagi bezpieczeństwa
- Nigdy nie commituj plików `.jks`, `.keystore` lub `key.properties`
- Używaj silnych haseł (min. 12 znaków)
- Zrób backup keystore w bezpiecznym miejscu - utrata = niemożność aktualizacji aplikacji w sklepie